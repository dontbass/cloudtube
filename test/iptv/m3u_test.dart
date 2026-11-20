import 'package:cloudtube/iptv/m3u.dart';
import 'package:flutter_test/flutter_test.dart';

const edem = '''#EXTM3U
#EXTINF:0 tvg-rec="0",Первый канал UHD
#EXTGRP:Общие
http://h/iptv/T/1/index.m3u8
#EXTINF:0 tvg-rec="7",Первый канал FHD
#EXTGRP:Общие
http://h/iptv/T/2/index.m3u8
#EXTINF:0 tvg-rec="7",Первый канал HD
#EXTGRP:Общие
http://h/iptv/T/3/index.m3u8
#EXTINF:0 tvg-rec="0",Первый канал +2
#EXTGRP:Общие
http://h/iptv/T/4/index.m3u8
#EXTINF:0 tvg-rec="3",Матч ТВ HD
#EXTGRP:Спорт
http://h/iptv/T/5/index.m3u8
''';

const std = '''#EXTM3U url-tvg="http://epg/a.xml.gz, http://epg/b.xml" catchup="shift" catchup-days="5"
#EXTINF:-1 tvg-id="ch1" tvg-name="One" tvg-logo="http://l/1.png" group-title="Новости, мир",One News
#EXTVLCOPT:http-user-agent=MyUA
http://s/1.ts|Referer=http://ref
#EXTINF:-1 tvg-chno="42" catchup="flussonic" catchup-days="2",Two
http://s/2.m3u8
''';

void main() {
  test('плейлист с #EXTGRP и tvg-rec: варианты объединены, архив самый глубокий', () {
    final p = parseM3u(edem);
    expect(p.groups, ['Общие', 'Спорт']);
    expect(p.channels.length, 3);
    final first = p.channels.first;
    expect(first.name, 'Первый канал');
    expect(first.streams.map((s) => s.quality), ['UHD', 'FHD', 'HD']);
    expect(first.catchupDays, 7);
    expect(p.channels[1].name, 'Первый канал +2');
    expect(p.channels.map((c) => c.number), [1, 2, 3]);
  });

  test('без объединения — каждый вариант отдельно', () {
    expect(parseM3u(edem, merge: false).channels.length, 5);
  });

  test('стандартные атрибуты, заголовки, url-tvg, catchup по умолчанию', () {
    final p = parseM3u(std);
    expect(p.epgUrls, ['http://epg/a.xml.gz', 'http://epg/b.xml']);
    final a = p.channels[0];
    expect(a.name, 'One News');
    expect(a.group, 'Новости, мир');
    expect(a.tvgId, 'ch1');
    expect(a.logo, 'http://l/1.png');
    expect(a.headers['User-Agent'], 'MyUA');
    expect(a.headers['Referer'], 'http://ref');
    expect(a.streams.first.url, 'http://s/1.ts');
    expect(a.catchup, 'shift');
    expect(a.catchupDays, 5);
    final b = p.channels[1];
    expect(b.number, 42);
    expect(b.catchup, 'flussonic');
    expect(b.catchupDays, 2);
  });

  test('совместимое качество по умолчанию — HD, максимальное — 4K', () {
    final c = parseM3u(edem).channels.first;
    int best(bool max) => c.streams.map((s) => qualityRank(s.quality, preferMax: max)).reduce((a, b) => a < b ? a : b);
    expect(c.streams.firstWhere((s) => qualityRank(s.quality) == best(false)).quality, 'HD');
    expect(c.streams.firstWhere((s) => qualityRank(s.quality, preferMax: true) == best(true)).quality, 'UHD');
  });
}
