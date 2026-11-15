import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../app/states/app.dart';
import 'connect.dart';

/// Подключение своего сервера одной формой: адрес, пароль сайта (если есть) и аккаунт (необязательно).
/// Возвращает true, если сервер добавлен и выбран.
class CtConnectScreen extends StatefulWidget {
  const CtConnectScreen({super.key});

  @override
  State<CtConnectScreen> createState() => _CtConnectScreenState();
}

class _CtConnectScreenState extends State<CtConnectScreen> {
  final _url = TextEditingController(text: 'https://');
  final _su = TextEditingController(), _sp = TextEditingController();
  final _au = TextEditingController(), _ap = TextEditingController();
  bool _site = false, _account = false, _show1 = false, _show2 = false, _busy = false;
  String? _error, _status;

  @override
  void dispose() {
    for (final c in [_url, _su, _sp, _au, _ap]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _go() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ctConnectServer(
        url: _url.text,
        app: context.read<AppCubit>(),
        siteUser: _site ? _su.text : '',
        sitePass: _site ? _sp.text : '',
        user: _account ? _au.text : '',
        pass: _account ? _ap.text : '',
        onStatus: (m) {
          if (mounted) setState(() => _status = m);
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  Widget _box(BuildContext context, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _text(TextEditingController c, String label,
          {bool secret = false, bool show = false, VoidCallback? toggle, TextInputType? kb, List<String>? hints}) =>
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          controller: c,
          obscureText: secret && !show,
          keyboardType: kb,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: hints,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: secret
                ? IconButton(icon: Icon(show ? Icons.visibility_off : Icons.visibility), onPressed: toggle)
                : null,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    return Scaffold(
      appBar: AppBar(title: const Text('Свой сервер')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: AutofillGroup(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              _box(context, [
                const SizedBox(height: 6),
                _text(_url, 'Адрес сервера Invidious', kb: TextInputType.url, hints: const [AutofillHints.url]),
                const SizedBox(height: 6),
                Text('Например https://invidious.example.com', style: muted),
              ]),
              _box(context, [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Сайт закрыт паролем'),
                  subtitle: Text('Браузер спрашивает логин и пароль при открытии сервера', style: muted),
                  value: _site,
                  onChanged: (v) => setState(() => _site = v),
                ),
                if (_site) ...[
                  _text(_su, 'Логин сайта', hints: const [AutofillHints.username]),
                  _text(_sp, 'Пароль сайта',
                      secret: true, show: _show1, toggle: () => setState(() => _show1 = !_show1)),
                ],
              ]),
              _box(context, [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Войти в аккаунт Invidious'),
                  subtitle: Text('Подписки, история и плейлисты. Можно сделать позже во вкладке «Вы»', style: muted),
                  value: _account,
                  onChanged: (v) => setState(() => _account = v),
                ),
                if (_account) ...[
                  _text(_au, 'Логин аккаунта'),
                  _text(_ap, 'Пароль аккаунта',
                      secret: true, show: _show2, toggle: () => setState(() => _show2 = !_show2)),
                  if (_site)
                    TextButton(
                      onPressed: () => setState(() {
                        _au.text = _su.text;
                        _ap.text = _sp.text;
                      }),
                      child: const Text('Такие же, как пароль сайта'),
                    ),
                ],
              ]),
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: colors.errorContainer, borderRadius: BorderRadius.circular(12)),
                  child: Text(_error!, style: TextStyle(color: colors.onErrorContainer)),
                ),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _go,
                  child: _busy
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 12),
                          Text(_status ?? 'Подключаюсь…'),
                        ])
                      : const Text('Подключиться', style: TextStyle(fontSize: 16)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
