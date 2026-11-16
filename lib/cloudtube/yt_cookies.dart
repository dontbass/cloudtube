import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:logging/logging.dart';

import '../globals.dart';
import '../settings/models/db/settings.dart';

final _log = Logger('CtYtCookies');
const _key = 'ct_yt_web_cookie';

/// Вход «как на сайте YouTube» (cookie). Нужен для действий от имени аккаунта на сайте:
/// комментарии, лайки и т.п. Так делают другие клиенты (InnerTune, Metrolist, youtubei.js):
/// вход в обычном окне Google → cookie сайта → заголовок Authorization: SAPISIDHASH.
/// Вход кодом (как на ТВ) YouTube для этого не принимает — только для чтения лент.
class CtYtCookies {
  static String? cookie;

  static void load() {
    try {
      cookie = db.getSettings(_key)?.value;
      if (cookie != null && cookie!.isEmpty) cookie = null;
    } catch (_) {}
  }

  static Future<void> save(String? c) async {
    cookie = c;
    if (c == null) {
      await db.deleteSetting(_key);
    } else {
      await db.saveSetting(SettingsValue(_key, c));
    }
  }

  static bool get active => cookie != null && _sapisid(cookie!) != null;

  static String? _sapisid(String c) {
    for (final part in c.split(';')) {
      final kv = part.trim();
      for (final name in ['SAPISID=', '__Secure-3PAPISID=']) {
        if (kv.startsWith(name)) return kv.substring(name.length);
      }
    }
    return null;
  }

  /// Заголовки для запросов InnerTube WEB от имени вошедшего пользователя.
  static Map<String, String> headers() {
    final c = cookie!;
    final sid = _sapisid(c)!;
    const origin = 'https://www.youtube.com';
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final hash = sha1.convert(utf8.encode('$ts $sid $origin')).toString();
    return {
      'Cookie': c,
      'Authorization': 'SAPISIDHASH ${ts}_$hash SAPISID1PHASH ${ts}_$hash SAPISID3PHASH ${ts}_$hash',
      'X-Origin': origin,
      'X-Goog-AuthUser': '0',
      'Origin': origin,
      'Referer': '$origin/',
    };
  }
}

/// Окно входа в Google (страница Google, пароль вводится там). После входа забираем cookie YouTube.
class CtYtWebLoginScreen extends StatefulWidget {
  const CtYtWebLoginScreen({super.key});

  @override
  State<CtYtWebLoginScreen> createState() => _CtYtWebLoginScreenState();
}

class _CtYtWebLoginScreenState extends State<CtYtWebLoginScreen> {
  bool _done = false;
  double _progress = 0;

  // обычный мобильный Chrome: со «встроенным» браузером (wv) Google вход не пускает
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  Future<void> _check(WebUri? url) async {
    if (_done || url == null) return;
    if (!url.host.endsWith('youtube.com')) return;
    final all = <String, String>{};
    for (final u in ['https://www.youtube.com', 'https://m.youtube.com', 'https://youtube.com']) {
      try {
        for (final c in await CookieManager.instance().getCookies(url: WebUri(u))) {
          all[c.name] = '${c.value}';
        }
      } catch (e) {
        _log.info('cookies $u: $e');
      }
    }
    if (!all.containsKey('SAPISID') && !all.containsKey('__Secure-3PAPISID')) return;
    _done = true;
    final cookie = all.entries.map((e) => '${e.key}=${e.value}').join('; ');
    await CtYtCookies.save(cookie);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Готово: теперь можно комментировать от своего имени')));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Вход через сайт YouTube'),
        bottom: _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2), child: LinearProgressIndicator(value: _progress, minHeight: 2))
            : null,
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(
            url: WebUri(
                'https://accounts.google.com/ServiceLogin?service=youtube&hl=ru&continue=${Uri.encodeComponent('https://m.youtube.com/')}')),
        initialSettings: InAppWebViewSettings(
          userAgent: _ua,
          javaScriptEnabled: true,
          thirdPartyCookiesEnabled: true,
          clearCache: false,
        ),
        onProgressChanged: (_, p) => setState(() => _progress = p / 100),
        onLoadStop: (_, url) => _check(url),
        onUpdateVisitedHistory: (_, url, __) => _check(url),
      ),
    );
  }
}
