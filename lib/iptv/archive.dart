import 'm3u.dart';

/// Адрес архива передачи по типу catchup из плейлиста.
///
/// - shift (и «tvg-rec» без типа, как у edem/castelloso): `…?utc=начало&lutc=сейчас`;
/// - append: к адресу канала дописывается catchup-source (с подстановками);
/// - default: catchup-source — полный адрес с подстановками;
/// - flussonic / fs: `index-начало-длительность.m3u8` (или `timeshift_abs-начало.ts`);
/// - xc (Xtream Codes): `/timeshift/логин/пароль/минуты/ГГГГ-ММ-ДД:ЧЧ-ММ/id.ts`.
/// Подстановки: {utc} {start} {utcend} {end} {lutc} {now} {timestamp} {duration} {offset}
/// и ${…}-варианты, {Y} {m} {d} {H} {M} {S}, {utc:Y-m-d…}.
String? iptvArchiveUrl(IptvChannel c, String liveUrl, int start, int stop, {int? nowSec}) {
  if (!c.hasArchive) return null;
  final now = nowSec ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final dur = (stop - start).clamp(60, 24 * 3600);
  final type = c.catchup.toLowerCase();
  String sub(String t) => _subst(t, start, stop, now, dur);
  switch (type) {
    case 'default':
      return c.catchupSource.isNotEmpty ? sub(c.catchupSource) : _shift(liveUrl, start, now);
    case 'append':
      return c.catchupSource.isNotEmpty ? liveUrl + sub(c.catchupSource) : _shift(liveUrl, start, now);
    case 'flussonic':
    case 'flussonic-hls':
    case 'flussonic-ts':
    case 'fs':
      return _flussonic(liveUrl, start, dur, ts: type.endsWith('ts'));
    case 'xc':
      return _xc(liveUrl, start, dur) ?? _shift(liveUrl, start, now);
    default: // shift, timeshift, tvg-rec без типа
      if (c.catchupSource.isNotEmpty && c.catchupSource.contains('{')) {
        final s = sub(c.catchupSource);
        return s.startsWith('http') ? s : liveUrl + s;
      }
      return _shift(liveUrl, start, now);
  }
}

String _shift(String url, int start, int now) => '$url${url.contains('?') ? '&' : '?'}utc=$start&lutc=$now';

String _flussonic(String url, int start, int dur, {bool ts = false}) {
  final u = Uri.parse(url);
  final segs = [...u.pathSegments];
  if (segs.isEmpty) return url;
  final last = segs.last;
  if (ts || last.endsWith('.ts') || last == 'mpegts') {
    segs[segs.length - 1] = 'timeshift_abs-$start.ts';
  } else {
    final name = last.contains('.') ? last.substring(0, last.lastIndexOf('.')) : 'index';
    final base = name == 'video' || name == 'mono' || name == 'index' ? name : 'index';
    segs[segs.length - 1] = '$base-$start-$dur.m3u8';
  }
  return u.replace(pathSegments: segs).toString();
}

String? _xc(String url, int start, int dur) {
  final m = RegExp(r'^(https?://[^/]+)/(?:live/)?([^/]+)/([^/]+)/(\d+)(\.\w+)?$').firstMatch(url);
  if (m == null) return null;
  final t = DateTime.fromMillisecondsSinceEpoch(start * 1000);
  String two(int n) => n.toString().padLeft(2, '0');
  final ts = '${t.year}-${two(t.month)}-${two(t.day)}:${two(t.hour)}-${two(t.minute)}';
  return '${m.group(1)}/timeshift/${m.group(2)}/${m.group(3)}/${(dur / 60).ceil()}/$ts/${m.group(4)}${m.group(5) ?? '.ts'}';
}

String _subst(String t, int start, int stop, int now, int dur) {
  final st = DateTime.fromMillisecondsSinceEpoch(start * 1000).toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final map = {
    'utc': '$start',
    'start': '$start',
    'timestamp': '$start',
    'utcend': '$stop',
    'end': '$stop',
    'lutc': '$now',
    'now': '$now',
    'duration': '$dur',
    'offset': '${now - start}',
    'Y': '${st.year}',
    'm': two(st.month),
    'd': two(st.day),
    'H': two(st.hour),
    'M': two(st.minute),
    'S': two(st.second),
  };
  var r = t.replaceAllMapped(RegExp(r'\$?\{(utc|start|end|utcend|lutc):([^}]*)\}'), (m) {
    final sec = switch (m.group(1)) { 'end' || 'utcend' => stop, 'lutc' => now, _ => start };
    final d = DateTime.fromMillisecondsSinceEpoch(sec * 1000).toUtc();
    return m.group(2)!
        .replaceAll('Y', '${d.year}')
        .replaceAll('m', two(d.month))
        .replaceAll('d', two(d.day))
        .replaceAll('H', two(d.hour))
        .replaceAll('M', two(d.minute))
        .replaceAll('S', two(d.second));
  });
  r = r.replaceAllMapped(RegExp(r'\$?\{([A-Za-z]+)\}'), (m) => map[m.group(1)] ?? m.group(0)!);
  return r;
}
