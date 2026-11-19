import 'package:cloudtube/cloudtube/audio_tracks.dart';
import 'package:flutter_test/flutter_test.dart';

const master = '''#EXTM3U
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:URI="https://m/a/en-dub.m3u8",TYPE=AUDIO,GROUP-ID="234",LANGUAGE="en",NAME="English (auto-dubbed)",DEFAULT=YES,AUTOSELECT=YES,YT-EXT-AUDIO-CONTENT-ID="en.3",YT-EXT-XTAGS="acont=dubbed-auto:lang=en"
#EXT-X-MEDIA:URI="https://m/a/es-orig.m3u8",TYPE=AUDIO,GROUP-ID="234",LANGUAGE="es",NAME="Spanish original",DEFAULT=NO,AUTOSELECT=NO,YT-EXT-AUDIO-CONTENT-ID="es.4",YT-EXT-XTAGS="acont=original:lang=es"
#EXT-X-STREAM-INF:BANDWIDTH=1000000,CODECS="avc1.4d401f,mp4a.40.2",RESOLUTION=1280x720,AUDIO="234"
https://m/v/720.m3u8
''';

void main() {
  test('HLS: по умолчанию оригинал, не автодубляж', () {
    final t = CtAudio.fromHls('vid1', master);
    expect(t.length, 2);
    expect(CtAudio.pick('vid1', t)!.id, 'es.4');
    final f = CtAudio.filterHls('vid1', master);
    expect(f.contains('es-orig.m3u8'), isTrue);
    expect(f.contains('en-dub.m3u8'), isFalse);
    expect(f.contains('https://m/v/720.m3u8'), isTrue);
    expect(RegExp('es-orig.*DEFAULT=YES').hasMatch(f), isTrue);
  });

  test('DASH: только звук оригинальной дорожки', () {
    final formats = [
      {'itag': 140, 'mimeType': 'audio/mp4; codecs="mp4a.40.2"', 'audioTrack': {'id': 'en.3', 'displayName': 'English (dubbed-auto)', 'audioIsDefault': true}},
      {'itag': 140, 'mimeType': 'audio/mp4; codecs="mp4a.40.2"', 'audioTrack': {'id': 'es.4', 'displayName': 'Spanish original', 'audioIsDefault': false}},
    ];
    final kept = CtAudio.filterFormats('vid2', formats);
    expect(kept.length, 1);
    expect((kept.first['audioTrack'] as Map)['id'], 'es.4');
  });

  test('одна дорожка — без изменений', () {
    const one = '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=640x360\nhttps://m/v/360.m3u8\n';
    expect(CtAudio.filterHls('vid3', one), one);
    expect(CtAudio.tracks('vid3'), isEmpty);
  });
}
