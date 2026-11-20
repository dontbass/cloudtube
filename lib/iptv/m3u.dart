/// IPTV: разбор плейлистов M3U/M3U8 и модель каналов.
///
/// Поддерживается всё, что встречается у провайдеров:
/// - группы: group-title="…" и строка #EXTGRP:… (как у castelloso/edem-подобных);
/// - tvg-id, tvg-name, tvg-logo, tvg-chno, tvg-shift;
/// - архив: catchup / catchup-type, catchup-days, catchup-source, tvg-rec (дни), timeshift;
/// - заголовки #EXTVLCOPT:http-user-agent / http-referrer и атрибуты user-agent=…;
/// - url-tvg / x-tvg-url в заголовке #EXTM3U (адрес телепрограммы).
library;

class IptvStream {
  /// Вариант канала: «HD», «FHD», «UHD», «orig»… (пусто — без пометки).
  final String quality;
  final String url;
  final String name;

  const IptvStream(this.quality, this.url, this.name);

  Map<String, Object?> toJson() => {'q': quality, 'u': url, 'n': name};
  static IptvStream fromJson(Map m) => IptvStream('${m['q'] ?? ''}', '${m['u']}', '${m['n'] ?? ''}');
}

/// Канал: один или несколько вариантов качества одного и того же канала.
class IptvChannel {
  /// Стабильный ключ (группа + название без пометки качества) — для избранного и «последнего канала».
  final String key;
  final String name;
  final String group;
  final String logo;
  final String tvgId;
  final String tvgName;
  final int number;
  final List<IptvStream> streams;

  /// Архив: тип (append / shift / flussonic / default / …), глубина в днях, шаблон адреса.
  final String catchup;
  final int catchupDays;
  final String catchupSource;

  /// Заголовки потока (User-Agent, Referer) из плейлиста.
  final Map<String, String> headers;

  const IptvChannel({
    required this.key,
    required this.name,
    required this.group,
    required this.streams,
    this.logo = '',
    this.tvgId = '',
    this.tvgName = '',
    this.number = 0,
    this.catchup = '',
    this.catchupDays = 0,
    this.catchupSource = '',
    this.headers = const {},
  });

  bool get hasArchive => catchupDays > 0;

  Map<String, Object?> toJson() => {
        'k': key,
        'n': name,
        'g': group,
        if (logo.isNotEmpty) 'l': logo,
        if (tvgId.isNotEmpty) 'i': tvgId,
        if (tvgName.isNotEmpty) 't': tvgName,
        'no': number,
        's': [for (final s in streams) s.toJson()],
        if (catchup.isNotEmpty) 'c': catchup,
        if (catchupDays > 0) 'cd': catchupDays,
        if (catchupSource.isNotEmpty) 'cs': catchupSource,
        if (headers.isNotEmpty) 'h': headers,
      };

  static IptvChannel fromJson(Map m) => IptvChannel(
        key: '${m['k']}',
        name: '${m['n']}',
        group: '${m['g'] ?? ''}',
        logo: '${m['l'] ?? ''}',
        tvgId: '${m['i'] ?? ''}',
        tvgName: '${m['t'] ?? ''}',
        number: (m['no'] as num?)?.toInt() ?? 0,
        streams: [for (final s in (m['s'] as List? ?? const [])) IptvStream.fromJson(s as Map)],
        catchup: '${m['c'] ?? ''}',
        catchupDays: (m['cd'] as num?)?.toInt() ?? 0,
        catchupSource: '${m['cs'] ?? ''}',
        headers: {for (final e in ((m['h'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
      );
}

class IptvParsed {
  final List<IptvChannel> channels;
  final List<String> groups;

  /// Адреса телепрограммы из заголовка плейлиста.
  final List<String> epgUrls;

  /// Общий архив из заголовка (catchup=…, catchup-days=…), если у каналов своего нет.
  const IptvParsed(this.channels, this.groups, this.epgUrls);
}

final _attrRe = RegExp(r'([A-Za-z0-9_-]+)="([^"]*)"');

/// Пометки качества в конце названия: «Первый канал FHD» → («Первый канал», «FHD»).
final _qualityRe = RegExp(r'\s+(UHD|4K|8K|FHD|QHD|HD|SD|HQ|LQ|orig|original|50fps|60fps)$', caseSensitive: false);

(String, String) splitQuality(String name) {
  var base = name.trim();
  final tags = <String>[];
  for (var i = 0; i < 3; i++) {
    final m = _qualityRe.firstMatch(base);
    if (m == null) break;
    tags.insert(0, m.group(1)!);
    base = base.substring(0, m.start).trim();
  }
  return (base.isEmpty ? name.trim() : base, tags.join(' '));
}

/// Порядок качества для автовыбора на Android-ТВ: сначала варианты со звуком AAC
/// (у провайдеров это обычно HD/SD), затем FHD/«orig» (часто MP2), затем 4K (тяжело для приставок).
int qualityRank(String q, {bool preferMax = false}) {
  final l = q.toLowerCase();
  int r;
  if (l.contains('uhd') || l.contains('4k') || l.contains('8k')) {
    r = preferMax ? 0 : 5;
  } else if (l.contains('fhd') || l.contains('qhd')) {
    r = preferMax ? 1 : 2;
  } else if (l.contains('orig')) {
    r = preferMax ? 2 : 3;
  } else if (l == 'hd' || l.startsWith('hd') || l.endsWith(' hd')) {
    r = preferMax ? 3 : 0;
  } else if (l.isEmpty) {
    r = preferMax ? 4 : 1;
  } else {
    r = 4;
  }
  return r;
}

/// Разобрать текст плейлиста. [merge] — объединять варианты качества одного канала в одну строку.
IptvParsed parseM3u(String text, {bool merge = true}) {
  final lines = text.replaceAll('\r', '').split('\n');
  final epg = <String>[];
  var defCatchup = '', defCatchupSource = '';
  var defDays = 0;
  final out = <IptvChannel>[];
  final byKey = <String, int>{};
  final groups = <String>[];
  final seenGroups = <String>{};

  String? extinf;
  String? grp;
  final vlc = <String, String>{};

  for (final raw in lines) {
    final l = raw.trim();
    if (l.isEmpty) continue;
    if (l.startsWith('#EXTM3U')) {
      for (final m in _attrRe.allMatches(l)) {
        final k = m.group(1)!.toLowerCase(), v = m.group(2)!;
        if (k == 'url-tvg' || k == 'x-tvg-url') {
          epg.addAll(v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
        } else if (k == 'catchup' || k == 'catchup-type') {
          defCatchup = v;
        } else if (k == 'catchup-source') {
          defCatchupSource = v;
        } else if (k == 'catchup-days' || k == 'tvg-rec') {
          defDays = int.tryParse(v) ?? defDays;
        }
      }
      continue;
    }
    if (l.startsWith('#EXTINF')) {
      extinf = l;
      grp = null;
      vlc.clear();
      continue;
    }
    if (l.startsWith('#EXTGRP:')) {
      grp = l.substring(8).trim();
      continue;
    }
    if (l.startsWith('#EXTVLCOPT:')) {
      final kv = l.substring(11);
      final i = kv.indexOf('=');
      if (i > 0) {
        final k = kv.substring(0, i).trim().toLowerCase();
        final v = kv.substring(i + 1).trim();
        if (k == 'http-user-agent') vlc['User-Agent'] = v;
        if (k == 'http-referrer' || k == 'http-referer') vlc['Referer'] = v;
      }
      continue;
    }
    if (l.startsWith('#')) continue;
    // адрес потока
    if (extinf == null) continue;
    final attrs = <String, String>{for (final m in _attrRe.allMatches(extinf)) m.group(1)!.toLowerCase(): m.group(2)!};
    final comma = _titleComma(extinf);
    final title = comma < 0 ? (attrs['tvg-name'] ?? '') : extinf.substring(comma + 1).trim();
    if (title.isEmpty) {
      extinf = null;
      continue;
    }
    final group = (grp ?? attrs['group-title'] ?? '').trim();
    final headers = <String, String>{...vlc};
    final ua = attrs['user-agent'] ?? attrs['http-user-agent'];
    if (ua != null && ua.isNotEmpty) headers['User-Agent'] = ua;
    final ref = attrs['referer'] ?? attrs['http-referrer'];
    if (ref != null && ref.isNotEmpty) headers['Referer'] = ref;
    // адрес вида «url|User-Agent=…» (Kodi)
    var url = l;
    final pipe = url.indexOf('|');
    if (pipe > 0) {
      for (final kv in url.substring(pipe + 1).split('&')) {
        final i = kv.indexOf('=');
        if (i > 0) headers[Uri.decodeComponent(kv.substring(0, i))] = Uri.decodeComponent(kv.substring(i + 1));
      }
      url = url.substring(0, pipe);
    }
    final days = int.tryParse(attrs['catchup-days'] ?? attrs['tvg-rec'] ?? attrs['timeshift'] ?? '') ?? defDays;
    final catchup = attrs['catchup'] ?? attrs['catchup-type'] ?? defCatchup;
    final source = attrs['catchup-source'] ?? defCatchupSource;
    final (base, q) = merge ? splitQuality(title) : (title, '');
    final key = '${group.toLowerCase()}|${base.toLowerCase()}';
    final stream = IptvStream(q, url, title);
    final existing = byKey[key];
    if (merge && existing != null) {
      final c = out[existing];
      out[existing] = IptvChannel(
        key: c.key,
        name: c.name,
        group: c.group,
        streams: [...c.streams, stream],
        logo: c.logo.isNotEmpty ? c.logo : (attrs['tvg-logo'] ?? ''),
        tvgId: c.tvgId.isNotEmpty ? c.tvgId : (attrs['tvg-id'] ?? ''),
        tvgName: c.tvgName.isNotEmpty ? c.tvgName : (attrs['tvg-name'] ?? ''),
        number: c.number,
        // архив — самый глубокий из вариантов
        catchup: c.catchup.isNotEmpty ? c.catchup : catchup,
        catchupDays: days > c.catchupDays ? days : c.catchupDays,
        catchupSource: c.catchupSource.isNotEmpty ? c.catchupSource : source,
        headers: c.headers.isNotEmpty ? c.headers : headers,
      );
    } else {
      if (group.isNotEmpty && seenGroups.add(group)) groups.add(group);
      byKey[key] = out.length;
      out.add(IptvChannel(
        key: key,
        name: base,
        group: group,
        streams: [stream],
        logo: attrs['tvg-logo'] ?? attrs['logo'] ?? '',
        tvgId: attrs['tvg-id'] ?? '',
        tvgName: attrs['tvg-name'] ?? '',
        number: int.tryParse(attrs['tvg-chno'] ?? '') ?? 0,
        catchup: catchup,
        catchupDays: days,
        catchupSource: source,
        headers: headers,
      ));
    }
    extinf = null;
    grp = null;
  }
  // нумерация: из плейлиста (tvg-chno), иначе по порядку
  var i = 0;
  final numbered = [
    for (final c in out)
      IptvChannel(
        key: c.key,
        name: c.name,
        group: c.group,
        streams: c.streams,
        logo: c.logo,
        tvgId: c.tvgId,
        tvgName: c.tvgName,
        number: c.number > 0 ? c.number : ++i,
        catchup: c.catchup,
        catchupDays: c.catchupDays,
        catchupSource: c.catchupSource,
        headers: c.headers,
      )
  ];
  return IptvParsed(numbered, groups, epg);
}

/// Запятая перед названием канала: первая вне кавычек (в атрибутах бывают запятые).
int _titleComma(String l) {
  var q = false;
  for (var i = 0; i < l.length; i++) {
    final c = l[i];
    if (c == '"') q = !q;
    if (c == ',' && !q) return i;
  }
  return -1;
}
