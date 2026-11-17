import 'dart:convert';

import 'net.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'yt_cookies.dart';

final _log = Logger('CtYtComments');

/// Комментарии YouTube без сервера: InnerTube (клиент WEB), разбор нового формата
/// (commentViewModel + commentEntityPayload) и старого (commentRenderer).
/// Отправка — от имени аккаунта, в который вошли кодом.
class CtYtComments {
  static http.Client client = ctHttp;
  static const _webVersion = '2.20251110.01.00';
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  /// Короткие ключи вместо длинных токенов YouTube (их неудобно гонять в адресе запроса).
  static final _tokens = <String, String>{};
  static final _createParams = <String, String>{};

  static String _keep(String token) {
    final k = '${_tokens.length + 1}';
    _tokens[k] = token;
    if (_tokens.length > 5000) _tokens.clear();
    return k;
  }

  static Map<String, dynamic> _ctx({bool auth = false}) => {
        'context': {
          'client': {'clientName': 'WEB', 'clientVersion': _webVersion, 'hl': 'ru', 'gl': 'RU', 'userAgent': _ua},
          if (auth && CtYtCookies.active) 'user': CtYtCookies.user(),
        },
      };

  static Future<Map<String, dynamic>> _next(Map<String, dynamic> body, {bool auth = false}) async {
    final headers = {
      'Content-Type': 'application/json',
      'User-Agent': _ua,
      'X-Youtube-Client-Name': '1',
      'X-Youtube-Client-Version': _webVersion,
      'Origin': 'https://www.youtube.com',
    };
    // от имени пользователя WEB принимает только cookie сайта (вход кодом, как на ТВ, тут даёт 400)
    if (auth && CtYtCookies.active) headers.addAll(CtYtCookies.headers());
    final r = await client.post(Uri.parse('https://www.youtube.com/youtubei/v1/next?prettyPrint=false'),
        headers: headers, body: jsonEncode({..._ctx(auth: auth), ...body}));
    if (r.statusCode != 200) throw 'YouTube next: ${r.statusCode}';
    return (await ctJsonDecodeBytes(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// Первая страница: sort = top | new.
  static Future<Map<String, dynamic>> load(String videoId, String sort) async {
    if (CtYtCookies.active) {
      try {
        final r = await _load(videoId, sort, true);
        if ((r['comments'] as List).isNotEmpty) return r;
      } catch (e) {
        _log.info('comments с аккаунтом: $e — читаю без него');
      }
    }
    return _load(videoId, sort, false);
  }

  static Future<Map<String, dynamic>> _load(String videoId, String sort, bool logged) async {
    final watch = await _next({'videoId': videoId}, auth: logged);
    String? token;
    _walk(watch, (k, v) {
      if (token == null && k == 'itemSectionRenderer' && v is Map && '${v['sectionIdentifier']}'.contains('comment')) {
        token = _findToken(v);
      }
    });
    if (token == null) {
      _walk(watch, (k, v) {
        if (token == null && k == 'engagementPanelSectionListRenderer' && v is Map &&
            '${v['panelIdentifier']}'.contains('comments')) {
          token = _findToken(v['content']);
        }
      });
    }
    if (token == null) return {'videoId': videoId, 'commentCount': 0, 'comments': [], 'continuation': null};
    var page = await _next({'continuation': token}, auth: logged);
    var parsed = _parse(videoId, page);
    if (sort == 'new' && parsed.sortNew != null) {
      page = await _next({'continuation': parsed.sortNew}, auth: logged);
      final p2 = _parse(videoId, page);
      p2.count ??= parsed.count;
      p2.create ??= parsed.create;
      parsed = p2;
    }
    if (parsed.create != null) _createParams[videoId] = parsed.create!;
    return parsed.toJson(videoId);
  }

  /// Продолжение списка или ответы на комментарий (ключ из прошлого ответа).
  static Future<Map<String, dynamic>> more(String videoId, String key) async {
    final token = _tokens[key];
    if (token == null) return {'videoId': videoId, 'comments': [], 'continuation': null};
    Map<String, dynamic> page;
    try {
      page = await _next({'continuation': token}, auth: CtYtCookies.active);
    } catch (_) {
      page = await _next({'continuation': token});
    }
    return _parse(videoId, page).toJson(videoId);
  }

  /// Отправить комментарий от своего имени — как на сайте: cookie входа + SAPISIDHASH,
  /// параметры из шапки комментариев, затем comment/create_comment.
  static Future<Map<String, dynamic>?> post(String videoId, String text) async {
    if (!CtYtCookies.active) throw CtNeedWebLogin();
    var params = _createParams[videoId];
    if (params == null) {
      await _load(videoId, 'top', true);
      params = _createParams[videoId];
    }
    if (params == null) {
      throw 'YouTube не дал отправить комментарий: возможно, вход через сайт устарел '
          '(«Профиль» → «Аккаунт для комментариев» → войти заново) или комментарии к видео ограничены';
    }
    final r = await client.post(Uri.parse('https://www.youtube.com/youtubei/v1/comment/create_comment?prettyPrint=false'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': _ua,
          'X-Youtube-Client-Name': '1',
          'X-Youtube-Client-Version': _webVersion,
          ...CtYtCookies.headers(),
        },
        body: jsonEncode({..._ctx(auth: true), 'commentText': text, 'createCommentParams': params}));
    final body = utf8.decode(r.bodyBytes);
    if (r.statusCode != 200) {
      _log.warning('create_comment ${r.statusCode}: ${body.length > 400 ? body.substring(0, 400) : body}');
      String msg = '${r.statusCode}';
      try {
        msg = '${r.statusCode} ${(jsonDecode(body)['error']?['message'] ?? '')}';
      } catch (_) {}
      if (r.statusCode == 401) throw CtNeedWebLogin();
      throw 'YouTube не принял комментарий: $msg';
    }
    final j = jsonDecode(body);
    if (j is Map && '${j['actionResult']?['status'] ?? 'STATUS_SUCCEEDED'}' != 'STATUS_SUCCEEDED') {
      throw 'YouTube не принял комментарий (${j['actionResult']?['status']})';
    }
    final parsed = _parse(videoId, j as Map<String, dynamic>);
    return parsed.items.isNotEmpty
        ? parsed.items.first
        : {'author': 'Вы', 'content': text, 'publishedText': 'только что', 'likeCount': 0};
  }

  /// Действие с комментарием от своего имени: ответ, правка, удаление.
  static Future<Map<String, dynamic>> _action(String endpoint, Map<String, dynamic> body) async {
    if (!CtYtCookies.active) throw CtNeedWebLogin();
    final r = await client.post(Uri.parse('https://www.youtube.com/youtubei/v1/comment/$endpoint?prettyPrint=false'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': _ua,
          'X-Youtube-Client-Name': '1',
          'X-Youtube-Client-Version': _webVersion,
          ...CtYtCookies.headers(),
        },
        body: jsonEncode({..._ctx(auth: true), ...body}));
    final txt = utf8.decode(r.bodyBytes);
    if (r.statusCode == 401) throw CtNeedWebLogin();
    if (r.statusCode != 200) {
      _log.warning('$endpoint ${r.statusCode}: ${txt.length > 400 ? txt.substring(0, 400) : txt}');
      String msg = '${r.statusCode}';
      try {
        msg = '${r.statusCode} ${(jsonDecode(txt)['error']?['message'] ?? '')}';
      } catch (_) {}
      throw 'YouTube отклонил действие: $msg';
    }
    final j = jsonDecode(txt) as Map<String, dynamic>;
    final st = '${(j['actionResult'] as Map?)?['status'] ?? 'STATUS_SUCCEEDED'}';
    if (st != 'STATUS_SUCCEEDED') throw 'YouTube отклонил действие ($st)';
    return j;
  }

  static Future<Map<String, dynamic>?> reply(String videoId, String params, String text) async {
    final j = await _action('create_comment_reply', {'commentText': text, 'createReplyParams': params});
    final p = _parse(videoId, j);
    return p.items.isNotEmpty ? p.items.first : {'author': 'Вы', 'content': text, 'publishedText': 'только что'};
  }

  static Future<void> edit(String params, String text, {bool isReply = false}) => _action(
      isReply ? 'update_comment_reply' : 'update_comment',
      {'commentText': text, if (isReply) 'updateReplyParams': params else 'updateCommentParams': params});

  static Future<void> delete(String action) => _action('perform_comment_action', {
        'actions': [action]
      });

  /// Параметры действий (ответить / изменить / удалить) из данных комментария.
  static void _attachActions(Map<String, dynamic> c, List<dynamic> sources) {
    String? reply, edit, editReply, del;
    final delRe = RegExp(r'удал|delete', caseSensitive: false);
    String? str(dynamic v) => v is String ? v : null;
    for (final src in sources) {
      reply ??= str(_findKey(src, 'createReplyParams'));
      edit ??= str(_findKey(src, 'updateCommentParams'));
      editReply ??= str(_findKey(src, 'updateReplyParams'));
      del ??= _findMenuAction(src, delRe);
    }
    if (reply != null) c['ctReply'] = reply;
    if (edit != null) c['ctEdit'] = edit;
    if (editReply != null) c['ctEditReply'] = editReply;
    if (del != null) c['ctDelete'] = del;
  }

  /// В меню комментария найти пункт с подписью (например «Удалить») и вернуть его action.
  static String? _findMenuAction(dynamic n, RegExp label) {
    String? found;
    void walk(dynamic x) {
      if (found != null) return;
      if (x is Map) {
        final t = _text(x['text']).isNotEmpty ? _text(x['text']) : _text(x['title']);
        if (t.isNotEmpty && label.hasMatch(t)) {
          final ep = _findKey(x, 'performCommentActionEndpoint');
          if (ep is Map && ep['action'] is String) {
            found = ep['action'] as String;
            return;
          }
        }
        x.values.forEach(walk);
      } else if (x is List) {
        x.forEach(walk);
      }
    }

    walk(n);
    return found;
  }

  // ---------- разбор ----------
  static _Page _parse(String videoId, Map<String, dynamic> j) {
    final p = _Page();
    // сущности нового формата
    final entities = <String, Map>{};
    final payloads = <String, dynamic>{}; // все сущности по ключу (меню, панель действий и т.п.)
    _walk(j['frameworkUpdates'], (k, v) {
      if (k == 'mutations' && v is List) {
        for (final m in v) {
          final pl = (m as Map?)?['payload'];
          if (m != null && m['entityKey'] != null) payloads['${m['entityKey']}'] = pl;
          if (pl is Map && pl['commentEntityPayload'] is Map) entities['${m!['entityKey']}'] = pl['commentEntityPayload'] as Map;
          if (pl is Map && pl['commentEntityPayload'] is Map) {
            final key = (pl['commentEntityPayload'] as Map)['key'];
            if (key != null) entities['$key'] = pl['commentEntityPayload'] as Map;
          }
        }
      }
    });
    final items = <dynamic>[];
    for (final e in (j['onResponseReceivedEndpoints'] as List?) ?? const []) {
      final c = (e as Map?)?['reloadContinuationItemsCommand'] ?? e?['appendContinuationItemsAction'];
      final list = (c as Map?)?['continuationItems'];
      if (list is List) items.addAll(list);
    }
    // ответ на create_comment
    _walk(j['actions'], (k, v) {
      if (k == 'commentViewModel' || k == 'commentRenderer') items.add({k: v});
    });
    for (final it in items) {
      if (it is! Map) continue;
      final header = it['commentsHeaderRenderer'];
      if (header is Map) {
        final cnt = _text(header['countText']).replaceAll(RegExp(r'[^\d]'), '');
        if (cnt.isNotEmpty) p.count = int.tryParse(cnt);
        final menu = _findKey(header['sortMenu'], 'subMenuItems');
        if (menu is List && menu.length > 1) p.sortNew = _findToken(menu[1]);
        final cp = _findKey(header, 'createCommentParams');
        if (cp is String) p.create = cp;
        continue;
      }
      final thread = it['commentThreadRenderer'];
      Map? vm = it['commentViewModel'] is Map ? it['commentViewModel'] as Map : null;
      Map? old = it['commentRenderer'] is Map ? it['commentRenderer'] as Map : null;
      String? repliesToken;
      if (thread is Map) {
        final cvm = thread['commentViewModel'];
        vm = cvm is Map ? (cvm['commentViewModel'] is Map ? cvm['commentViewModel'] as Map : cvm) : null;
        old = (thread['comment'] as Map?)?['commentRenderer'] as Map?;
        final rep = thread['replies'];
        if (rep != null) repliesToken = _findToken(rep);
      }
      if (vm != null && vm['commentViewModel'] is Map) vm = vm['commentViewModel'] as Map;
      final cont = it['continuationItemRenderer'];
      if (cont is Map) {
        p.next = _findToken(cont);
        continue;
      }
      Map<String, dynamic>? c;
      if (vm != null) {
        final e = entities['${vm['commentKey']}'];
        if (e != null) {
          c = _fromEntity(e);
          // связанные сущности: ключи, на которые ссылается commentViewModel
          final related = <dynamic>[vm, e];
          for (final v in vm.values) {
            if (v is String && payloads.containsKey(v)) related.add(payloads[v]);
          }
          _attachActions(c, related);
        }
      } else if (old != null) {
        c = _fromRenderer(old);
        _attachActions(c, [old]);
      }
      if (c == null) continue;
      if (repliesToken != null) {
        c['replies'] = {'replyCount': c.remove('_replies') ?? 1, 'continuation': 'y:${_keep(repliesToken)}'};
      } else {
        c.remove('_replies');
      }
      p.items.add(c);
    }
    return p;
  }

  static Map<String, dynamic> _fromEntity(Map e) {
    final props = (e['properties'] as Map?) ?? const {};
    final author = (e['author'] as Map?) ?? const {};
    final toolbar = (e['toolbar'] as Map?) ?? const {};
    final avatar = '${author['avatarThumbnailUrl'] ?? ''}';
    return {
      'author': '${author['displayName'] ?? ''}',
      'authorId': '${author['channelId'] ?? ''}',
      'authorUrl': '/channel/${author['channelId'] ?? ''}',
      'authorThumbnails': avatar.isEmpty ? [] : [{'url': avatar, 'width': 88, 'height': 88}],
      'authorIsChannelOwner': author['isCreator'] == true,
      'content': '${(props['content'] as Map?)?['content'] ?? ''}',
      'published': 0,
      'publishedText': '${props['publishedTime'] ?? ''}',
      'likeCount': _count('${toolbar['likeCountNotliked'] ?? toolbar['likeCountA11y'] ?? ''}'),
      'commentId': '${props['commentId'] ?? ''}',
      'isEdited': false,
      'creatorHeart': toolbar['heartActiveTooltip'] != null && '${toolbar['heartState'] ?? ''}'.contains('HEARTED') ? {} : null,
      '_replies': _count('${toolbar['replyCount'] ?? ''}'),
    };
  }

  static Map<String, dynamic> _fromRenderer(Map r) {
    final thumbs = (_findKey(r['authorThumbnail'], 'thumbnails') as List?) ?? const [];
    final ch = _findKey(r['authorEndpoint'], 'browseId');
    return {
      'author': _text(r['authorText']),
      'authorId': '${ch ?? ''}',
      'authorUrl': '/channel/${ch ?? ''}',
      'authorThumbnails': thumbs,
      'authorIsChannelOwner': r['authorIsChannelOwner'] == true,
      'content': _text(r['contentText']),
      'published': 0,
      'publishedText': _text(r['publishedTimeText']),
      'likeCount': _count(_text(r['voteCount'])),
      'commentId': '${r['commentId'] ?? ''}',
      'isEdited': false,
      'creatorHeart': null,
      '_replies': (r['replyCount'] as num?)?.toInt() ?? 0,
    };
  }

  static int _count(String s) {
    final m = RegExp(r'([\d.,\s ]+)\s*(тыс|млн|K|M)?', caseSensitive: false).firstMatch(s);
    if (m == null) return 0;
    final x = double.tryParse(m.group(1)!.replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.')) ?? 0;
    final u = (m.group(2) ?? '').toLowerCase();
    return (x * (u == 'тыс' || u == 'k' ? 1e3 : u == 'млн' || u == 'm' ? 1e6 : 1)).round();
  }

  static String _text(dynamic t) {
    if (t is! Map) return '';
    if (t['simpleText'] is String) return t['simpleText'] as String;
    if (t['content'] is String) return t['content'] as String;
    final runs = t['runs'];
    if (runs is List) return runs.map((r) => (r as Map?)?['text'] ?? '').join();
    return '';
  }

  static String? _findToken(dynamic n) {
    final c = _findKey(n, 'continuationCommand');
    if (c is Map && c['token'] is String) return c['token'] as String;
    final d = _findKey(n, 'nextContinuationData');
    if (d is Map && d['continuation'] is String) return d['continuation'] as String;
    return null;
  }

  static dynamic _findKey(dynamic n, String key) {
    if (n is Map) {
      if (n.containsKey(key)) return n[key];
      for (final v in n.values) {
        final r = _findKey(v, key);
        if (r != null) return r;
      }
    } else if (n is List) {
      for (final v in n) {
        final r = _findKey(v, key);
        if (r != null) return r;
      }
    }
    return null;
  }

  static void _walk(dynamic n, void Function(String k, dynamic v) f) {
    if (n is Map) {
      n.forEach((k, v) {
        f('$k', v);
        _walk(v, f);
      });
    } else if (n is List) {
      for (final v in n) {
        _walk(v, f);
      }
    }
  }
}

class _Page {
  int? count;
  String? sortNew;
  String? create;
  String? next;
  final items = <Map<String, dynamic>>[];

  Map<String, dynamic> toJson(String videoId) => {
        'videoId': videoId,
        'commentCount': count ?? items.length,
        'comments': items,
        'continuation': next == null ? null : 'y:${CtYtComments._keep(next!)}',
      };
}

/// Для комментариев нужен вход через сайт YouTube (cookie), а не только код ТВ.
class CtNeedWebLogin implements Exception {
  @override
  String toString() => 'Для комментариев нужен вход через сайт YouTube';
}
