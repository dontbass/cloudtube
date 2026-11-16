import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

final _log = Logger('CtHlsLocal');

/// ТВ: ExoPlayer по мастер-плейлисту HLS начинает с самого низкого качества (оценка скорости
/// на старте занижена), а на приставках часто так и остаётся на 360p.
/// Решение: отдаём плееру тот же мастер-плейлист, но без вариантов ниже нужной высоты.
/// Плейлист раздаётся с 127.0.0.1 — для плеера это обычный http, поэтому заголовки (User-Agent
/// клиента iOS, без него YouTube отвечает 403) уходят и на все дальнейшие запросы к googlevideo.
class CtHlsLocal {
  static HttpServer? _srv;
  static final _lists = <String, String>{};
  static var _n = 0;

  static Future<int> _port() async {
    if (_srv != null) return _srv!.port;
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _srv = s;
    s.listen((req) {
      final name = req.uri.pathSegments.isNotEmpty ? req.uri.pathSegments.last : '';
      final body = _lists[name];
      if (body == null) {
        req.response.statusCode = 404;
      } else {
        req.response.headers.contentType = name.endsWith('.mpd')
            ? ContentType('application', 'dash+xml', charset: 'utf-8')
            : ContentType('application', 'vnd.apple.mpegurl');
        req.response.write(body);
      }
      req.response.close();
    });
    return s.port;
  }

  /// Адрес отфильтрованного мастер-плейлиста или null (оставить исходный).
  static Future<String?> atLeast(String masterUrl, Map<String, String> headers,
      {int minHeight = 720, int maxHeight = 1080}) async {
    try {
      final r = await http.get(Uri.parse(masterUrl), headers: headers).timeout(const Duration(seconds: 6));
      if (r.statusCode != 200 || !r.body.contains('#EXT-X-STREAM-INF')) return null;
      final lines = r.body.split('\n');
      final out = <String>[];
      var kept = 0, total = 0;
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.startsWith('#EXT-X-STREAM-INF')) {
          total++;
          final h = int.tryParse(RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(l)?.group(1) ?? '') ?? 0;
          final uri = i + 1 < lines.length ? lines[i + 1] : '';
          if (h >= minHeight && h <= maxHeight) {
            out..add(_abs(masterUrl, l))..add(_absUri(masterUrl, uri));
            kept++;
          }
          i++; // строка с адресом варианта уже обработана
          continue;
        }
        out.add(_abs(masterUrl, l));
      }
      if (kept == 0) return null; // нужного качества нет — пусть ExoPlayer выбирает сам
      final id = '${++_n}.m3u8';
      _lists[id] = out.join('\n');
      if (_lists.length > 20) _lists.remove(_lists.keys.first);
      final port = await _port();
      _log.info('HLS: оставлено $kept из $total вариантов ($minHeight–${maxHeight}p)');
      return 'http://127.0.0.1:$port/$id';
    } catch (e) {
      _log.info('HLS filter: $e');
      return null;
    }
  }

  /// Плейлист раздаётся с 127.0.0.1 — относительные адреса надо сделать абсолютными.
  static String _absUri(String base, String u) {
    final t = u.trim();
    if (t.isEmpty || t.startsWith('#') || t.startsWith('http')) return u;
    return Uri.parse(base).resolve(t).toString();
  }

  static String _abs(String base, String line) {
    if (!line.startsWith('#')) return _absUri(base, line);
    return line.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (m) {
      final u = m.group(1)!;
      return u.startsWith('http') ? m.group(0)! : 'URI="${Uri.parse(base).resolve(u)}"';
    });
  }
}

/// ТВ без сервера: свой DASH-манифест с ОДНИМ видеокачеством (как в SmartTube — по умолчанию
/// лучшее доступное, профиль качества лишь ограничивает сверху). ExoPlayer не может «съехать»
/// на 360p: другого видео в манифесте просто нет. Звук — лучшая дорожка mp4a.
class CtDashLocal {
  static final _raw = <String, (List, int)>{};

  /// Запомнить адаптивные форматы ролика (сырые, из ответа player) — вызывается адаптером.
  static void remember(String id, List? formats, int durationMs) {
    if (formats == null || formats.isEmpty) return;
    _raw[id] = (formats, durationMs);
    if (_raw.length > 30) _raw.remove(_raw.keys.first);
  }

  static int _h(Map f) => (f['height'] as num?)?.toInt() ?? 0;
  static int _fps(Map f) => (f['fps'] as num?)?.toInt() ?? 30;
  static int _br(Map f) => (f['bitrate'] as num?)?.toInt() ?? 0;

  static bool _ok(Map f) =>
      f['url'] is String && f['initRange'] is Map && f['indexRange'] is Map && f['mimeType'] is String;

  /// (адрес манифеста, высота кадра, адрес первой дорожки для заголовков) или null.
  static Future<(String, int, String)?> build(String id, {int maxHeight = 1080, bool allowVp9 = false}) async {
    final e = _raw[id];
    if (e == null) return null;
    final all = e.$1.whereType<Map>().where(_ok).toList();
    bool avc(Map f) => '${f['mimeType']}'.contains('avc1');
    bool vp9(Map f) => '${f['mimeType']}'.contains('vp9') || '${f['mimeType']}'.contains('vp09');
    final videos = all
        .where((f) => '${f['mimeType']}'.startsWith('video/') && _h(f) > 0 && _h(f) <= maxHeight)
        .where((f) => avc(f) || (allowVp9 && vp9(f)))
        .toList()
      // выше кадр — лучше; при равной высоте — 30 к/с (60 к/с тяжело для слабых приставок), затем битрейт
      ..sort((a, b) {
        final c = _h(b).compareTo(_h(a));
        if (c != 0) return c;
        final fa = _fps(a) > 30 ? 1 : 0, fb = _fps(b) > 30 ? 1 : 0;
        if (fa != fb) return fa.compareTo(fb);
        return _br(b).compareTo(_br(a));
      });
    final audios = all
        .where((f) => '${f['mimeType']}'.startsWith('audio/mp4'))
        .toList()
      ..sort((a, b) => _br(b).compareTo(_br(a)));
    if (videos.isEmpty || audios.isEmpty) return null;
    final v = videos.first, a = audios.first;
    if (_h(v) < 480) return null; // ничего лучше 360p — пусть играет как обычно
    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
    String codecs(Map f) => RegExp(r'codecs="([^"]+)"').firstMatch('${f['mimeType']}')?.group(1) ?? '';
    String mime(Map f) => '${f['mimeType']}'.split(';').first.trim();
    String rep(Map f, bool video) {
      final ir = f['initRange'] as Map, xr = f['indexRange'] as Map;
      final attrs = video
          ? 'width="${f['width'] ?? 0}" height="${_h(f)}" frameRate="${_fps(f)}"'
          : 'audioSamplingRate="${f['audioSampleRate'] ?? 44100}"';
      return '<Representation id="${f['itag']}" codecs="${codecs(f)}" bandwidth="${_br(f)}" $attrs>'
          '${video ? '' : '<AudioChannelConfiguration schemeIdUri="urn:mpeg:dash:23003:3:audio_channel_configuration:2011" value="${f['audioChannels'] ?? 2}"/>'}'
          '<BaseURL>${esc(f['url'])}</BaseURL>'
          '<SegmentBase indexRange="${xr['start']}-${xr['end']}"><Initialization range="${ir['start']}-${ir['end']}"/></SegmentBase>'
          '</Representation>';
    }

    var durMs = e.$2;
    if (durMs <= 0) durMs = int.tryParse('${v['approxDurationMs'] ?? 0}') ?? 0;
    final mpd = '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" profiles="urn:mpeg:dash:profile:isoff-on-demand:2011" '
        'type="static" minBufferTime="PT1.5S" mediaPresentationDuration="PT${(durMs / 1000).toStringAsFixed(3)}S">'
        '<Period>'
        '<AdaptationSet mimeType="${mime(v)}" subsegmentAlignment="true" startWithSAP="1">${rep(v, true)}</AdaptationSet>'
        '<AdaptationSet mimeType="${mime(a)}" lang="und" subsegmentAlignment="true" startWithSAP="1">${rep(a, false)}</AdaptationSet>'
        '</Period></MPD>';
    final name = 'd${++CtHlsLocal._n}.mpd';
    CtHlsLocal._lists[name] = mpd;
    if (CtHlsLocal._lists.length > 20) CtHlsLocal._lists.remove(CtHlsLocal._lists.keys.first);
    final port = await CtHlsLocal._port();
    return ('http://127.0.0.1:$port/$name', _h(v), v['url'] as String);
  }
}
