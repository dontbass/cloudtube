import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import 'm3u.dart';
import 'store.dart';

final _log = Logger('IptvEpg');

/// Передача телепрограммы.
class EpgProg {
  final int start; // секунды UTC
  final int stop;
  final String title;
  final String desc;

  const EpgProg(this.start, this.stop, this.title, [this.desc = '']);

  bool isNow(int now) => start <= now && now < stop;
  double progress(int now) => stop <= start ? 0 : ((now - start) / (stop - start)).clamp(0.0, 1.0);
  DateTime get startTime => DateTime.fromMillisecondsSinceEpoch(start * 1000);
  DateTime get stopTime => DateTime.fromMillisecondsSinceEpoch(stop * 1000);

  List<Object> toJson() => [start, stop, title, if (desc.isNotEmpty) desc];
  static EpgProg fromJson(List l) => EpgProg((l[0] as num).toInt(), (l[1] as num).toInt(), '${l[2]}', l.length > 3 ? '${l[3]}' : '');
}

String _two(int n) => n.toString().padLeft(2, '0');
String epgHm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// Телепрограмма IPTV: XMLTV (в т. ч. .gz на десятки мегабайт) разбирается потоком в отдельном
/// потоке (isolate) раз в 12 ч; остаются только каналы плейлиста. На диске:
/// - epg_<плейлист>.json — «сейчас и далее» на сутки (для списка и плашки, грузится сразу);
/// - epg_<плейлист>/<канал>.json — вся программа канала (архив + вперёд), читается по запросу.
class IptvEpg {
  IptvEpg._();
  static final IptvEpg I = IptvEpg._();

  /// Канал → передачи на ближайшие сутки.
  final now = ValueNotifier<Map<String, List<EpgProg>>>(const {});

  /// Логотипы из телепрограммы (если в плейлисте их нет).
  final logos = ValueNotifier<Map<String, String>>(const {});

  /// Идёт загрузка/разбор (для подписи «Обновляю телепрограмму…»).
  final busy = ValueNotifier<String?>(null);

  String? _loadedFor;
  bool _building = false;

  static int get _nowSec => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Future<Directory> _dir() async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}/iptv');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Источники для плейлиста: свой адрес → url-tvg плейлиста → общий по умолчанию.
  List<String> sources(IptvPlaylist p, IptvParsed parsed) {
    if (p.epgUrl.trim().isNotEmpty) return p.epgUrl.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parsed.epgUrls.isNotEmpty) return parsed.epgUrls;
    final def = IptvStore.I.settings.value.defaultEpg.trim();
    return def.isEmpty ? const [] : [def];
  }

  /// Загрузить готовую программу с диска; если устарела (или её нет) — пересобрать в фоне.
  Future<void> ensure(IptvPlaylist p, IptvParsed parsed, {bool force = false}) async {
    final f = File('${(await _dir()).path}/epg_${p.id}.json');
    var age = const Duration(days: 999);
    if (await f.exists()) {
      age = DateTime.now().difference(await f.lastModified());
      if (_loadedFor != p.id || force) await _loadShort(f, p.id);
    } else if (_loadedFor != p.id) {
      now.value = const {};
      logos.value = const {};
    }
    if ((force || age > const Duration(hours: 12)) && !_building) unawaited(_build(p, parsed));
  }

  Future<void> _loadShort(File f, String id) async {
    try {
      final m = await compute(_decodeShort, await f.readAsString());
      now.value = m.$1;
      logos.value = m.$2;
      _loadedFor = id;
    } catch (e) {
      _log.warning('epg load: $e');
    }
  }

  static (Map<String, List<EpgProg>>, Map<String, String>) _decodeShort(String s) {
    final m = jsonDecode(s) as Map;
    final ch = <String, List<EpgProg>>{
      for (final e in ((m['ch'] as Map?) ?? const {}).entries)
        '${e.key}': [for (final l in e.value as List) EpgProg.fromJson(l as List)]
    };
    final lg = <String, String>{for (final e in ((m['logo'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'};
    return (ch, lg);
  }

  /// Вся программа канала (архив и вперёд) — с диска.
  Future<List<EpgProg>> full(IptvPlaylist p, IptvChannel c) async {
    try {
      final f = File('${(await _dir()).path}/epg_${p.id}/${_fileName(c.key)}.json');
      if (!await f.exists()) return now.value[c.key] ?? const [];
      final l = jsonDecode(await f.readAsString()) as List;
      return [for (final x in l) EpgProg.fromJson(x as List)];
    } catch (_) {
      return now.value[c.key] ?? const [];
    }
  }

  EpgProg? current(String key) {
    final t = _nowSec;
    for (final p in now.value[key] ?? const <EpgProg>[]) {
      if (p.isNow(t)) return p;
    }
    return null;
  }

  List<EpgProg> upcoming(String key, {int count = 4}) {
    final t = _nowSec;
    return (now.value[key] ?? const <EpgProg>[]).where((p) => p.start >= t).take(count).toList();
  }

  Future<void> _build(IptvPlaylist p, IptvParsed parsed) async {
    final urls = sources(p, parsed);
    if (urls.isEmpty) return;
    _building = true;
    busy.value = 'Обновляю телепрограмму…';
    final dir = (await _dir()).path;
    final chans = [
      for (final c in parsed.channels) [c.key, c.tvgId, c.tvgName, c.name, c.catchupDays]
    ];
    try {
      final stats = await Isolate.run(() => _buildEpg(urls, chans, dir, p.id));
      _log.info('epg ${p.name}: $stats');
      await _loadShort(File('$dir/epg_${p.id}.json'), p.id);
    } catch (e) {
      _log.warning('epg build: $e');
    } finally {
      _building = false;
      busy.value = null;
    }
  }

  static String _fileName(String key) {
    // безопасное имя файла из ключа канала
    final b = utf8.encode(key);
    var h = 0x811c9dc5;
    for (final x in b) {
      h ^= x;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }
}

// ======================= разбор в отдельном потоке =======================

/// Название для сопоставления: без регистра, «ё», пометок качества и знаков.
String epgNorm(String s) {
  var x = s.toLowerCase().replaceAll('ё', 'е');
  x = x.replaceAll(RegExp(r'\b(uhd|4k|8k|fhd|qhd|hd|sd|hq|orig|original|50fps|60fps)\b'), ' ');
  x = x.replaceAll(RegExp(r'[()\[\]«»"\x27.,:;!?_\-–—|/\\]'), ' ');
  return x.replaceAll(RegExp(r'\s+'), '');
}

/// Скачать XMLTV и разобрать потоком (без DOM: файл бывает 400+ МБ). Возвращает краткую сводку.
Future<String> _buildEpg(List<String> urls, List<List<Object>> chans, String dir, String plId) async {
  final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  // ключи каналов плейлиста по id и по названию
  final byId = <String, List<String>>{};
  final byName = <String, List<String>>{};
  final archiveDays = <String, int>{};
  for (final c in chans) {
    final key = c[0] as String;
    archiveDays[key] = c[4] as int;
    if ((c[1] as String).isNotEmpty) (byId[(c[1] as String).toLowerCase()] ??= []).add(key);
    for (final n in [c[2] as String, c[3] as String]) {
      final k = epgNorm(n);
      if (k.isNotEmpty) (byName[k] ??= []).add(key);
    }
  }
  final idMap = <String, List<String>>{}; // id канала в XMLTV → ключи плейлиста
  final logos = <String, String>{};
  final progs = <String, List<EpgProg>>{};
  var progCount = 0, chanCount = 0;

  for (final url in urls) {
    final client = http.Client();
    try {
      final res = await client
          .send(http.Request('GET', Uri.parse(url))..headers['User-Agent'] = 'Mozilla/5.0 CloudTube')
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) continue;
      final bytes = res.stream.timeout(const Duration(seconds: 60));
      final gz = url.toLowerCase().endsWith('.gz') || (res.headers['content-type'] ?? '').contains('gzip');
      final Stream<List<int>> plain = gz ? bytes.transform(gzip.decoder) : bytes;
      var pending = '';
      await for (final chunk in plain.transform(const Utf8Decoder(allowMalformed: true))) {
        pending += chunk;
        var pos = 0;
        while (true) {
          final pi = pending.indexOf('<programme', pos);
          final ci = pending.indexOf('<channel', pos);
          int at;
          bool isProg;
          if (pi < 0 && ci < 0) break;
          if (ci >= 0 && (pi < 0 || ci < pi)) {
            at = ci;
            isProg = false;
          } else {
            at = pi;
            isProg = true;
          }
          final endTag = isProg ? '</programme>' : '</channel>';
          final end = pending.indexOf(endTag, at);
          if (end < 0) {
            pos = at;
            break;
          }
          final block = pending.substring(at, end + endTag.length);
          pos = end + endTag.length;
          if (isProg) {
            final id = _attr(block, 'channel').toLowerCase();
            final keys = idMap[id];
            if (keys == null) continue;
            final start = _xmltvTime(_attr(block, 'start'));
            final stop = _xmltvTime(_attr(block, 'stop'));
            if (start == 0 || stop <= start) continue;
            // окно: вперёд на 2 суток; назад — глубина архива (минимум 6 часов)
            if (start > nowSec + 2 * 86400) continue;
            final title = _tag(block, 'title');
            if (title.isEmpty) continue;
            var desc = _tag(block, 'desc');
            if (desc.length > 220) desc = '${desc.substring(0, 217)}…';
            for (final k in keys) {
              final back = ((archiveDays[k] ?? 0) * 86400).clamp(6 * 3600, 8 * 86400);
              if (stop < nowSec - back) continue;
              (progs[k] ??= []).add(EpgProg(start, stop, title, desc));
              progCount++;
            }
          } else {
            chanCount++;
            final id = _attr(block, 'id').toLowerCase();
            final keys = <String>{...?byId[id]};
            for (final m in RegExp(r'<display-name[^>]*>([^<]*)</display-name>').allMatches(block)) {
              keys.addAll(byName[epgNorm(_unescape(m.group(1)!))] ?? const []);
            }
            if (keys.isEmpty) continue;
            (idMap[id] ??= []).addAll(keys);
            final icon = RegExp(r'<icon[^>]*src="([^"]+)"').firstMatch(block)?.group(1);
            if (icon != null) {
              for (final k in keys) {
                logos.putIfAbsent(k, () => _unescape(icon));
              }
            }
          }
        }
        pending = pending.substring(pos);
        // защита от «рваного» файла без закрывающих тегов
        if (pending.length > 4 * 1024 * 1024) pending = '';
      }
    } catch (e) {
      // следующий источник
    } finally {
      client.close();
    }
    if (progs.isNotEmpty) break; // первый рабочий источник
  }

  // на диск: сутки для списка и полная программа по каналам
  final short = <String, List<List<Object>>>{};
  final chDir = Directory('$dir/epg_$plId');
  if (await chDir.exists()) await chDir.delete(recursive: true);
  await chDir.create(recursive: true);
  for (final e in progs.entries) {
    final list = e.value..sort((a, b) => a.start.compareTo(b.start));
    // дубли (несколько вариантов в XMLTV) — по времени начала
    final dedup = <EpgProg>[];
    for (final p in list) {
      if (dedup.isEmpty || dedup.last.start != p.start) dedup.add(p);
    }
    short[e.key] = [
      for (final p in dedup)
        if (p.stop > nowSec - 3 * 3600 && p.start < nowSec + 26 * 3600) p.toJson()
    ];
    await File('${chDir.path}/${IptvEpg._fileName(e.key)}.json')
        .writeAsString(jsonEncode([for (final p in dedup) p.toJson()]));
  }
  final f = File('$dir/epg_$plId.json');
  await File('${f.path}.tmp').writeAsString(jsonEncode({'ch': short, 'logo': logos}));
  await File('${f.path}.tmp').rename(f.path);
  return 'каналов в XMLTV $chanCount, сопоставлено ${progs.length}, передач $progCount';
}

String _attr(String block, String name) {
  final m = RegExp('$name="([^"]*)"').firstMatch(block);
  return m == null ? '' : _unescape(m.group(1)!);
}

String _tag(String block, String name) {
  final m = RegExp('<$name[^>]*>([\\s\\S]*?)</$name>').firstMatch(block);
  return m == null ? '' : _unescape(m.group(1)!.trim());
}

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

/// «20261120183000 +0300» → секунды UTC.
int _xmltvTime(String s) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{4})?').firstMatch(s.trim());
  if (m == null) return 0;
  final t = DateTime.utc(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!), int.parse(m.group(4)!),
      int.parse(m.group(5)!), int.parse(m.group(6) ?? '0'));
  var sec = t.millisecondsSinceEpoch ~/ 1000;
  final tz = m.group(7);
  if (tz != null) {
    final sign = tz.startsWith('-') ? -1 : 1;
    final off = int.parse(tz.substring(1, 3)) * 3600 + int.parse(tz.substring(3, 5)) * 60;
    sec -= sign * off;
  }
  return sec;
}

@visibleForTesting
int epgParseTime(String s) => _xmltvTime(s);
