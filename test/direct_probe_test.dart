// Диагностика режима «без сервера»: реальные запросы к YouTube, замер каждого шага.
// Запускается только вручную/в CI: CT_PROBE=1 flutter test test/direct_probe_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:clipious/cloudtube/direct.dart';
import 'package:clipious/videos/models/video.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

const _vid = 'jNQXAC9IVRw'; // «Me at the zoo» — всегда доступно
const _vid2 = 'dQw4w9WgXcQ';

Future<void> _t(String name, Future<Object?> Function() f) async {
  final sw = Stopwatch()..start();
  try {
    final r = await f();
    stdout.writeln('PROBE OK   ${sw.elapsedMilliseconds.toString().padLeft(6)} ms  $name  ${r ?? ''}');
  } catch (e) {
    final s = '$e'.replaceAll('\n', ' ');
    stdout.writeln('PROBE FAIL ${sw.elapsedMilliseconds.toString().padLeft(6)} ms  $name  ${s.length > 300 ? s.substring(0, 300) : s}');
  }
}

String _m(yt.StreamManifest m) {
  final hls = m.hls.length;
  final c = m.streams.isEmpty ? '-' : RegExp(r'[?&]c=([A-Z_0-9]+)').firstMatch(m.streams.first.url.toString())?.group(1);
  return 'muxed=${m.muxed.length} video=${m.videoOnly.length} audio=${m.audioOnly.length} hls=$hls c=$c';
}

void main() {
  final enabled = Platform.environment['CT_PROBE'] == '1';
  test('direct probe', () async {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((r) => stdout.writeln('LOG ${r.loggerName} ${r.level.name}: ${r.message}'.split('\n').first));
    ctDirectActive = true;
    final client = CtHttpClient(http.Client());
    Future<Object?> api(String path, {bool parse = true}) async {
      final r = await client.get(Uri.parse('$kCtDirectUrl$path'));
      if (r.statusCode != 200) throw 'HTTP ${r.statusCode}: ${r.body}';
      final j = jsonDecode(r.body);
      if (!parse) return 'ok';
      if (j is List) {
        var bad = 0;
        String? err;
        for (final e in j) {
          if (e is Map && e['type'] == 'video') {
            try {
              Video.fromJson(Map<String, dynamic>.from(e));
            } catch (x) {
              bad++;
              err ??= '$x  ← ${jsonEncode(e).substring(0, 200)}';
            }
          }
        }
        return 'items=${j.length} parseErrors=$bad ${err ?? ''}';
      }
      final v = Video.fromJson(Map<String, dynamic>.from(j as Map));
      return 'hls=${j['hlsUrl'] != null} fmt=${(j['formatStreams'] as List?)?.length} adaptive=${(j['adaptiveFormats'] as List?)?.length} rec=${v.recommendedVideos.length}';
    }

    stdout.writeln('==== API адаптера (как видит приложение) ====');
    for (final s in ['home', 'news', 'live', 'music', 'sport']) {
      await _t('search ct:$s', () => api('/api/v1/search?q=ct:$s&page=1'));
    }
    await _t('search ct:news (двойное кодирование)', () => api('/api/v1/search?q=ct%253Anews&page=1'));
    await _t('videos/$_vid (холодный)', () => api('/api/v1/videos/$_vid'));
    await _t('videos/$_vid (кэш)', () => api('/api/v1/videos/$_vid'));
    await _t('videos/$_vid2', () => api('/api/v1/videos/$_vid2'));

    stdout.writeln('==== HLS-мастер: можно ли проиграть ====');
    await _t('hls master → variant → segment', () async {
      final r = await client.get(Uri.parse('$kCtDirectUrl/api/v1/videos/$_vid2'));
      final master = (jsonDecode(r.body) as Map)['hlsUrl'] as String;
      final h = ctDirectStreamHeaders(master);
      final m = await http.get(Uri.parse(master), headers: h);
      final lines = m.body.split('\n');
      final variant = lines.lastWhere((l) => l.startsWith('http'));
      final audio = RegExp(r'URI="([^"]+)"').firstMatch(m.body)?.group(1);
      final vp = await http.get(Uri.parse(variant), headers: ctDirectStreamHeaders(variant));
      final seg = vp.body.split('\n').firstWhere((l) => l.startsWith('http'));
      final sr = await http.get(Uri.parse(seg), headers: ctDirectStreamHeaders(seg));
      return 'master=${m.statusCode} (${lines.where((l) => l.startsWith('#EXT-X-STREAM-INF')).length} вариантов, '
          'звук отдельно=${audio != null}) variant=${vp.statusCode} segment=${sr.statusCode} ${sr.bodyBytes.length} байт '
          'UA=${h['User-Agent']?.substring(0, 20)}';
    });
        stdout.writeln('==== Отдельные шаги youtube_explode ====');
    final y = yt.YoutubeExplode();
    await _t('videos.get (страница просмотра)', () async => (await y.videos.get(_vid2)).title);
    final clients = {
      'ios': yt.YoutubeApiClient.ios,
      'safari': yt.YoutubeApiClient.safari,
      'androidSdkless': yt.YoutubeApiClient.androidSdkless,
      'androidVr': yt.YoutubeApiClient.androidVr,
      'tv': yt.YoutubeApiClient.tv,
      'mweb': yt.YoutubeApiClient.mweb,
    };
    for (final e in clients.entries) {
      await _t('manifest ${e.key} watchPage=true', () async => _m(await y.videos.streams.getManifest(_vid2, ytClients: [e.value])));
      await _t('manifest ${e.key} watchPage=false',
          () async => _m(await y.videos.streams.getManifest(_vid2, ytClients: [e.value], requireWatchPage: false)));
    }
    await _t('manifest default', () async => _m(await y.videos.streams.getManifest(_vid2)));
    await _t('related', () async => (await y.videos.getRelatedVideos(await y.videos.get(_vid2)))?.length);
    await _t('search новости lastWeek', () async {
      final r = await y.search.search('новости', filter: yt.UploadDateFilter.lastWeek);
      return 'n=${r.length} live=${r.where((v) => v.isLive).length}';
    });
    await _t('search прямой эфир live', () async {
      final r = await y.search.search('прямой эфир', filter: yt.FeatureFilters.live);
      return 'n=${r.length}';
    });
    y.close();
  }, skip: !enabled, timeout: const Timeout(Duration(minutes: 10)));
}
