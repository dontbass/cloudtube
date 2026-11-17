import 'dart:async';
import 'net.dart';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Refresh-токен аккаунта YouTube для режима «без сервера» (null — не вошли).
/// Хранится как authToken «сервера» youtube.direct, сюда копируется при выборе сервера.
String? ctYtRefreshToken;

/// Краткие сведения о роликах из лент аккаунта (для истории — без лишних запросов).
final ctDirectBriefs = <String, Map<String, dynamic>>{};

/// Вход в аккаунт YouTube так же, как это делают телевизоры и SmartTube:
/// «код устройства» (OAuth 2.0 device flow) — пользователь вводит короткий код на youtube.com/activate
/// с телефона или компьютера. Пароль приложение не видит.
class CtYtAccount {
  static const tvUserAgent =
      'Mozilla/5.0 (Linux armeabi-v7a; Android 7.1.2; Fire OS 6.0) Cobalt/22.lts.3.306369-gold (unlike Gecko) '
      'v8/8.8.278.8-jit gles Starboard/13, Amazon_ATV_mediatek8695_2019/NS6294 (Amazon, AFTMM, Wireless) '
      'com.amazon.firetv.youtube/22.3.r2.v66.0';
  static const tvClientVersion = '7.20260901.15.00';
  static const _scope = 'http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content';
  // + полный доступ YouTube Data API (нужен для отправки комментариев); если Google не примет — без него
  static const _scopeFull = '$_scope https://www.googleapis.com/auth/youtube';

  static http.Client client = ctHttp;

  static (String, String)? _creds;
  static String? _access;
  static DateTime _accessUntil = DateTime(2000);
  static String? _accessFor;

  /// client_id/client_secret приложения YouTube для ТВ — берутся из его же скрипта (как в SmartTube).
  static Future<(String, String)> clientCreds() async {
    if (_creds != null) return _creds!;
    final page = await client.get(Uri.parse('https://www.youtube.com/tv'), headers: {'User-Agent': tvUserAgent});
    final m = RegExp(r'id="base-js" src="(.*?)"').firstMatch(page.body) ??
        RegExp(r"\.src = '(.*?m=base)'").firstMatch(page.body) ??
        RegExp(r"\.src = '(.*?)'; .\.id = 'base-js'").firstMatch(page.body);
    if (m == null) throw 'Не найден скрипт YouTube TV';
    var src = m.group(1)!.replaceAll(r'\/', '/');
    if (src.startsWith('/')) src = 'https://www.youtube.com$src';
    final js = await client.get(Uri.parse(src), headers: {'User-Agent': tvUserAgent});
    final c = RegExp(r'clientId:"([-\w]+\.apps\.googleusercontent\.com)",\n?[$\w]+:"(\w+)"').firstMatch(js.body);
    if (c == null) throw 'Не найден client_id YouTube TV';
    return _creds = (c.group(1)!, c.group(2)!);
  }

  static String _deviceId() {
    final r = Random.secure();
    String hex(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
  }

  static Future<Map<String, dynamic>> _post(String url, Map<String, dynamic> body, {Map<String, String>? headers}) async {
    final r = await client.post(Uri.parse(url),
        headers: {'Content-Type': 'application/json', 'User-Agent': tvUserAgent, ...?headers}, body: jsonEncode(body));
    final j = r.body.isEmpty ? <String, dynamic>{} : await ctJsonDecodeBytes(r.bodyBytes);
    if (j is! Map<String, dynamic>) throw 'Неожиданный ответ YouTube (${r.statusCode})';
    j['_status'] = r.statusCode;
    return j;
  }

  /// Шаг 1: получить код для ввода на youtube.com/activate.
  static Future<CtDeviceCode> startLogin() async {
    final (id, _) = await clientCreds();
    var j = await _post('https://www.youtube.com/o/oauth2/device/code',
        {'client_id': id, 'device_id': _deviceId(), 'model_name': 'ytlr::', 'scope': _scopeFull});
    if (j['device_code'] == null) {
      j = await _post('https://www.youtube.com/o/oauth2/device/code',
          {'client_id': id, 'device_id': _deviceId(), 'model_name': 'ytlr::', 'scope': _scope});
    }
    if (j['device_code'] == null) throw 'YouTube не выдал код: ${j['error'] ?? j['_status']}';
    return CtDeviceCode(j['device_code'] as String, j['user_code'] as String, (j['verification_url'] as String?) ?? 'https://www.youtube.com/activate',
        (j['interval'] as num?)?.toInt() ?? 5, (j['expires_in'] as num?)?.toInt() ?? 1800);
  }

  /// Шаг 2: ждать, пока пользователь подтвердит. Возвращает refresh-токен.
  static Future<String> waitForLogin(CtDeviceCode code, {bool Function()? cancelled}) async {
    final (id, secret) = await clientCreds();
    final until = DateTime.now().add(Duration(seconds: code.expiresIn));
    var interval = code.interval;
    while (DateTime.now().isBefore(until)) {
      await Future.delayed(Duration(seconds: interval));
      if (cancelled?.call() ?? false) throw 'Отменено';
      final j = await _post('https://www.youtube.com/o/oauth2/token', {
        'code': code.deviceCode,
        'client_id': id,
        'client_secret': secret,
        'grant_type': 'http://oauth.net/grant_type/device/1.0',
      });
      if (j['refresh_token'] != null) {
        _access = j['access_token'] as String?;
        _accessFor = j['refresh_token'] as String?;
        _accessUntil = DateTime.now().add(Duration(seconds: ((j['expires_in'] as num?)?.toInt() ?? 3600) - 120));
        return j['refresh_token'] as String;
      }
      final err = j['error'];
      if (err == 'slow_down') interval += 2;
      if (err == 'authorization_pending' || err == 'slow_down') continue;
      throw 'Вход отклонён: ${err ?? j['_status']}';
    }
    throw 'Время на ввод кода истекло';
  }

  /// Access-токен (живёт ~1 час) по refresh-токену.
  static Future<String> accessToken(String refresh) async {
    if (_access != null && _accessFor == refresh && DateTime.now().isBefore(_accessUntil)) return _access!;
    final (id, secret) = await clientCreds();
    final j = await _post('https://www.youtube.com/o/oauth2/token',
        {'refresh_token': refresh, 'client_id': id, 'client_secret': secret, 'grant_type': 'refresh_token'});
    if (j['access_token'] == null) throw CtYtAuthError('Вход в YouTube устарел — войдите заново (${j['error'] ?? j['_status']})');
    _access = j['access_token'] as String?;
    _accessFor = refresh;
    _accessUntil = DateTime.now().add(Duration(seconds: ((j['expires_in'] as num?)?.toInt() ?? 3600) - 120));
    return _access!;
  }

  static Map<String, dynamic> _ctx() => {
        'context': {
          'client': {
            'clientName': 'TVHTML5',
            'clientVersion': tvClientVersion,
            'clientScreen': 'WATCH',
            'userAgent': tvUserAgent,
            'tvAppInfo': {'appQuality': 'TV_APP_QUALITY_FULL_ANIMATION', 'zylonLeftNav': true},
            'webpSupport': false,
            'animatedWebpSupport': true,
            'acceptLanguage': 'ru',
            'acceptRegion': 'RU',
            'hl': 'ru',
            'gl': 'RU',
            'utcOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
          },
          'user': {'enableSafetyMode': false, 'lockedSafetyMode': false},
        },
        'racyCheckOk': true,
        'contentCheckOk': true,
      };

  /// Запрос к InnerTube от имени аккаунта (клиент YouTube для ТВ).
  static Future<Map<String, dynamic>> innertube(String refresh, String endpoint, Map<String, dynamic> body) async {
    final token = await accessToken(refresh);
    final j = await _post('https://www.youtube.com/youtubei/v1/$endpoint?prettyPrint=false', {..._ctx(), ...body},
        headers: {
          'Authorization': 'Bearer $token',
          'X-Youtube-Client-Name': '7',
          'X-Youtube-Client-Version': tvClientVersion,
          'Referer': 'https://www.youtube.com/tv',
          'Origin': 'https://www.youtube.com',
        });
    final st = j['_status'] as int;
    if (st == 401 || st == 403) throw CtYtAuthError('YouTube отклонил вход ($st)');
    if (st >= 400) throw 'YouTube $endpoint: ${(j['error'] as Map?)?['message'] ?? st}';
    return j;
  }

  /// Лента (browseId: default — рекомендации, FEsubscriptions, FEhistory) или её продолжение.
  static Future<CtTvPage> browse(String refresh, {String? browseId, String? continuation}) async {
    final j = await innertube(refresh, 'browse', continuation != null ? {'continuation': continuation} : {'browseId': browseId});
    return CtTvPage.parse(j);
  }

  static Future<void> subscribe(String refresh, String channelId, bool on) async {
    await innertube(refresh, on ? 'subscription/subscribe' : 'subscription/unsubscribe', {
      'channelIds': [channelId]
    });
  }
}

class CtYtAuthError implements Exception {
  final String message;

  CtYtAuthError(this.message);

  @override
  String toString() => message;
}

class CtDeviceCode {
  final String deviceCode, userCode, verificationUrl;
  final int interval, expiresIn;

  CtDeviceCode(this.deviceCode, this.userCode, this.verificationUrl, this.interval, this.expiresIn);
}

/// Разбор ответа YouTube для ТВ: собираем все плитки-ролики, каналы и токен продолжения,
/// не завися от точной вложенности разделов (она у YouTube часто меняется).
class CtTvPage {
  final List<Map<String, dynamic>> videos = [];
  final List<Map<String, dynamic>> channels = [];
  String? continuation;

  static CtTvPage parse(Map<String, dynamic> j) {
    final p = CtTvPage();
    final seenV = <String>{};
    final seenC = <String>{};
    void walk(dynamic n) {
      if (n is Map) {
        final tile = n['tileRenderer'];
        if (tile is Map) {
          final v = _tile(tile);
          if (v != null && seenV.add('${v['videoId']}')) p.videos.add(v);
        }
        final next = n['nextContinuationData'] ?? n['reloadContinuationData'];
        if (p.continuation == null && next is Map && next['continuation'] is String) p.continuation = next['continuation'] as String;
        final cmd = n['continuationCommand'];
        if (p.continuation == null && cmd is Map && cmd['token'] is String) p.continuation = cmd['token'] as String;
        // канал в левой колонке «Подписок» (вкладка с аватаром)
        final tab = n['tabRenderer'];
        if (tab is Map) {
          final id = _find(tab['endpoint'], 'browseId');
          final title = _text(tab['title']);
          if (id is String && id.startsWith('UC') && title.isNotEmpty && seenC.add(id)) {
            final thumbs = _find(tab['thumbnail'], 'thumbnails');
            p.channels.add({
              'author': title,
              'authorId': id,
              'authorThumbnails': thumbs is List ? thumbs : const [],
            });
          }
        }
        n.values.forEach(walk);
      } else if (n is List) {
        n.forEach(walk);
      }
    }

    walk(j);
    return p;
  }

  static Map<String, dynamic>? _tile(Map tile) {
    final type = '${tile['contentType'] ?? ''}';
    if (type.isNotEmpty && !type.contains('VIDEO') && !type.contains('SHORTS')) return null;
    final sel = tile['onSelectCommand'];
    final id = (sel is Map ? (sel['watchEndpoint'] ?? sel['reelWatchEndpoint']) : null)?['videoId'] ?? tile['contentId'];
    if (id is! String || id.length != 11) return null;
    final meta = (tile['metadata'] as Map?)?['tileMetadataRenderer'] as Map?;
    final title = _text(meta?['title']);
    final lines = (meta?['lines'] as List?) ?? const [];
    String line(int i) {
      if (i >= lines.length) return '';
      final items = ((lines[i] as Map?)?['lineRenderer'] as Map?)?['items'] as List? ?? const [];
      return items
          .map((e) => _text(((e as Map?)?['lineItemRenderer'] as Map?)?['text']))
          .where((s) => s.trim().isNotEmpty && s.trim() != '•')
          .join(' • ');
    }

    final author = line(0);
    final info = line(1);
    var duration = 0;
    final overlays = ((tile['header'] as Map?)?['tileHeaderRenderer'] as Map?)?['thumbnailOverlays'] as List? ?? const [];
    for (final o in overlays) {
      final t = _text(((o as Map?)?['thumbnailOverlayTimeStatusRenderer'] as Map?)?['text']);
      if (RegExp(r'^\d+(:\d+)+$').hasMatch(t)) {
        duration = t.split(':').fold(0, (a, b) => a * 60 + int.parse(b));
      }
    }
    final ch = _findWhere(tile, (k, v) => k == 'browseId' && v is String && v.startsWith('UC'));
    final views = RegExp(r'([\d\s ,.]+)\s*(тыс|млн|млрд|K|M|B)?\.?\s*(просм|view)', caseSensitive: false).firstMatch(info);
    final v = {
      'type': 'video',
      'videoId': id,
      'title': title,
      'author': author,
      'authorId': ch ?? '',
      'authorUrl': ch == null ? '' : '/channel/$ch',
      'lengthSeconds': duration,
      'viewCount': views == null ? 0 : _num(views.group(1)!, views.group(2)),
      'published': 0,
      'publishedText': info.split(' • ').lastWhere((s) => !s.contains(RegExp('просм|view', caseSensitive: false)), orElse: () => ''),
      'liveNow': type.contains('LIVE'),
      'videoThumbnails': [
        {'quality': 'high', 'url': 'https://i.ytimg.com/vi/$id/hqdefault.jpg', 'width': 480, 'height': 360},
        {'quality': 'medium', 'url': 'https://i.ytimg.com/vi/$id/mqdefault.jpg', 'width': 320, 'height': 180},
      ],
      'description': '',
    };
    ctDirectBriefs[id] = v;
    if (ctDirectBriefs.length > 2000) ctDirectBriefs.remove(ctDirectBriefs.keys.first);
    return v;
  }

  static int _num(String n, String? unit) {
    final x = double.tryParse(n.replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.')) ?? 0;
    final m = switch ((unit ?? '').toLowerCase()) { 'тыс' || 'k' => 1e3, 'млн' || 'm' => 1e6, 'млрд' || 'b' => 1e9, _ => 1 };
    return (x * m).round();
  }

  static String _text(dynamic t) {
    if (t is! Map) return '';
    if (t['simpleText'] is String) return t['simpleText'] as String;
    final runs = t['runs'];
    if (runs is List) return runs.map((r) => (r as Map?)?['text'] ?? '').join();
    return '';
  }

  static dynamic _find(dynamic n, String key) => _findWhere(n, (k, _) => k == key);

  static dynamic _findWhere(dynamic n, bool Function(String k, dynamic v) test) {
    if (n is Map) {
      for (final e in n.entries) {
        if (test('${e.key}', e.value)) return e.value;
      }
      for (final v in n.values) {
        final r = _findWhere(v, test);
        if (r != null) return r;
      }
    } else if (n is List) {
      for (final v in n) {
        final r = _findWhere(v, test);
        if (r != null) return r;
      }
    }
    return null;
  }
}
