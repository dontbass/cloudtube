import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../globals.dart';
import '../settings/models/db/settings.dart';

final _log = Logger('CtYtCookies');
const _key = 'ct_yt_web_cookie';
const _idKey = 'ct_yt_web_identity';

/// Канал, от имени которого действуем (у одного Google-аккаунта их может быть несколько,
/// плюс в окне входа можно войти в несколько Google-аккаунтов).
class CtYtIdentity {
  final String name, handle, photo;
  final String? pageId;
  final int authUser;
  final bool selected;

  CtYtIdentity(this.name, this.handle, this.photo, this.pageId, this.authUser, this.selected);

  Map<String, dynamic> toJson() => {'name': name, 'handle': handle, 'photo': photo, 'pageId': pageId, 'authUser': authUser};

  static CtYtIdentity? fromJson(dynamic j) => j is Map
      ? CtYtIdentity('${j['name'] ?? ''}', '${j['handle'] ?? ''}', '${j['photo'] ?? ''}', j['pageId'] as String?,
          (j['authUser'] as num?)?.toInt() ?? 0, true)
      : null;
}

/// Вход «как на сайте YouTube» (cookie). Нужен для действий от имени аккаунта на сайте:
/// комментарии, лайки и т.п. Так делают другие клиенты (InnerTune, Metrolist, youtubei.js):
/// вход в обычном окне Google → cookie сайта → заголовок Authorization: SAPISIDHASH.
/// Вход кодом (как на ТВ) YouTube для этого не принимает — только для чтения лент.
class CtYtCookies {
  static String? cookie;
  static CtYtIdentity? identity;

  static void load() {
    try {
      cookie = db.getSettings(_key)?.value;
      if (cookie != null && cookie!.isEmpty) cookie = null;
      final id = db.getSettings(_idKey)?.value;
      if (id != null && id.isNotEmpty) identity = CtYtIdentity.fromJson(jsonDecode(id));
    } catch (_) {}
  }

  static Future<void> setIdentity(CtYtIdentity? id) async {
    identity = id;
    if (id == null) {
      await db.deleteSetting(_idKey);
    } else {
      await db.saveSetting(SettingsValue(_idKey, jsonEncode(id.toJson())));
    }
  }

  /// Контекст InnerTube с учётом выбранного канала.
  static Map<String, dynamic> user() =>
      identity?.pageId != null ? {'onBehalfOfUser': identity!.pageId} : <String, dynamic>{};

  /// Список каналов (и Google-аккаунтов), в которые выполнен вход.
  static Future<List<CtYtIdentity>> accounts() async {
    final out = <CtYtIdentity>[];
    final seen = <String>{};
    // в окне входа может быть несколько Google-аккаунтов: authuser = 0, 1, 2…
    for (var au = 0; au < 5; au++) {
      List<CtYtIdentity> part;
      try {
        part = await _accountsFor(au);
      } catch (e) {
        if (au == 0) rethrow;
        break;
      }
      final fresh = part.where((a) => seen.add('${a.pageId ?? a.name}|${a.authUser}')).toList();
      if (fresh.isEmpty) break;
      out.addAll(fresh);
    }
    return out;
  }

  static Future<List<CtYtIdentity>> _accountsFor(int authUser) async {
    final h = headers(withIdentity: false)..['X-Goog-AuthUser'] = '$authUser';
    final r = await http.post(Uri.parse('https://www.youtube.com/youtubei/v1/account/accounts_list?prettyPrint=false'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
          'X-Youtube-Client-Name': '1',
          'X-Youtube-Client-Version': '2.20251110.01.00',
          ...h,
        },
        body: jsonEncode({
          'context': {
            'client': {'clientName': 'WEB', 'clientVersion': '2.20251110.01.00', 'hl': 'ru', 'gl': 'RU'}
          },
          'requestType': 'ACCOUNTS_LIST_REQUEST_TYPE_CHANNEL_SWITCHER',
          'callCircumstance': 'SWITCHING_USERS_FULL',
        }));
    if (r.statusCode != 200) throw 'Список каналов: HTTP ${r.statusCode}';
    final out = <CtYtIdentity>[];
    String text(dynamic t) =>
        t is Map ? '${t['simpleText'] ?? ((t['runs'] as List?)?.map((e) => e['text']).join() ?? '')}' : '';
    void walk(dynamic n) {
      if (n is Map) {
        final item = n['accountItem'];
        if (item is Map) {
          String? pageId;
          var au = authUser;
          final tokens = ((item['serviceEndpoint'] as Map?)?['selectActiveIdentityEndpoint'] as Map?)?['supportedTokens'];
          if (tokens is List) {
            for (final t in tokens) {
              if (t is! Map) continue;
              final pid = (t['pageIdToken'] as Map?)?['pageId'];
              if (pid is String) pageId = pid;
              // ссылка переключения канала: …&authuser=N&pageid=… (есть и у каналов-брендов этой же почты)
              final url = (t['accountSigninToken'] as Map?)?['signinUrl'];
              if (url is String) {
                final m = RegExp(r'authuser=(\d+)').firstMatch(url);
                if (m != null) au = int.parse(m.group(1)!);
                final pm = RegExp(r'pageid=(\d+)').firstMatch(url);
                if (pm != null) pageId ??= pm.group(1);
              }
            }
          }
          final photo = ((item['accountPhoto'] as Map?)?['thumbnails'] as List?)?.lastOrNull;
          out.add(CtYtIdentity(text(item['accountName']), text(item['channelHandle']),
              '${photo is Map ? photo['url'] ?? '' : ''}', pageId, au, item['isSelected'] == true));
          return;
        }
        n.values.forEach(walk);
      } else if (n is List) {
        n.forEach(walk);
      }
    }

    walk(jsonDecode(utf8.decode(r.bodyBytes)));
    return out;
  }

  /// Единое окно «Аккаунт для комментариев»: текущий канал, все доступные каналы
  /// (один щелчок — переключиться), добавить другой аккаунт Google, выйти.
  /// Возвращает true, если что-то изменилось.
  static Future<bool> manage(BuildContext context) async {
    if (!active) {
      final ok = await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const CtYtWebLoginScreen()));
      return ok == true;
    }
    final changed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => const _CtAccountSheet(),
    );
    return changed == true;
  }

  static Future<void> signOut() async {
    await save(null);
    await setIdentity(null);
    try {
      await CookieManager.instance().deleteAllCookies(); // чтобы в следующий раз Google спросил аккаунт заново
    } catch (_) {}
  }

  /// Выбрать канал: если их несколько — спросить пользователя.
  static Future<void> chooseIdentity(BuildContext context, {bool force = false}) async {
    List<CtYtIdentity> list;
    try {
      list = await accounts();
    } catch (e) {
      _log.info('accounts_list: $e');
      return;
    }
    if (list.isEmpty) return;
    if (list.length == 1 && !force) {
      await setIdentity(list.first);
      return;
    }
    if (!context.mounted) return;
    final picked = await showDialog<CtYtIdentity>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('От имени какого канала?'),
        children: [
          for (final a in list)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(a),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundImage: a.photo.isNotEmpty ? NetworkImage(a.photo) : null,
                  child: a.photo.isEmpty ? Text(a.name.isNotEmpty ? a.name[0] : '?') : null,
                ),
                title: Text(a.name),
                subtitle: Text(a.handle),
                trailing: (identity?.pageId == a.pageId && identity?.authUser == a.authUser)
                    ? const Icon(Icons.check)
                    : null,
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text('Другой Google-аккаунт: «Вы» → «Комментарии от своего имени» → «Добавить аккаунт Google».',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
    if (picked != null) await setIdentity(picked);
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
  static Map<String, String> headers({bool withIdentity = true}) {
    final c = cookie!;
    final sid = _sapisid(c)!;
    const origin = 'https://www.youtube.com';
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final hash = sha1.convert(utf8.encode('$ts $sid $origin')).toString();
    return {
      'Cookie': c,
      'Authorization': 'SAPISIDHASH ${ts}_$hash SAPISID1PHASH ${ts}_$hash SAPISID3PHASH ${ts}_$hash',
      'X-Origin': origin,
      'X-Goog-AuthUser': '${withIdentity ? (identity?.authUser ?? 0) : 0}',
      if (withIdentity && identity?.pageId != null) 'X-Goog-PageId': identity!.pageId!,
      'Origin': origin,
      'Referer': '$origin/',
    };
  }
}

/// Окно входа в Google (страница Google, пароль вводится там). После входа забираем cookie YouTube.
class CtYtWebLoginScreen extends StatefulWidget {
  /// true — открыть выбор/добавление Google-аккаунта (для второго аккаунта)
  final bool addAccount;

  /// true — открыть переключатель каналов на сайте YouTube (выбор как на сайте/ТВ)
  final bool switcher;

  const CtYtWebLoginScreen({super.key, this.addAccount = false, this.switcher = false});

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
    // в переключателе ждём, пока пользователь выберет канал и сайт уйдёт со страницы выбора
    if (widget.switcher && (url.path.contains('channel_switcher') || url.path.contains('signin'))) return;
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
    if (widget.switcher) {
      // канал выбран на самом сайте — дальше действуем от того канала, который сайт сделал активным
      await CtYtCookies.setIdentity(null);
      try {
        final cur = (await CtYtCookies.accounts()).where((a) => a.selected).firstOrNull;
        if (cur != null) await CtYtCookies.setIdentity(cur);
      } catch (_) {}
    } else {
      await CtYtCookies.chooseIdentity(context, force: widget.addAccount);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Готово: теперь можно комментировать от своего имени')));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.switcher ? 'Выберите канал' : 'Вход через сайт YouTube'),
        bottom: _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2), child: LinearProgressIndicator(value: _progress, minHeight: 2))
            : null,
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(
            url: WebUri(
                widget.switcher
                    ? 'https://www.youtube.com/channel_switcher?next=%2F'
                    : widget.addAccount
                    ? 'https://accounts.google.com/AddSession?service=youtube&hl=ru&continue=${Uri.encodeComponent('https://m.youtube.com/')}'
                    : 'https://accounts.google.com/ServiceLogin?service=youtube&hl=ru&continue=${Uri.encodeComponent('https://m.youtube.com/')}')),
        initialSettings: InAppWebViewSettings(
          // переключатель каналов есть только в полной версии сайта
          userAgent: widget.switcher
              ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
              : _ua,
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


class _CtAccountSheet extends StatefulWidget {
  const _CtAccountSheet();

  @override
  State<_CtAccountSheet> createState() => _CtAccountSheetState();
}

class _CtAccountSheetState extends State<_CtAccountSheet> {
  List<CtYtIdentity>? list;
  String? err;

  @override
  void initState() {
    super.initState();
    CtYtCookies.accounts().then((l) {
      if (mounted) setState(() => list = l);
    }).catchError((e) {
      if (mounted) setState(() => err = '$e');
    });
  }

  bool _isCurrent(CtYtIdentity a) {
    final cur = CtYtCookies.identity;
    if (cur == null) return a.selected;
    return cur.pageId == a.pageId && cur.authUser == a.authUser;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: ListView(shrinkWrap: true, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Аккаунт для комментариев', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Нажмите на канал, чтобы писать от его имени.',
                style: TextStyle(color: colors.onSurfaceVariant)),
          ),
          if (list == null && err == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (err != null)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text('Не удалось получить список каналов: $err', style: TextStyle(color: colors.error))),
          for (final a in list ?? const <CtYtIdentity>[])
            ListTile(
              leading: CircleAvatar(
                backgroundImage: a.photo.isNotEmpty ? NetworkImage(a.photo) : null,
                child: a.photo.isEmpty ? Text(a.name.isNotEmpty ? a.name[0] : '?') : null,
              ),
              title: Text(a.name),
              subtitle: Text([a.handle, if (a.authUser > 0) 'аккаунт Google №${a.authUser + 1}']
                  .where((e) => e.isNotEmpty)
                  .join(' · ')),
              trailing: _isCurrent(a) ? Icon(Icons.check_circle, color: colors.primary) : null,
              onTap: () async {
                await CtYtCookies.setIdentity(a);
                if (context.mounted) Navigator.of(context).pop(true);
              },
            ),
          if (list != null && list!.length <= 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                  'Найден один канал. Если у этой почты есть ещё каналы YouTube, они появятся здесь; '
                  'другую почту добавьте кнопкой ниже.',
                  style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.switch_account),
            title: const Text('Выбрать канал на сайте YouTube'),
            subtitle: const Text('Если нужного канала нет в списке — выбор как на сайте'),
            onTap: () async {
              final ok = await Navigator.of(context)
                  .push<bool>(MaterialPageRoute(builder: (_) => const CtYtWebLoginScreen(switcher: true)));
              if (context.mounted) Navigator.of(context).pop(ok == true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_add_alt),
            title: const Text('Добавить другой аккаунт Google'),
            onTap: () async {
              final ok = await Navigator.of(context)
                  .push<bool>(MaterialPageRoute(builder: (_) => const CtYtWebLoginScreen(addAccount: true)));
              if (context.mounted) Navigator.of(context).pop(ok == true);
            },
          ),
          ListTile(
            leading: Icon(Icons.logout, color: colors.error),
            title: Text('Выйти (не писать комментарии)', style: TextStyle(color: colors.error)),
            subtitle: const Text('Вход через сайт будет удалён с устройства'),
            onTap: () async {
              await CtYtCookies.signOut();
              if (context.mounted) Navigator.of(context).pop(true);
            },
          ),
        ]),
      ),
    );
  }
}
