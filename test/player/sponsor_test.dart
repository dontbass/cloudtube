import 'package:cloudtube/player/core/sponsor.dart';
import 'package:cloudtube/videos/models/sponsor_segment_types.dart';
import 'package:flutter_test/flutter_test.dart';

const total = Duration(minutes: 10);
Duration s(num sec) => Duration(milliseconds: (sec * 1000).round());

void main() {
  group('пропуск SponsorBlock', () {
    late CtSponsorSkipper k;
    setUp(() {
      k = CtSponsorSkipper()
        ..setSegments(const [
          CtSponsorSeg(60000, 90000, SponsorSegmentType.sponsor),
          CtSponsorSeg(10000, 20000, SponsorSegmentType.intro),
        ]);
    });

    test('вне фрагментов — ничего', () {
      expect(k.check(s(5), total), isNull);
      expect(k.check(s(30), total), isNull);
      expect(k.check(s(95), total), isNull);
    });

    test('внутри фрагмента — на конец фрагмента, чуть дальше', () {
      final r = k.check(s(61), total)!;
      expect(r.seg.type, SponsorSegmentType.sponsor);
      expect(r.to, s(90.25));
      expect(r.announce, isTrue);
    });

    test('сообщение — один раз на фрагмент', () {
      final t = DateTime(2026);
      expect(k.check(s(11), total, now: t)!.announce, isTrue);
      expect(k.check(s(11.2), total, now: t.add(s(1)))!.announce, isFalse);
      expect(k.check(s(61), total, now: t.add(s(2)))!.announce, isTrue);
    });

    test('у самого конца фрагмента не дёргаем', () {
      expect(k.check(s(89.8), total), isNull);
    });

    test('в последние 5 секунд ролика не пропускаем', () {
      k.setSegments(const [CtSponsorSeg(590000, 600000, SponsorSegmentType.outro)]);
      expect(k.check(s(597), total), isNull);
    });

    test('фрагмент до конца ролика — встаём на последнюю секунду', () {
      k.setSegments(const [CtSponsorSeg(500000, 600000, SponsorSegmentType.outro)]);
      expect(k.check(s(510), total)!.to, s(599));
    });

    test('пустой список — ничего', () {
      k.clear();
      expect(k.check(s(61), total), isNull);
    });
  });

  group('разбор ответа SponsorBlock', () {
    test('music_offtopic понимаем, незнакомое пропускаем, не роняя остальное', () {
      final segs = CtSponsorSkipper.parse([
        {'category': 'sponsor', 'actionType': 'skip', 'segment': [1.5, 3]},
        {'category': 'music_offtopic', 'actionType': 'skip', 'segment': [10, 20]},
        {'category': 'exclusive_access', 'actionType': 'full', 'segment': [0, 0]},
        {'category': 'poi_highlight', 'actionType': 'poi', 'segment': [5, 5]},
        {'category': 'chapter', 'actionType': 'chapter', 'segment': [0, 100]},
        {'category': 'filler', 'actionType': 'mute', 'segment': [30, 40]},
        {'category': 'selfpromo', 'segment': [50, 'x']},
        'мусор',
      ]);
      expect(segs.map((e) => e.type), [SponsorSegmentType.sponsor, SponsorSegmentType.musicOffTopic]);
      expect(segs.first.startMs, 1500);
      expect(segs.first.endMs, 3000);
    });
  });
}
