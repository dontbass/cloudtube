import 'package:cloudtube/iptv/archive.dart';
import 'package:cloudtube/iptv/epg.dart';
import 'package:cloudtube/iptv/m3u.dart';
import 'package:flutter_test/flutter_test.dart';

IptvChannel ch({String catchup = '', String source = '', int days = 7}) => IptvChannel(
    key: 'k', name: 'n', group: '', streams: const [], catchup: catchup, catchupDays: days, catchupSource: source);

void main() {
  const live = 'http://h/iptv/T/19241/index.m3u8';
  test('архив: tvg-rec без типа — utc/lutc (проверено на edem-подобном провайдере)', () {
    expect(iptvArchiveUrl(ch(), live, 1000, 4600, nowSec: 9000), '$live?utc=1000&lutc=9000');
  });
  test('архив: flussonic', () {
    expect(iptvArchiveUrl(ch(catchup: 'flussonic'), 'http://h/ch1/index.m3u8', 1000, 4600),
        'http://h/ch1/index-1000-3600.m3u8');
    expect(iptvArchiveUrl(ch(catchup: 'flussonic'), 'http://h/ch1/mpegts', 1000, 4600), 'http://h/ch1/timeshift_abs-1000.ts');
  });
  test('архив: append и default с подстановками', () {
    expect(iptvArchiveUrl(ch(catchup: 'append', source: '?utc={utc}&lutc={lutc}'), live, 1000, 4600, nowSec: 9000),
        '$live?utc=1000&lutc=9000');
    expect(iptvArchiveUrl(ch(catchup: 'default', source: 'http://a/{start}/{duration}.m3u8'), live, 1000, 4600),
        'http://a/1000/3600.m3u8');
  });
  test('архив: xtream', () {
    final u = iptvArchiveUrl(ch(catchup: 'xc'), 'http://x:8080/live/u/p/123.ts', 1000, 4600)!;
    expect(u.startsWith('http://x:8080/timeshift/u/p/60/'), isTrue);
    expect(u.endsWith('/123.ts'), isTrue);
  });
  test('нет архива — null', () {
    expect(iptvArchiveUrl(ch(days: 0), live, 1, 2), isNull);
  });
  test('время XMLTV с поясом', () {
    expect(epgParseTime('20261120183000 +0300'), DateTime.utc(2026, 11, 20, 15, 30).millisecondsSinceEpoch ~/ 1000);
    expect(epgParseTime('20261120183000'), DateTime.utc(2026, 11, 20, 18, 30).millisecondsSinceEpoch ~/ 1000);
  });
  test('сопоставление названий', () {
    expect(epgNorm('Первый канал HD'), epgNorm('Первый канал'));
    expect(epgNorm('Россия-1 FHD'), epgNorm('Россия 1'));
    expect(epgNorm('НТВ +2'), isNot(epgNorm('НТВ')));
  });
}
