import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../app/states/app.dart';
import 'connect.dart';
import 'theme.dart';
import 'updater.dart' show kCtUpdateRepo;

final _logger = Logger('CtDeploy');

/// Мастер «Свой сервер»: приложение подключается к VPS по SSH, запускает server/deploy.sh
/// и показывает прогресс. В конце сервер сразу добавляется в приложение, вход выполнен.
class CtDeployScreen extends StatefulWidget {
  const CtDeployScreen({super.key});

  @override
  State<CtDeployScreen> createState() => _CtDeployScreenState();
}

enum _Phase { form, running, done, failed }

class _CtDeployScreenState extends State<CtDeployScreen> {
  final _form = GlobalKey<FormState>();
  final _ip = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _rootPass = TextEditingController();
  final _domain = TextEditingController();
  final _email = TextEditingController();
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController();
  bool _showRoot = false, _showPass = false;

  _Phase _phase = _Phase.form;
  double _progress = 0;
  String _step = '';
  String? _error;
  String? _url;
  final List<String> _lines = [];
  bool _showLog = false;
  String? _dnsInfo;
  bool? _dnsOk;
  SSHClient? _client;
  bool _cancelled = false;

  @override
  void dispose() {
    _cancelled = true;
    _client?.close();
    for (final c in [_ip, _port, _rootPass, _domain, _email, _user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _domainClean => _domain.text.trim().toLowerCase().replaceAll(RegExp(r'^https?://'), '').replaceAll('/', '');

  Future<void> _checkDns() async {
    final d = _domainClean, ip = _ip.text.trim();
    if (d.isEmpty) return;
    setState(() {
      _dnsOk = null;
      _dnsInfo = 'Проверяю…';
    });
    try {
      final res = await InternetAddress.lookup(d, type: InternetAddressType.IPv4);
      final got = res.map((a) => a.address).toSet();
      setState(() {
        _dnsOk = ip.isNotEmpty && got.contains(ip);
        _dnsInfo = _dnsOk == true
            ? '$d → ${got.join(', ')} — запись верная'
            : '$d → ${got.join(', ')}${ip.isNotEmpty ? ', а сервер $ip — исправьте A-запись или подождите' : ''}';
      });
    } catch (_) {
      setState(() {
        _dnsOk = false;
        _dnsInfo = 'У домена $d пока нет A-записи. Создайте её и подождите 5–30 минут';
      });
    }
  }

  static String _q(String v) => "'${v.replaceAll("'", "'\\''")}'";

  Future<SSHClient> _connect() async {
    final socket = await SSHSocket.connect(_ip.text.trim(), int.tryParse(_port.text.trim()) ?? 22,
        timeout: const Duration(seconds: 20));
    final client = SSHClient(
      socket,
      username: 'root',
      onPasswordRequest: () => _rootPass.text,
      // первый вход на свежий VPS: ключ хоста ещё не известен — доверяем при первом подключении
      onVerifyHostKey: (type, fingerprint) => true,
    );
    await client.authenticated;
    return client;
  }

  Future<void> _start() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _phase = _Phase.running;
      _progress = 0.01;
      _step = 'Подключаюсь к серверу ${_ip.text.trim()}…';
      _error = null;
      _lines.clear();
    });
    try {
      final client = await _connect();
      _client = client;
      _addLog('SSH: вход выполнен');
      final env = [
        'CT_DOMAIN=${_q(_domainClean)}',
        'CT_USER=${_q(_user.text.trim())}',
        'CT_PASS=${_q(_pass.text)}',
        'CT_EMAIL=${_q(_email.text.trim())}',
        'CT_REPO=${_q('https://raw.githubusercontent.com/$kCtUpdateRepo/main')}',
      ].join('\n');
      // параметры передаём через stdin в файл (не видны в списке процессов), установщик работает
      // отдельно от SSH-сессии — если телефон уснёт, установка продолжится, а мы потом догоним по логу
      // идёт ли уже установка — по PID-файлу (раньше «pgrep -f ct-deploy.sh» находил саму эту
      // команду, в её тексте есть «ct-deploy.sh», — и мастер вечно «подключался» к несуществующей установке)
      final launch = await client.execute('umask 077; cat > /root/.ct-deploy.env; '
          'if [ -f /root/.ct-deploy.pid ] && kill -0 "\$(cat /root/.ct-deploy.pid)" 2>/dev/null; then echo already; else '
          'curl -fsSL https://raw.githubusercontent.com/$kCtUpdateRepo/main/server/deploy.sh -o /root/ct-deploy.sh '
          '&& (setsid nohup bash -c \'echo \$\$ > /root/.ct-deploy.pid; exec bash /root/ct-deploy.sh\' > /var/log/ct-deploy.log 2>&1 < /dev/null &) && echo started '
          '|| echo "##ERR Не удалось скачать установщик — у сервера нет доступа к GitHub?"; fi');
      launch.stdin.add(utf8.encode('$env\n'));
      await launch.stdin.close();
      final out = await utf8.decodeStream(launch.stdout.cast<List<int>>());
      await launch.done;
      if (out.contains('##ERR')) throw out.substring(out.indexOf('##ERR') + 6).trim();
      _addLog(out.contains('already') ? 'Установка уже идёт — подключаюсь к ней' : 'Установщик запущен');
      await _follow();
    } catch (e) {
      _fail('$e');
    }
  }

  /// Читаем лог установки; при обрыве соединения переподключаемся.
  Future<void> _follow() async {
    var attempts = 0;
    while (!_cancelled && _phase == _Phase.running) {
      try {
        _client ??= await _connect();
        final s = await _client!.execute('tail -n +1 -F /var/log/ct-deploy.log 2>/dev/null');
        final lines = s.stdout.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
        _lines.clear();
        await for (final l in lines) {
          if (_handle(l)) break;
        }
        s.close();
        if (_phase != _Phase.running) break;
      } catch (e) {
        _lines.add('… связь прервалась: $e');
      }
      _client?.close();
      _client = null;
      if (_phase != _Phase.running || _cancelled) break;
      if (++attempts > 30) {
        _fail('Потеряна связь с сервером. Установка может продолжаться — откройте мастер позже');
        break;
      }
      setState(() => _step = 'Переподключаюсь…');
      await Future.delayed(const Duration(seconds: 5));
    }
    _client?.close();
    _client = null;
  }

  /// true — установка завершена (успех или ошибка)
  bool _handle(String l) {
    if (l.startsWith('##P ')) {
      final m = RegExp(r'^##P (\d+) (.*)$').firstMatch(l);
      if (m != null) {
        setState(() {
          _progress = (int.parse(m.group(1)!) / 100).clamp(0.01, 1.0);
          _step = m.group(2)!;
        });
        _addLog('${m.group(1)}% ${m.group(2)}');
      }
      return false;
    }
    if (l.startsWith('##ERR')) {
      _fail(l.substring(5).trim());
      return true;
    }
    if (l.startsWith('##DONE')) {
      try {
        final j = jsonDecode(l.substring(6).trim()) as Map;
        _url = j['url'] as String?;
      } catch (_) {}
      _finish();
      return true;
    }
    if (l.trim().isNotEmpty) _addLog(l);
    return false;
  }

  void _addLog(String l) {
    _lines.add(l);
    if (_lines.length > 400) _lines.removeAt(0);
    if (mounted && _showLog) setState(() {});
  }

  void _fail(String e) {
    _logger.warning('deploy failed: $e');
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _error = e;
    });
  }

  Future<void> _finish() async {
    setState(() {
      _progress = 1;
      _step = 'Подключаю приложение к серверу…';
    });
    try {
      final url = _url ?? 'https://$_domainClean';
      await ctConnectServer(
        url: url,
        app: context.read<AppCubit>(),
        siteUser: _user.text.trim(),
        sitePass: _pass.text,
        user: _user.text.trim(),
        pass: _pass.text,
      );
      if (mounted) setState(() => _phase = _Phase.done);
    } on CtConnectError catch (e) {
      // сервер готов, но вход не удался — сервер всё равно добавлен без аккаунта
      try {
        await ctConnectServer(
            url: _url ?? 'https://$_domainClean',
            app: context.read<AppCubit>(),
            siteUser: _user.text.trim(),
            sitePass: _pass.text);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _phase = _Phase.done;
          _error = 'Сервер работает, но войти в аккаунт не удалось: ${e.message}. '
              'Зарегистрируйтесь на сайте и войдите во вкладке «Вы».';
        });
      }
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase != _Phase.running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Установка идёт на сервере. Можно выйти — она продолжится, а мастер потом покажет итог')));
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Свой сервер')),
        body: switch (_phase) {
          _Phase.form => _formView(context),
          _ => _progressView(context),
        },
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(color: colors.surfaceContainer, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 8),
        ...children,
      ]),
    );
  }

  Widget _field(TextEditingController c, String label,
          {String? hint,
          bool obscure = false,
          VoidCallback? toggle,
          TextInputType? kb,
          String? Function(String)? check,
          ValueChanged<String>? onChanged}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: c,
          obscureText: obscure,
          keyboardType: kb,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: toggle == null
                ? null
                : IconButton(icon: Icon(obscure ? Icons.visibility : Icons.visibility_off), onPressed: toggle),
          ),
          validator: (v) => check?.call(v ?? ''),
        ),
      );

  Widget _formView(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant, height: 1.35);
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Свой Invidious за 10–15 минут', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
            'Приложение само подключится к VPS, поставит Invidious, сайт CloudTube в виде YouTube '
            '(с паролем и HTTPS), дополнения CloudTube и приглашения для друзей. '
            'В конце сервер сразу появится в приложении.',
            style: muted),
        const SizedBox(height: 16),
        _section(context, '1. Что понадобится', [
          Text('• VPS с Debian 11+ или Ubuntu 20.04+, от 1 ГБ памяти, доступ root по паролю.\n'
              '• Домен или поддомен, например video.example.com.', style: muted),
          const SizedBox(height: 6),
        ]),
        _section(context, '2. Сервер', [
          Row(children: [
            Expanded(
                flex: 3,
                child: _field(_ip, 'IP-адрес VPS',
                    hint: '203.0.113.10',
                    kb: TextInputType.number,
                    check: (v) => RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(v.trim()) ? null : 'Нужен IPv4-адрес',
                    onChanged: (_) => setState(() => _dnsOk = null))),
            const SizedBox(width: 10),
            Expanded(
                child: _field(_port, 'SSH-порт',
                    kb: TextInputType.number, check: (v) => int.tryParse(v.trim()) == null ? 'Порт' : null)),
          ]),
          _field(_rootPass, 'Пароль root',
              obscure: !_showRoot,
              toggle: () => setState(() => _showRoot = !_showRoot),
              check: (v) => v.isEmpty ? 'Введите пароль root' : null),
          Text('Пароль root нужен только для установки и нигде не сохраняется.', style: muted.copyWith(fontSize: 12)),
          const SizedBox(height: 8),
        ]),
        _section(context, '3. Домен', [
          _field(_domain, 'Домен',
              hint: 'video.example.com',
              kb: TextInputType.url,
              check: (v) => RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}$').hasMatch(_domainClean) ? null : 'Например video.example.com',
              onChanged: (_) => setState(() => _dnsOk = null)),
          Text(
              'У регистратора домена (где покупали домен) откройте DNS и добавьте запись:\n'
              '• Тип: A\n'
              '• Имя: video (для поддомена) или @ (для самого домена)\n'
              '• Значение: IP-адрес вашего VPS\n'
              'Запись начинает работать через 5–30 минут.',
              style: muted),
          Row(children: [
            TextButton.icon(onPressed: _checkDns, icon: const Icon(Icons.dns_outlined), label: const Text('Проверить запись')),
            if (_dnsOk != null) Icon(_dnsOk! ? Icons.check_circle : Icons.error_outline, color: _dnsOk! ? Colors.green : colors.error),
          ]),
          if (_dnsInfo != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_dnsInfo!, style: muted)),
          _field(_email, 'Почта для сертификата (необязательно)', kb: TextInputType.emailAddress),
        ]),
        _section(context, '4. Вход на ваш сервер', [
          Text('Этим логином и паролем закрывается сайт, и с ними же создаётся аккаунт Invidious.', style: muted),
          const SizedBox(height: 10),
          _field(_user, 'Логин',
              check: (v) => RegExp(r'^[A-Za-z0-9._@-]{3,64}$').hasMatch(v.trim()) ? null : '3–64 символа: латиница, цифры, . _ @ -'),
          _field(_pass, 'Пароль',
              obscure: !_showPass,
              toggle: () => setState(() => _showPass = !_showPass),
              check: (v) => v.length < 8 ? 'Не короче 8 символов' : null),
        ]),
        const SizedBox(height: 4),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
              onPressed: _start, icon: const Icon(Icons.rocket_launch_outlined), label: const Text('Развернуть сервер')),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _progressView(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final failed = _phase == _Phase.failed, done = _phase == _Phase.done;
    return ListView(padding: const EdgeInsets.all(20), children: [
      const SizedBox(height: 12),
      Center(
        child: Icon(
          failed ? Icons.error_outline : (done ? Icons.check_circle_outline : Icons.cloud_upload_outlined),
          size: 72,
          color: failed ? colors.error : (done ? Colors.green : CtColors.logoRed),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        failed ? 'Установка остановилась' : (done ? 'Сервер готов' : 'Разворачиваю сервер'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 20),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: _progress,
          minHeight: 10,
          color: failed ? colors.error : ctAccent(colors),
          backgroundColor: colors.surfaceContainerHighest,
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: Text(failed ? (_error ?? '') : _step, style: TextStyle(color: colors.onSurfaceVariant))),
        Text('${(_progress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
      if (done) ...[
        const SizedBox(height: 16),
        Text('Адрес: ${_url ?? 'https://$_domainClean'}\nЛогин: ${_user.text.trim()}',
            style: const TextStyle(fontSize: 16, height: 1.5)),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: colors.error))),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Начать смотреть')),
      ],
      if (failed) ...[
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: () => setState(() => _phase = _Phase.form), child: const Text('Изменить данные'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: _start, child: const Text('Повторить'))),
        ]),
        const SizedBox(height: 8),
        Text('Повторный запуск безопасен: готовые шаги пропускаются. Подробный журнал на сервере: /var/log/ct-deploy.debug',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
      ],
      const SizedBox(height: 20),
      TextButton.icon(
        onPressed: () => setState(() => _showLog = !_showLog),
        icon: Icon(_showLog ? Icons.expand_less : Icons.expand_more),
        label: Text(_showLog ? 'Скрыть журнал' : 'Показать журнал'),
      ),
      if (_showLog)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
          child: SelectableText(_lines.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFFB8F5C8))),
        ),
      if (_showLog)
        TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: _lines.join('\n'))),
            child: const Text('Скопировать журнал')),
    ]);
  }
}
