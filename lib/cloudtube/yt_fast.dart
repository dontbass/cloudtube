import 'dart:async';
import 'net.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'trace.dart';
import 'hls_local.dart';
import 'direct.dart' show kCtVisionUserAgent;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

final _log = Logger('CtYtFast');

/// Быстрое получение видео без сервера — как это делают NewPipe/LibreTube/SmartTube:
/// сразу запросы InnerTube «player» (iOS → HLS-мастер, ANDROID_VR → поток со звуком),
/// без загрузки HTML-страницы просмотра (~1 МБ) и без лишних проверок.
/// Описание, канал и рекомендации — отдельным запросом «next» параллельно.
class CtYtFast {
  static http.Client client = ctHttp;

  /// Нужны адаптивные потоки (ТВ: своё DASH-качество) — тогда ждём ответа VISIONOS.
  static bool wantAdaptive = false;
  static String? _visitor;
  static Future<String?>? _visitorFut;

  static Future<String?> visitorData() {
    if (_visitor != null) return Future.value(_visitor);
    return _visitorFut ??= () async {
      try {
        final r = await client.get(Uri.parse('https://www.youtube.com/sw.js_data'), headers: {
          'User-Agent': yt.YoutubeApiClient.ios.payload['context']['client']['userAgent'] as String,
        }).timeout(const Duration(seconds: 4));
        var b = r.body;
        if (b.startsWith(")]}'")) b = b.substring(4);
        _visitor = (jsonDecode(b) as List)[0][2][0][0][13] as String?;
      } catch (e) {
        _log.info('visitorData: $e');
      }
      _visitorFut = null;
      return _visitor;
    }();
  }

  /// Ответ «player» от указанного клиента или null, если видео ему недоступно.
  static Future<Map<String, dynamic>?> player(String id, yt.YoutubeApiClient c) async {
    final cl = Map<String, dynamic>.from(c.payload['context']['client'] as Map);
    final name = cl['clientName'];
    if (name == 'IOS') {
      final v = await visitorData();
      if (v != null) cl['visitorData'] = v;
    }
    cl['hl'] = 'ru';
    final body = {
      ...c.payload,
      'context': {...(c.payload['context'] as Map), 'client': cl},
      'videoId': id,
      'contentCheckOk': true,
      'racyCheckOk': true,
    };
    final r = await client
        .post(Uri.parse(c.apiUrl), body: jsonEncode(body), headers: {
          'Content-Type': 'application/json',
          'User-Agent': (cl['userAgent'] as String?) ??
              (name == 'ANDROID_VR'
                  ? 'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12; eureka-user Build/SQ3A.220605.009.A1) gzip'
                  : 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip'),
          'X-Youtube-Client-Name': name == 'IOS' ? '5' : (name == 'ANDROID_VR' ? '28' : '3'),
          'X-Youtube-Client-Version': '${cl['clientVersion']}',
          if (cl['visitorData'] != null) 'X-Goog-Visitor-Id': '${cl['visitorData']}',
          'Origin': 'https://www.youtube.com',
        })
        .timeout(const Duration(seconds: 7));
    if (r.statusCode != 200) return null;
    final j = (await ctJsonDecodeBytes(r.bodyBytes)) as Map<String, dynamic>;
    final st = (j['playabilityStatus'] as Map?)?['status'];
    if (st != 'OK') {
      _log.info('player $name $id: $st ${(j['playabilityStatus'] as Map?)?['reason'] ?? ''}');
      return null;
    }
    return j;
  }

  /// «player» клиента VISIONOS (YouTube для Apple Vision Pro): адаптивные потоки до 4K,
  /// без PO-токена; ANDROID_VR с августа 2026 отдаёт ссылки, которые рвутся через ~1 минуту.
  static Future<Map<String, dynamic>?> playerVision(String id) async {
    final v = await visitorData();
    final body = {
      'context': {
        'client': {
          'clientName': 'VISIONOS',
          'clientVersion': '1.02',
          'deviceMake': 'Apple',
          'deviceModel': 'RealityDevice17,1',
          'osName': 'visionOS',
          'osVersion': '26.5.23O471',
          'userAgent': kCtVisionUserAgent,
          'hl': 'ru',
          'gl': 'US',
          if (v != null) 'visitorData': v,
        }
      },
      'videoId': id,
      'contentCheckOk': true,
      'racyCheckOk': true,
    };
    final r = await client
        .post(Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
            body: jsonEncode(body),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': kCtVisionUserAgent,
              'X-Youtube-Client-Name': '101',
              'X-Youtube-Client-Version': '1.02',
              if (v != null) 'X-Goog-Visitor-Id': v,
              'Origin': 'https://www.youtube.com',
              'Referer': 'https://www.youtube.com/',
            })
        .timeout(const Duration(seconds: 7));
    if (r.statusCode != 200) {
      _log.info('player VISIONOS $id: HTTP ${r.statusCode}');
      return null;
    }
    final j = (await ctJsonDecodeBytes(r.bodyBytes)) as Map<String, dynamic>;
    final st = (j['playabilityStatus'] as Map?)?['status'];
    if (st != 'OK') {
      _log.info('player VISIONOS $id: $st ${(j['playabilityStatus'] as Map?)?['reason'] ?? ''}');
      return null;
    }
    // без прямых ссылок (только шифр) нам не годится
    final af = (j['streamingData'] as Map?)?['adaptiveFormats'] as List?;
    if (af == null || !af.any((f) => f is Map && f['url'] is String)) return null;
    return j;
  }

  /// «next» (клиент WEB): канал, подписчики, лайки, дата и рекомендации.
  static Future<Map<String, dynamic>> next(String id) async {
    final r = await client
        .post(Uri.parse('https://www.youtube.com/youtubei/v1/next?prettyPrint=false'),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
              'X-Youtube-Client-Name': '1',
              'X-Youtube-Client-Version': '2.20251110.01.00',
              'Origin': 'https://www.youtube.com',
            },
            body: jsonEncode({
              'context': {
                'client': {'clientName': 'WEB', 'clientVersion': '2.20251110.01.00', 'hl': 'ru', 'gl': 'RU'}
              },
              'videoId': id,
            }))
        .timeout(const Duration(seconds: 6));
    if (r.statusCode != 200) throw 'next ${r.statusCode}';
    return (await ctJsonDecodeBytes(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// Поиск через InnerTube (JSON, как приложение YouTube), а не через HTML-страницу результатов.
  /// params EgIYAQ== — короткие видео (до 4 мин). Возвращает ролики и токен продолжения.
  static Future<(List<Map<String, dynamic>>, String?)> searchShorts(String query, {String? continuation}) async {
    final r = await client
        .post(Uri.parse('https://www.youtube.com/youtubei/v1/search?prettyPrint=false'),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
              'X-Youtube-Client-Name': '1',
              'X-Youtube-Client-Version': '2.20251110.01.00',
              'Origin': 'https://www.youtube.com',
            },
            body: jsonEncode({
              'context': {
                'client': {'clientName': 'WEB', 'clientVersion': '2.20251110.01.00', 'hl': 'ru', 'gl': 'RU'}
              },
              if (continuation != null) 'continuation': continuation else ...{'query': query, 'params': 'EgIYAQ=='},
            }))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) throw 'search ${r.statusCode}';
    final j = await ctJsonDecodeBytes(r.bodyBytes);
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    String? next;
    void add(String id, String title, String author, String ch, int len) {
      if (id.length != 11 || !seen.add(id)) return;
      out.add({
        'type': 'video',
        'videoId': id,
        'title': title,
        'author': author,
        'authorId': ch,
        'authorUrl': ch.isEmpty ? '' : '/channel/$ch',
        'lengthSeconds': len,
        'viewCount': 0,
        'published': 0,
        'publishedText': '',
        'videoThumbnails': thumbs(id),
      });
    }

    void walk(dynamic x) {
      if (x is Map) {
        final v = x['videoRenderer'];
        if (v is Map && v['videoId'] is String) {
          final ch = _find(v['ownerText'] ?? v['longBylineText'], 'browseId');
          add(v['videoId'] as String, _text(v['title']), _text(v['ownerText'] ?? v['longBylineText']), '${ch ?? ''}',
              _dur(_text(v['lengthText'])));
        }
        final sl = x['shortsLockupViewModel'];
        if (sl is Map) {
          final id = _find(sl['onTap'], 'videoId');
          final title = _find(sl['overlayMetadata'], 'primaryText');
          if (id is String) add(id, title is Map ? '${title['content'] ?? ''}' : '', '', '', 0);
        }
        final reel = x['reelItemRenderer'];
        if (reel is Map && reel['videoId'] is String) add(reel['videoId'] as String, _text(reel['headline']), '', '', 0);
        final cmd = x['continuationCommand'];
        if (cmd is Map && cmd['token'] is String) next = cmd['token'] as String;
        x.values.forEach(walk);
      } else if (x is List) {
        x.forEach(walk);
      }
    }

    walk(j);
    return (out, next);
  }

  static List<Map<String, dynamic>> thumbs(String id) => [
        {'quality': 'maxres', 'url': 'https://i.ytimg.com/vi/$id/maxresdefault.jpg', 'width': 1280, 'height': 720},
        {'quality': 'sddefault', 'url': 'https://i.ytimg.com/vi/$id/sddefault.jpg', 'width': 640, 'height': 480},
        {'quality': 'high', 'url': 'https://i.ytimg.com/vi/$id/hqdefault.jpg', 'width': 480, 'height': 360},
        {'quality': 'medium', 'url': 'https://i.ytimg.com/vi/$id/mqdefault.jpg', 'width': 320, 'height': 180},
      ];

  /// Собрать JSON видео в формате Invidious. null — быстрый путь не сработал.
  static Future<Map<String, dynamic>?> video(String id) async {
    final sw = Stopwatch()..start();
    CtTrace.mark('адаптер: запросы к YouTube');
    final iosF = player(id, yt.YoutubeApiClient.ios).catchError((e) {
      _log.info('ios $id: $e');
      return null;
    });
    final vrF = player(id, yt.YoutubeApiClient.androidVr).catchError((e) {
      _log.info('vr $id: $e');
      return null;
    });
    // третий клиент — ANDROID: если VR откажет (бывает на отдельных роликах), поток со звуком возьмём у него
    final anF = player(id, yt.YoutubeApiClient.androidSdkless).catchError((e) {
      _log.info('android $id: $e');
      return null;
    });
    unawaited(anF.then((_) {}, onError: (_) {}));
    final visF = playerVision(id).catchError((e) {
      _log.info('visionos $id: $e');
      return null;
    });
    final nextF = next(id);
    unawaited(nextF.then((_) {}, onError: (_) {}));
    final ios = await iosF;
    CtTrace.mark('адаптер: player iOS ${ios != null ? 'ok' : 'нет'}');
    var vr = await vrF;
    CtTrace.mark('адаптер: player VR ${vr != null ? 'ok' : 'нет'}');
    if (vr == null || ((vr['streamingData'] as Map?)?['formats'] as List?)?.isEmpty != false) {
      final an = await anF;
      CtTrace.mark('адаптер: player ANDROID ${an != null ? 'ok' : 'нет'}');
      if (an != null) vr = an;
    }
    // VISIONOS ждём не дольше 2,5 с: нужен для качественных адаптивных потоков (ТВ, 4K)
    Map<String, dynamic>? vis;
    if (wantAdaptive) {
      try {
        vis = await visF.timeout(const Duration(milliseconds: 2500));
      } catch (_) {}
    } else {
      // телефон играет HLS — не ждём; потоки VISIONOS запомним, когда придут
      unawaited(visF.then((v) {
        final af = (v?['streamingData'] as Map?)?['adaptiveFormats'] as List?;
        if (af != null) CtDashLocal.remember(id, af, (int.tryParse('${(v?['videoDetails'] as Map?)?['lengthSeconds'] ?? 0}') ?? 0) * 1000);
      }, onError: (_) {}));
    }
    CtTrace.mark('адаптер: player VISIONOS ${vis != null ? 'ok' : 'нет'}');
    final base = ios ?? vis ?? vr;
    if (base == null) return null;
    final d = (base['videoDetails'] as Map?) ?? const {};
    final j = <String, dynamic>{
      'type': 'video',
      'videoId': id,
      'title': '${d['title'] ?? ''}',
      'author': '${d['author'] ?? ''}',
      'authorId': '${d['channelId'] ?? ''}',
      'authorUrl': '/channel/${d['channelId'] ?? ''}',
      'lengthSeconds': int.tryParse('${d['lengthSeconds'] ?? 0}') ?? 0,
      'viewCount': int.tryParse('${d['viewCount'] ?? 0}') ?? 0,
      'published': 0,
      'publishedText': '',
      'liveNow': d['isLive'] == true,
      'videoThumbnails': thumbs(id),
      'description': '${d['shortDescription'] ?? ''}',
      'descriptionHtml': const HtmlEscape().convert('${d['shortDescription'] ?? ''}').replaceAll('\n', '<br>'),
      'keywords': (d['keywords'] as List?) ?? const [],
      'likeCount': 0,
      'allowRatings': true,
      'isListed': true,
      'recommendedVideos': <Map<String, dynamic>>[],
    };
    final mf = (vr?['microformat'] ?? ios?['microformat']) as Map?;
    final pd = (mf?['playerMicroformatRenderer'] as Map?)?['publishDate'] ?? (mf?['playerMicroformatRenderer'] as Map?)?['uploadDate'];
    final pdt = pd is String ? DateTime.tryParse(pd) : null;
    if (pdt != null) j['published'] = pdt.millisecondsSinceEpoch ~/ 1000;

    final hls = (ios?['streamingData'] as Map?)?['hlsManifestUrl'] ?? (vr?['streamingData'] as Map?)?['hlsManifestUrl'];
    if (hls is String) j['hlsUrl'] = hls;
    // адаптивные потоки — от VISIONOS (не рвутся через минуту), иначе от VR/ANDROID
    final sd = (vr?['streamingData'] as Map?) ?? const {};
    final sdAdaptive = (vis?['streamingData'] as Map?) ?? sd;
    j['formatStreams'] = [
      for (final f in (sd['formats'] as List?) ?? const [])
        if (f is Map && f['url'] is String)
          {
            'url': f['url'],
            'itag': '${f['itag']}',
            'type': '${f['mimeType']}',
            'quality': '${f['quality'] ?? ''}',
            'container': '${f['mimeType']}'.contains('webm') ? 'webm' : 'mp4',
            'encoding': '',
            'qualityLabel': '${f['qualityLabel'] ?? '360p'}',
            'resolution': '${f['height'] ?? 360}p',
            'size': '${f['width'] ?? 640}x${f['height'] ?? 360}',
          }
    ];
    j['adaptiveFormats'] = [
      for (final f in (sdAdaptive['adaptiveFormats'] as List?) ?? const [])
        if (f is Map && f['url'] is String)
          {
            'url': f['url'],
            'itag': '${f['itag']}',
            'type': '${f['mimeType']}',
            'bitrate': '${f['bitrate'] ?? 0}',
            'clen': '${f['contentLength'] ?? 0}',
            'lmt': '0',
            'projectionType': 'RECTANGULAR',
            'container': '${f['mimeType']}'.contains('webm') ? 'webm' : 'mp4',
            'encoding': '',
            if (f['qualityLabel'] != null) 'qualityLabel': '${f['qualityLabel']}',
            if (f['height'] != null) 'resolution': '${f['height']}p',
            if (f['width'] != null) 'size': '${f['width']}x${f['height']}',
            if (f['audioQuality'] != null) 'audioQuality': '${f['audioQuality']}',
          }
    ];
    // сырые форматы (с initRange/indexRange) — для своего DASH на ТВ
    CtDashLocal.remember(id, sdAdaptive['adaptiveFormats'] as List?, (j['lengthSeconds'] as int) * 1000);
    if (j['hlsUrl'] == null && (j['formatStreams'] as List).isEmpty) {
      CtTrace.mark('адаптер: нет ни HLS, ни потока со звуком → запасной путь');
      return null;
    }
    final streamsMs = sw.elapsedMilliseconds;

    // «next» ждём не дольше 0,7 с после готовности потоков — видео важнее
    try {
      final n = await nextF.timeout(const Duration(milliseconds: 700));
      CtTrace.mark('адаптер: next получен');
      _applyNext(j, n);
      CtTrace.mark('адаптер: next разобран');
    } catch (_) {
      CtTrace.mark('адаптер: next не успел — догрузится в фоне');
      // догрузим в фоне — при следующем открытии будет полностью
      unawaited(nextF.then((n) => _applyNext(j, n), onError: (_) {}));
    }
    CtTrace.mark('адаптер: готово (hls=${j['hlsUrl'] != null}, 360p=${(j['formatStreams'] as List).isNotEmpty})');
    _log.info('fast $id: потоки ${streamsMs}мс, всего ${sw.elapsedMilliseconds}мс, '
        'hls=${j['hlsUrl'] != null} muxed=${(j['formatStreams'] as List).length} rec=${(j['recommendedVideos'] as List).length}');
    return j;
  }

  static void _applyNext(Map<String, dynamic> j, Map<String, dynamic> n) {
    final owner = _find(n, 'videoOwnerRenderer');
    if (owner is Map) {
      final th = _find(owner['thumbnail'], 'thumbnails');
      if (th is List && th.isNotEmpty) {
        j['authorThumbnails'] = [
          for (final t in th)
            if (t is Map && t['url'] is String)
              {
                'url': (t['url'] as String).startsWith('//') ? 'https:${t['url']}' : t['url'],
                'width': t['width'] ?? 88,
                'height': t['height'] ?? 88,
                'quality': 'default',
              }
        ];
      }
      final sub = _text(owner['subscriberCountText']);
      if (sub.isNotEmpty) j['subCountText'] = sub.replaceAll(RegExp(r'\s*подписчик\S*', caseSensitive: false), '');
    }
    final primary = _find(n, 'videoPrimaryInfoRenderer');
    if (primary is Map) {
      final date = _text(primary['dateText']);
      if (date.isNotEmpty) {
        j['publishedText'] = date;
        final m = RegExp(r'(\d{1,2})\s+([а-яё]{3})\S*\s+(\d{4})', caseSensitive: false).firstMatch(date);
        const months = ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
        if (m != null && (j['published'] ?? 0) == 0) {
          var mi = months.indexOf(m.group(2)!.toLowerCase());
          if (mi < 0 && m.group(2)!.toLowerCase() == 'май') mi = 4;
          if (mi >= 0) {
            j['published'] = DateTime.utc(int.parse(m.group(3)!), mi + 1, int.parse(m.group(1)!)).millisecondsSinceEpoch ~/ 1000;
          }
        }
      }
    }
    final like = _find(n, 'likeCountIfIndifferentNumber') ?? _find(n, 'likeCountIfLikedNumber');
    if (like != null) j['likeCount'] = int.tryParse('$like') ?? 0;
    final sec = _find(n, 'secondaryResults');
    final rec = <Map<String, dynamic>>[];
    final seen = <String>{};
    void walk(dynamic x) {
      if (x is Map) {
        final c = x['compactVideoRenderer'];
        if (c is Map && c['videoId'] is String && seen.add(c['videoId'] as String)) {
          final vid = c['videoId'] as String;
          final ch = _find(c['longBylineText'] ?? c['shortBylineText'], 'browseId');
          rec.add({
            'type': 'video',
            'videoId': vid,
            'title': _text(c['title']),
            'author': _text(c['longBylineText'] ?? c['shortBylineText']),
            'authorId': '${ch ?? ''}',
            'authorUrl': '/channel/${ch ?? ''}',
            'lengthSeconds': _dur(_text(c['lengthText'])),
            'viewCount': _views(_text(c['viewCountText'])),
            'viewCountText': _text(c['shortViewCountText']),
            'published': 0,
            'publishedText': _text(c['publishedTimeText']),
            'videoThumbnails': thumbs(vid),
          });
        }
        final l = x['lockupViewModel'];
        if (l is Map && '${l['contentType']}'.contains('VIDEO') && l['contentId'] is String && seen.add(l['contentId'] as String)) {
          final vid = l['contentId'] as String;
          final meta = _find(l['metadata'], 'lockupMetadataViewModel') as Map?;
          final title = '${(meta?['title'] as Map?)?['content'] ?? ''}';
          final parts = <String>[];
          final rows = _find(meta, 'metadataRows');
          if (rows is List) {
            for (final r in rows) {
              for (final p in ((r as Map?)?['metadataParts'] as List?) ?? const []) {
                final t = ((p as Map?)?['text'] as Map?)?['content'];
                if (t is String && t.trim().isNotEmpty) parts.add(t.trim());
              }
            }
          }
          var dur = 0;
          void badges(dynamic b) {
            if (b is Map) {
              final t = (b['thumbnailBadgeViewModel'] as Map?)?['text'];
              if (t is String && RegExp(r'^\d+(:\d+)+$').hasMatch(t)) dur = _dur(t);
              b.values.forEach(badges);
            } else if (b is List) {
              b.forEach(badges);
            }
          }

          badges(l['contentImage']);
          final ch = _findWhere(l, (k, v) => k == 'browseId' && v is String && v.startsWith('UC'));
          rec.add({
            'type': 'video',
            'videoId': vid,
            'title': title,
            'author': parts.isNotEmpty ? parts.first : '',
            'authorId': '${ch ?? ''}',
            'authorUrl': '/channel/${ch ?? ''}',
            'lengthSeconds': dur,
            'viewCount': parts.length > 1 ? _views(parts[1]) : 0,
            'published': 0,
            'publishedText': parts.length > 2 ? parts[2] : '',
            'videoThumbnails': thumbs(vid),
          });
        }
        x.values.forEach(walk);
      } else if (x is List) {
        x.forEach(walk);
      }
    }

    walk(sec);
    if (rec.isNotEmpty) j['recommendedVideos'] = rec;
  }

  static int _dur(String t) {
    if (!RegExp(r'^\d+(:\d+)+$').hasMatch(t.trim())) return 0;
    return t.trim().split(':').fold(0, (a, b) => a * 60 + int.parse(b));
  }

  static int _views(String s) {
    final m = RegExp(r'([\d.,\s ]+)\s*(тыс|млн|млрд|K|M|B)?', caseSensitive: false).firstMatch(s);
    if (m == null) return 0;
    final x = double.tryParse(m.group(1)!.replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.')) ?? 0;
    final u = (m.group(2) ?? '').toLowerCase();
    final k = switch (u) { 'тыс' || 'k' => 1e3, 'млн' || 'm' => 1e6, 'млрд' || 'b' => 1e9, _ => 1 };
    return (x * k).round();
  }

  static String _text(dynamic t) {
    if (t is! Map) return '';
    if (t['simpleText'] is String) return t['simpleText'] as String;
    if (t['content'] is String) return t['content'] as String;
    final runs = t['runs'];
    if (runs is List) return runs.map((r) => (r as Map?)?['text'] ?? '').join();
    return '';
  }

  static dynamic _find(dynamic n, String key) => _findWhere(n, (k, _) => k == key);

  /// Первое значение по ключу в глубине JSON-ответа InnerTube.
  static dynamic findKey(dynamic n, String key) => _find(n, key);

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
