import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/states/app.dart';
import '../globals.dart';
import '../main.dart' show isTv;
import 'yt_account.dart';

/// Вход в аккаунт YouTube кодом (как на телевизорах и в SmartTube): пароль вводится только на сайте Google.
class CtYtLoginScreen extends StatefulWidget {
  const CtYtLoginScreen({super.key});

  @override
  State<CtYtLoginScreen> createState() => _CtYtLoginScreenState();
}

class _CtYtLoginScreenState extends State<CtYtLoginScreen> {
  CtDeviceCode? _code;
  String? _error;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _code = null;
      _error = null;
    });
    try {
      final code = await CtYtAccount.startLogin();
      if (_closed) return;
      setState(() => _code = code);
      final refresh = await CtYtAccount.waitForLogin(code, cancelled: () => _closed);
      if (_closed || !mounted) return;
      final app = context.read<AppCubit>();
      var s = await db.getCurrentlySelectedServer();
      s = s.copyWith(authToken: refresh, sidCookie: null);
      await db.upsertServer(s);
      app.setServer(s);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Вы вошли в аккаунт YouTube: подписки, рекомендации и история')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!_closed && mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final code = _code;
    final url = code?.verificationUrl ?? 'https://www.google.com/device';
    // ссылка сразу с кодом: страница Google подставит его сама (если нет — код уже в буфере обмена)
    final link = code == null ? url : '$url?user_code=${Uri.encodeQueryComponent(code.userCode)}';
    Future<void> open() async {
      if (code == null) return;
      await Clipboard.setData(ClipboardData(text: code.userCode));
      await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    }

    Widget body;
    if (_error != null) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 48, color: colors.error),
        const SizedBox(height: 12),
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(autofocus: true, onPressed: _start, child: const Text('Попробовать снова')),
      ]);
    } else if (code == null) {
      body = const Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(),
        SizedBox(height: 12),
        Text('Получаем код у YouTube…'),
      ]);
    } else {
      final steps = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (!isTv) ...[
          FilledButton.icon(
            autofocus: true,
            onPressed: open,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Открыть страницу входа Google'),
          ),
          const SizedBox(height: 6),
          Text('Код скопируется автоматически — если страница его не подставит, вставьте его.',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 16),
          Text('Или вручную: откройте', style: text.titleMedium),
        ] else
          Text('1. Наведите камеру телефона на QR-код или откройте', style: text.titleMedium),
        const SizedBox(height: 4),
        InkWell(
          onTap: isTv ? null : open,
          child: Text(url.replaceFirst('https://', ''),
              style: text.titleLarge?.copyWith(
                  color: colors.primary, fontWeight: FontWeight.w700, decoration: isTv ? null : TextDecoration.underline)),
        ),
        const SizedBox(height: 16),
        Text(isTv ? '2. Войдите в Google и введите код' : 'и введите код', style: text.titleMedium),
        const SizedBox(height: 8),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(color: colors.secondaryContainer, borderRadius: BorderRadius.circular(12)),
            child: SelectableText(code.userCode,
                style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 4)),
          ),
          if (!isTv)
            IconButton(
                tooltip: 'Скопировать код',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code.userCode));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Код скопирован')));
                },
                icon: const Icon(Icons.copy)),
        ]),
        const SizedBox(height: 16),
        Text(isTv ? '3. Разрешите доступ — приложение само продолжит.' : 'Затем разрешите доступ и вернитесь сюда — приложение продолжит само.', style: text.titleMedium),
        const SizedBox(height: 12),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text('Ждём подтверждения…', style: TextStyle(color: colors.onSurfaceVariant)),
        ]),
        const SizedBox(height: 12),
        Text('Пароль вводится только на сайте Google; приложение получает доступ к ленте, подпискам и истории.',
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
      ]);
      final qr = Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: QrImageView(data: link, size: 180, backgroundColor: Colors.white),
      );
      body = LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > 640;
        return wide
            ? Row(mainAxisSize: MainAxisSize.min, children: [Flexible(child: steps), const SizedBox(width: 32), qr])
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                steps,
                const SizedBox(height: 16),
                Center(child: qr),
              ]);
      });
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Вход в аккаунт YouTube')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: body),
          ),
        ),
      ),
    );
  }
}
