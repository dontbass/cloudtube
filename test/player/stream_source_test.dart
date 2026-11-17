import 'package:clipious/cloudtube/hls_local.dart';
import 'package:clipious/player/core/stream_source.dart';
import 'package:clipious/videos/models/format_stream.dart';
import 'package:flutter_test/flutter_test.dart';

FormatStream fs(String label, String url) =>
    FormatStream(url, '18', 'video/mp4', 'medium', 'mp4', 'h264', label, label, '');

CtStreamRequest req({
  String? hls,
  String? dash = 'https://srv/api/manifest/dash/id/v1',
  List<FormatStream>? streams,
  bool proxy = false,
  bool serverDash = false,
  bool tvDirect = false,
  bool noOwnDash = false,
  String id = 'v1',
}) =>
    CtStreamRequest(
      videoId: id,
      hlsUrl: hls,
      dashUrl: dash,
      formatStreams: streams ?? [fs('360p', 'https://rr1.googlevideo.com/a'), fs('720p', 'https://rr2.googlevideo.com/b')],
      serverUrl: 'https://srv',
      serverHeaders: (u) => u.startsWith('https://srv') ? {'Authorization': 'Basic x'} : null,
      useProxy: proxy,
      useServerDash: serverDash,
      tvDirect: tvDirect,
      noOwnDash: noOwnDash,
    );

void main() {
  test('обычный поток: последнее (лучшее) разрешение, все разрешения в меню', () async {
    final c = await ctPickStream(req());
    expect(c.kind, CtStreamKind.progressive);
    expect(c.url, 'https://rr2.googlevideo.com/b');
    expect(c.progressiveResolution, '720p');
    expect(c.resolutions.keys, ['360p', '720p']);
    expect(c.headers.containsKey('Authorization'), isFalse, reason: 'заголовки сервера — только своему серверу');
  });

  test('прокси сервера: адрес Google заменяется адресом сервера, заголовки сервера добавляются', () async {
    final c = await ctPickStream(req(proxy: true));
    expect(c.url, 'https://srv/b');
    expect(c.headers['Authorization'], 'Basic x');
  });

  test('DASH сервера', () async {
    final c = await ctPickStream(req(serverDash: true, proxy: true));
    expect(c.kind, CtStreamKind.serverDash);
    expect(c.url, 'https://srv/api/manifest/dash/id/v1?local=true');
  });

  test('HLS как есть', () async {
    final c = await ctPickStream(req(hls: 'https://manifest.googlevideo.com/m.m3u8'));
    expect(c.kind, CtStreamKind.hls);
    expect(c.fixedQuality, isFalse);
  });

  test('ТВ без сервера: свой DASH с одним качеством', () async {
    CtDashLocal.remember('t1', [
      {
        'itag': 137, 'height': 1080, 'width': 1920, 'fps': 30, 'bitrate': 4000000,
        'mimeType': 'video/mp4; codecs="avc1.640028"', 'url': 'https://rr.googlevideo.com/v',
        'initRange': {'start': '0', 'end': '700'}, 'indexRange': {'start': '701', 'end': '2000'},
      },
      {
        'itag': 140, 'height': 0, 'bitrate': 130000, 'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
        'url': 'https://rr.googlevideo.com/a',
        'initRange': {'start': '0', 'end': '600'}, 'indexRange': {'start': '601', 'end': '900'},
      },
    ], 60000);
    final c = await ctPickStream(req(id: 't1', tvDirect: true, hls: 'https://manifest.googlevideo.com/m.m3u8'));
    expect(c.kind, CtStreamKind.ownDash);
    expect(c.height, 1080);
    expect(c.itag, '137');
    expect(c.fixedQuality, isTrue);
    expect(c.url, startsWith('http://127.0.0.1:'));
  });

  test('ТВ без сервера, свой DASH уже давал сбой — не используется', () async {
    final c = await ctPickStream(req(id: 't1', tvDirect: true, noOwnDash: true));
    expect(c.kind, isNot(CtStreamKind.ownDash));
  });
}
