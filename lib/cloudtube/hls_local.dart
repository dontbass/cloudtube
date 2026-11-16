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
      final body = _lists[req.uri.pathSegments.isNotEmpty ? req.uri.pathSegments.last : ''];
      if (body == null) {
        req.response.statusCode = 404;
      } else {
        req.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
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
