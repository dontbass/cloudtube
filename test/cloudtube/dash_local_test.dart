import 'package:cloudtube/cloudtube/hls_local.dart';
import 'package:flutter_test/flutter_test.dart';

/// Выбор качества для ТВ без сервера: какой поток попадёт в свой DASH-манифест.
Map<String, Object> fmt(int itag, int h, String mime, int br, {int fps = 30}) => {
      'itag': itag,
      'height': h,
      'width': h * 16 ~/ 9,
      'fps': fps,
      'bitrate': br,
      'mimeType': mime,
      'url': 'https://example.invalid/v$itag?a=1&b=2',
      'initRange': {'start': '0', 'end': '700'},
      'indexRange': {'start': '701', 'end': '2000'},
    };

const avc = 'video/mp4; codecs="avc1.640028"';
const vp9 = 'video/webm; codecs="vp9"';
const av1 = 'video/mp4; codecs="av01.0.08M.08"';
const aac = 'audio/mp4; codecs="mp4a.40.2"';

void main() {
  final formats = [
    fmt(137, 1080, avc, 4500000),
    fmt(248, 1080, vp9, 2600000),
    fmt(313, 2160, vp9, 12400000),
    fmt(401, 2160, av1, 10300000),
    fmt(299, 1080, avc, 6000000, fps: 60),
    fmt(136, 720, avc, 2200000),
    fmt(140, 0, aac, 130000),
  ];

  setUp(() => CtDashLocal.remember('v1', formats, 600000));

  test('список форматов: выше качество — выше, подпись как в SmartTube', () {
    final list = CtDashLocal.formats('v1');
    expect(list.first['height'], 2160);
    expect(list.last['height'], 720);
    expect(list.any((f) => f['mimeType'] == aac), isFalse, reason: 'звук в меню качества не показываем');
    expect(CtDashLocal.label(formats[2]), '(4K) 2160p, 30fps, 12.40Mbps, vp9');
    expect(CtDashLocal.label(formats[0]), '1080p, 30fps, 4.50Mbps, avc');
  });

  test('по умолчанию — лучшее до 4K (VP9), до 1080p — AVC 30 к/с', () async {
    final best = await CtDashLocal.build('v1');
    expect(best, isNotNull);
    expect(best!.$2, 2160);
    expect(best.$4, '313');

    final capped = await CtDashLocal.build('v1', cap: 1080);
    expect(capped!.$2, 1080);
    expect(capped.$4, '137', reason: 'AVC важнее VP9, 30 к/с важнее 60');
  });

  test('выбранный вручную формат имеет приоритет', () async {
    final r = await CtDashLocal.build('v1', itag: '401');
    expect(r!.$4, '401');
  });

  test('без звуковой дорожки манифест не строится', () async {
    CtDashLocal.remember('v2', formats.where((f) => f['mimeType'] != aac).toList(), 1000);
    expect(await CtDashLocal.build('v2'), isNull);
  });

  test('неизвестный ролик', () async {
    expect(CtDashLocal.formats('нет'), isEmpty);
    expect(await CtDashLocal.build('нет'), isNull);
  });
}
