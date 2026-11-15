import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/states/app.dart';
import '../globals.dart';
import '../settings/models/db/server.dart';
import 'connect.dart';
import 'theme.dart';

final _log = Logger('CtTvLink');

/// Вход на телевизоре с телефона.
/// ТВ поднимает маленький веб-сервер в домашней сети и показывает QR со ссылкой.
/// Телефон открывает страницу, человек вводит адрес сервера, пароль сайта и логин аккаунта —
/// данные уходят прямо на ТВ, а тот сам подключается и входит. Сервер работает, только пока открыт экран.
class CtTvLinkScreen extends StatefulWidget {
  /// вызывается после успешного подключения (например, чтобы перейти на главную)
  final void Function(BuildContext context)? onDone;

  const CtTvLinkScreen({super.key, this.onDone});

  @override
  State<CtTvLinkScreen> createState() => _CtTvLinkScreenState();
}

class _CtTvLinkScreenState extends State<CtTvLinkScreen> {
  HttpServer? _http;
  String? _link;
  String _status = 'Запускаю…';
  bool _ok = false;
  bool _busy = false;
  late final String _token = _randomToken();

  static String _randomToken() {
    const abc = 'abcdefghjkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(10, (_) => abc[r.nextInt(abc.length)]).join();
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _http?.close(force: true);
    super.dispose();
  }

  Future<String?> _lanIp() async {
    final list = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    String? fallback;
    for (final i in list) {
      for (final a in i.addresses) {
        final ip = a.address;
        if (ip.startsWith('192.168.') || ip.startsWith('10.') || RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) {
          return ip;
        }
        fallback ??= ip;
      }
    }
    return fallback;
  }

  Future<void> _start() async {
    try {
      final ip = await _lanIp();
      if (ip == null) {
        setState(() => _status = 'Телевизор не подключён к сети — проверьте Wi-Fi или кабель');
        return;
      }
      HttpServer srv;
      try {
        srv = await HttpServer.bind(InternetAddress.anyIPv4, 8686);
      } catch (_) {
        srv = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      }
      _http = srv;
      srv.listen(_handle, onError: (e) => _log.warning('http: $e'));
      setState(() {
        _link = 'http://$ip:${srv.port}/$_token';
        _status = 'Ждём данные с телефона…';
      });
    } catch (e) {
      setState(() => _status = 'Не удалось запустить: $e');
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.uri.path != '/$_token') {
        res.statusCode = 404;
        res.write('not found');
      } else if (req.method == 'GET') {
        final cur = await db.getCurrentlySelectedServer().then<Server?>((s) => s).catchError((_) => null);
        res.headers.contentType = ContentType.html;
        res.write(_page(cur?.url ?? ''));
      } else if (req.method == 'POST') {
        final body = await utf8.decoder.bind(req).join();
        final f = Uri.splitQueryString(body);
        String msg;
        bool ok;
        if (_busy) {
          ok = false;
          msg = 'Телевизор уже подключается, подождите';
        } else {
          (ok, msg) = await _apply(f);
        }
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'ok': ok, 'msg': msg}));
      } else {
        res.statusCode = 405;
      }
    } catch (e) {
      res.statusCode = 500;
      res.write('$e');
    } finally {
      await res.close();
    }
  }

  Future<(bool, String)> _apply(Map<String, String> f) async {
    _busy = true;
    setState(() => _status = 'Получены данные, подключаюсь…');
    try {
      final s = await ctConnectServer(
        url: f['server'] ?? '',
        app: context.read<AppCubit>(),
        siteUser: f['site_user'] ?? '',
        sitePass: f['site_pass'] ?? '',
        user: f['user'] ?? '',
        pass: f['pass'] ?? '',
        onStatus: (m) {
          if (mounted) setState(() => _status = m);
        },
      );
      final au = (f['user'] ?? '').trim();
      final done = au.isNotEmpty
          ? 'Готово: телевизор подключён к ${s.url}, вход выполнен ($au)'
          : 'Готово: телевизор подключён к ${s.url}';
      if (mounted) {
        setState(() {
          _ok = true;
          _status = done;
        });
      }
      if (widget.onDone != null && mounted) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) widget.onDone!(context);
        });
      }
      return (true, done);
    } on CtConnectError catch (e) {
      return _fail(e.message);
    } catch (e) {
      return _fail('Ошибка: $e');
    } finally {
      _busy = false;
    }
  }

  (bool, String) _fail(String m) {
    if (mounted) setState(() => _status = m);
    return (false, m);
  }

  String _page(String server) {
    final esc = const HtmlEscape();
    return '''<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>CloudTube — вход на телевизоре</title>
<style>
:root{color-scheme:light dark}
body{font-family:system-ui,-apple-system,Roboto,sans-serif;margin:0;background:#0f0f0f;color:#f1f1f1}
main{max-width:440px;margin:0 auto;padding:24px 18px 40px}
h1{font-size:22px;margin:4px 0 2px}h1 b{color:#E85D4A}
p.sub{color:#aaa;margin:0 0 18px;font-size:14px}
fieldset{border:1px solid #303030;border-radius:14px;padding:12px 14px 4px;margin:0 0 14px}
legend{padding:0 6px;color:#aaa;font-size:13px}
label{display:block;font-size:13px;color:#aaa;margin:8px 0 4px}
input{width:100%;box-sizing:border-box;font-size:16px;padding:12px;border-radius:10px;border:1px solid #3f3f3f;background:#181818;color:#f1f1f1}
input:focus{outline:2px solid #3EA6FF;border-color:transparent}
button{width:100%;font-size:17px;font-weight:600;padding:14px;border:0;border-radius:24px;background:#f1f1f1;color:#0f0f0f;margin-top:6px}
button:disabled{opacity:.5}
#msg{margin-top:16px;padding:12px;border-radius:10px;display:none;font-size:15px}
.ok{background:#12351f;color:#9ff0b8}.err{background:#3d1214;color:#ffb4b4}
small{display:block;color:#717171;margin-top:18px;font-size:12px;line-height:1.4}
</style></head><body><main>
<h1>CLOUD<b>TUBE</b></h1>
<p class="sub">Вход на телевизоре. Данные уйдут прямо на ТВ в вашей домашней сети.</p>
<form id="f">
<fieldset><legend>Сервер</legend>
<label for="server">Адрес сервера Invidious</label>
<input id="server" name="server" type="url" inputmode="url" autocomplete="url" required placeholder="https://invidious.example.com" value="${esc.convert(server)}">
</fieldset>
<fieldset><legend>Пароль сайта — если сайт его спрашивает</legend>
<label for="site_user">Логин сайта</label><input id="site_user" name="site_user" autocomplete="off" autocapitalize="none">
<label for="site_pass">Пароль сайта</label><input id="site_pass" name="site_pass" type="password" autocomplete="off">
</fieldset>
<fieldset><legend>Аккаунт Invidious — подписки, история, плейлисты</legend>
<label for="user">Логин</label><input id="user" name="user" autocomplete="username" autocapitalize="none">
<label for="pass">Пароль</label><input id="pass" name="pass" type="password" autocomplete="current-password">
</fieldset>
<button id="b">Отправить на телевизор</button>
</form>
<div id="msg"></div>
<small>Связь телефона и телевизора идёт по вашей локальной сети без шифрования. Ссылка одноразовая и работает, пока на ТВ открыт экран входа.</small>
</main><script>
const f=document.getElementById('f'),b=document.getElementById('b'),m=document.getElementById('msg');
f.addEventListener('submit',async e=>{e.preventDefault();b.disabled=true;b.textContent='Подключаю…';m.style.display='none';
try{const r=await fetch(location.pathname,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams(new FormData(f))});
const j=await r.json();m.className=j.ok?'ok':'err';m.textContent=j.msg;}catch(err){m.className='err';m.textContent='Нет связи с телевизором: '+err;}
m.style.display='block';b.disabled=false;b.textContent='Отправить на телевизор';});
</script></body></html>''';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 27),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: _link == null
                    ? const SizedBox(width: 260, height: 260, child: Center(child: CircularProgressIndicator()))
                    : QrImageView(data: _link!, size: 260, backgroundColor: Colors.white),
              ),
              const SizedBox(width: 48),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Вход с телефона', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    Text('1. Подключите телефон к той же сети Wi-Fi, что и телевизор.', style: text.titleMedium),
                    Text('2. Наведите камеру телефона на QR-код.', style: text.titleMedium),
                    Text('3. Введите адрес сервера, пароль сайта и логин — и нажмите «Отправить».',
                        style: text.titleMedium),
                    const SizedBox(height: 16),
                    if (_link != null)
                      Text('Или откройте на телефоне: $_link',
                          style: text.titleSmall?.copyWith(color: colors.onSurfaceVariant)),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: _ok ? Colors.green.withValues(alpha: 0.15) : colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_ok ? Icons.check_circle : Icons.wifi_tethering,
                            color: _ok ? Colors.green : ctAccent(colors)),
                        const SizedBox(width: 12),
                        Flexible(child: Text(_status, style: text.titleMedium)),
                      ]),
                    ),
                    const SizedBox(height: 24),
                    _TvBackButton(label: _ok ? 'Готово' : 'Назад'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvBackButton extends StatelessWidget {
  final String label;

  const _TvBackButton({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FilledButton(
      autofocus: true,
      style: ButtonStyle(
        side: WidgetStateProperty.resolveWith((s) => BorderSide(
            color: s.contains(WidgetState.focused) ? ctAccent(colors) : Colors.transparent, width: 3)),
      ),
      onPressed: () => Navigator.of(context).maybePop(),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Text(label)),
    );
  }
}
