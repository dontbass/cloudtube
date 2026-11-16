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

  /// Мастер-плейлист с ОДНИМ вариантом видео — лучшим не выше [cap] (при равной высоте —
  /// 30 к/с, затем больший битрейт). ExoPlayer не может сам уйти на низкое качество.
  /// (адрес, высота) или null.
  static Future<(String, int)?> single(String masterUrl, Map<String, String> headers, {int cap = 2160}) async {
    try {
      final r = await http.get(Uri.parse(masterUrl), headers: headers).timeout(const Duration(seconds: 6));
      if (r.statusCode != 200 || !r.body.contains('#EXT-X-STREAM-INF')) return null;
      final lines = r.body.split('\n');
      int h(String l) => int.tryParse(RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(l)?.group(1) ?? '') ?? 0;
      double fps(String l) => double.tryParse(RegExp(r'FRAME-RATE=([\d.]+)').firstMatch(l)?.group(1) ?? '') ?? 30;
      int bw(String l) => int.tryParse(RegExp(r'[^-]BANDWIDTH=(\d+)').firstMatch(l)?.group(1) ?? '') ?? 0;
      int? best;
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (!l.startsWith('#EXT-X-STREAM-INF') || h(l) > cap || h(l) <= 0) continue;
        if (best == null) {
          best = i;
          continue;
        }
        final b = lines[best];
        final better = h(l) > h(b) ||
            (h(l) == h(b) && (fps(l) <= 30) && fps(b) > 30) ||
            (h(l) == h(b) && (fps(l) > 30) == (fps(b) > 30) && bw(l) > bw(b));
        if (better) best = i;
      }
      if (best == null || best + 1 >= lines.length) return null;
      final out = <String>[];
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.startsWith('#EXT-X-STREAM-INF')) {
          if (i == best) out..add(_abs(masterUrl, l))..add(_absUri(masterUrl, lines[i + 1]));
          i++;
          continue;
        }
        out.add(_abs(masterUrl, l));
      }
      final id = '${++_n}.m3u8';
      _lists[id] = out.join('\n');
      if (_lists.length > 20) _lists.remove(_lists.keys.first);
      final port = await _port();
      return ('http://127.0.0.1:$port/$id', h(lines[best]));
    } catch (e) {
      _log.info('HLS single: $e');
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

  static bool _avc(Map f) => '${f['mimeType']}'.contains('avc1');
  static bool _vp9(Map f) => '${f['mimeType']}'.contains('vp9') || '${f['mimeType']}'.contains('vp09');

  /// Лучший видеоформат для каждой высоты: до 1080p — AVC (легче для приставок), выше — VP9
  /// (4K у YouTube только в VP9/AV1). При равной высоте 30 к/с важнее 60 к/с, затем битрейт.
  static Map<int, Map> _byHeight(String id) {
    final e = _raw[id];
    if (e == null) return const {};
    final out = <int, Map>{};
    int rank(Map f) {
      final h = _h(f);
      final codec = h <= 1080 ? (_avc(f) ? 0 : 1) : 0;
      return codec * 10 + (_fps(f) > 30 ? 1 : 0);
    }

    for (final f in e.$1.whereType<Map>().where(_ok)) {
      if (!'${f['mimeType']}'.startsWith('video/')) continue;
      final h = _h(f);
      if (h <= 0 || h > 2160) continue;
      if (!(_avc(f) || _vp9(f))) continue;
      if (h > 1080 && !_vp9(f)) continue;
      final cur = out[h];
      if (cur == null || rank(f) < rank(cur) || (rank(f) == rank(cur) && _br(f) > _br(cur))) out[h] = f;
    }
    return out;
  }

  /// Доступные качества ролика (высоты, по убыванию).
  static List<int> heights(String id) => (_byHeight(id).keys.toList()..sort((a, b) => b.compareTo(a)));

  static bool _av1(Map f) => '${f['mimeType']}'.contains('av01');

  /// Все видеоформаты ролика для меню (как «Видеоформат» в SmartTube): выше качество — выше в списке.
  static List<Map> formats(String id) {
    final e = _raw[id];
    if (e == null) return const [];
    final out = e.$1
        .whereType<Map>()
        .where(_ok)
        .where((f) => '${f['mimeType']}'.startsWith('video/') && _h(f) > 0 && _h(f) <= 2160)
        .where((f) => _avc(f) || _vp9(f) || _av1(f))
        .toList()
      ..sort((a, b) {
        final c = _h(b).compareTo(_h(a));
        if (c != 0) return c;
        final fc = _fps(b).compareTo(_fps(a));
        if (fc != 0) return fc;
        return _br(b).compareTo(_br(a));
      });
    return out;
  }

  /// «(4K) 2160p, 25fps, 12.42Mbps, vp9»
  static String label(Map f) {
    final h = _h(f);
    final tag = h >= 2160 ? '(4K) ' : (h >= 1440 ? '(2K) ' : '');
    final codec = _avc(f) ? 'avc' : (_vp9(f) ? 'vp9' : 'av1');
    return '$tag${h}p, ${_fps(f)}fps, ${(_br(f) / 1e6).toStringAsFixed(2)}Mbps, $codec';
  }

  /// (адрес манифеста, высота кадра, адрес видеодорожки для заголовков) или null.
  /// [cap] — потолок качества (по умолчанию 4K: берётся лучшее, что есть у ролика).
  /// [itag] — конкретный формат, выбранный в меню (если есть у ролика).
  static Future<(String, int, String, String)?> build(String id, {int cap = 2160, String? itag}) async {
    final e = _raw[id];
    if (e == null) return null;
    final all = e.$1.whereType<Map>().where(_ok).toList();
    final byH = _byHeight(id);
    final hs = byH.keys.where((h) => h <= cap).toList()..sort((a, b) => b.compareTo(a));
    final audios = all
        .where((f) => '${f['mimeType']}'.startsWith('audio/mp4'))
        .toList()
      ..sort((a, b) => _br(b).compareTo(_br(a)));
    if (audios.isEmpty) return null;
    Map? v = itag == null ? null : formats(id).where((f) => '${f['itag']}' == itag).firstOrNull;
    if (v == null) {
      if (hs.isEmpty) return null;
      v = byH[hs.first]!;
    }
    final a = audios.first;
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
    return ('http://127.0.0.1:$port/$name', _h(v), v['url'] as String, '${v['itag']}');
  }
}
