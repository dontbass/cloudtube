import 'package:cloudtube/cloudtube/yt_fast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('субтитры из ответа player: WebVTT, автоматические, автоперевод на русский', () {
    final p = <String, dynamic>{
      'captions': {
        'playerCaptionsTracklistRenderer': {
          'captionTracks': [
            {
              'baseUrl': 'https://www.youtube.com/api/timedtext?v=x&lang=en&kind=asr',
              'name': {'simpleText': 'English'},
              'languageCode': 'en',
              'kind': 'asr',
              'isTranslatable': true,
            },
            {
              'baseUrl': 'https://www.youtube.com/api/timedtext?v=x&lang=de&fmt=srv3',
              'name': {
                'runs': [
                  {'text': 'German'}
                ]
              },
              'languageCode': 'de',
            },
          ]
        }
      }
    };
    final c = CtYtFast.captions(p)!;
    expect(c.length, 3);
    expect(c[0]['label'], 'English (автоматические)');
    expect(c[0]['url'], endsWith('&fmt=vtt'));
    expect(c[1]['label'], 'German');
    expect(c[1]['url'], contains('fmt=vtt'));
    expect(c[1]['url'], isNot(contains('srv3')));
    expect(c[2]['languageCode'], 'ru');
    expect(c[2]['url'], endsWith('&fmt=vtt&tlang=ru'));
  });

  test('нет субтитров — null', () {
    expect(CtYtFast.captions(null), isNull);
    expect(CtYtFast.captions(<String, dynamic>{}), isNull);
  });
}
