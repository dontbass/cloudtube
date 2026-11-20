import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import 'm3u.dart';

final _log = Logger('Iptv');

/// Плейлист, добавленный пользователем.
class IptvPlaylist {
  final String id;
  final String name;

  /// Ссылка (http/https) или пусто, если плейлист загружен файлом.
  final String url;
  final String userAgent;

  /// Своя ссылка на телепрограмму (иначе — из плейлиста или общая по умолчанию).
  final String epgUrl;
  final DateTime updated;

  const IptvPlaylist(
      {required this.id, required this.name, this.url = '', this.userAgent = '', this.epgUrl = '', required this.updated});

  IptvPlaylist copyWith({String? name, String? url, String? userAgent, String? epgUrl, DateTime? updated}) =>
      IptvPlaylist(
          id: id,
          name: name ?? this.name,
          url: url ?? this.url,
          userAgent: userAgent ?? this.userAgent,
          epgUrl: epgUrl ?? this.epgUrl,
          updated: updated ?? this.updated);

  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'url': url, 'ua': userAgent, 'epg': epgUrl, 'upd': updated.millisecondsSinceEpoch};

  static IptvPlaylist fromJson(Map m) => IptvPlaylist(
      id: '${m['id']}',
      name: '${m['name'] ?? ''}',
      url: '${m['url'] ?? ''}',
      userAgent: '${m['ua'] ?? ''}',
      epgUrl: '${m['epg'] ?? ''}',
      updated: DateTime.fromMillisecondsSinceEpoch((m['upd'] as num?)?.toInt() ?? 0));
}

/// Настройки IPTV.
class IptvSettings {
  /// Качество по умолчанию: false — «совместимое» (HD со звуком AAC, работает на любой приставке),
  /// true — максимальное (FHD/4K; звук MP2 декодируют не все приставки).
  final bool preferMax;

  /// Объединять варианты одного канала (HD / FHD / 4K) в одну строку.
  final bool merge;

  /// Показывать 4K-варианты (тяжело для слабых приставок).
  final bool show4k;

  /// Открывать последний канал при входе в раздел.
  final bool resumeLast;

  /// Обновлять плейлист при открытии раздела, если старше стольких часов.
  final int refreshHours;

  /// Источник телепрограммы по умолчанию (если в плейлисте его нет).
  final String defaultEpg;

  const IptvSettings({
    this.preferMax = false,
    this.merge = true,
    this.show4k = true,
    this.resumeLast = false,
    this.refreshHours = 12,
    this.defaultEpg = kIptvDefaultEpg,
  });

  IptvSettings copyWith(
          {bool? preferMax, bool? merge, bool? show4k, bool? resumeLast, int? refreshHours, String? defaultEpg}) =>
      IptvSettings(
          preferMax: preferMax ?? this.preferMax,
          merge: merge ?? this.merge,
          show4k: show4k ?? this.show4k,
          resumeLast: resumeLast ?? this.resumeLast,
          refreshHours: refreshHours ?? this.refreshHours,
          defaultEpg: defaultEpg ?? this.defaultEpg);

  Map<String, Object?> toJson() => {
        'max': preferMax,
        'merge': merge,
        '4k': show4k,
        'resume': resumeLast,
        'refresh': refreshHours,
        'epg': defaultEpg,
      };

  static IptvSettings fromJson(Map m) => IptvSettings(
        preferMax: m['max'] == true,
        merge: m['merge'] != false,
        show4k: m['4k'] != false,
        resumeLast: m['resume'] == true,
        refreshHours: (m['refresh'] as num?)?.toInt() ?? 12,
        defaultEpg: '${m['epg'] ?? kIptvDefaultEpg}',
      );
}

/// Телепрограмма по умолчанию (большинство русскоязычных провайдеров, сопоставление по названию).
const kIptvDefaultEpg = 'http://epg.it999.ru/epg.xml.gz';

/// Хранилище IPTV: плейлисты, разобранные каналы (кэш на диске), избранное, недавние, настройки.
/// Всё в файлах приложения (iptv/*.json) — без базы, чтобы раздел ничего не стоил, пока не нужен.
class IptvStore {
  IptvStore._();
  static final IptvStore I = IptvStore._();

  final playlists = ValueNotifier<List<IptvPlaylist>>(const []);
  final settings = ValueNotifier<IptvSettings>(const IptvSettings());
  final favorites = ValueNotifier<List<String>>(const []);
  final recent = ValueNotifier<List<String>>(const []);
  String? currentPlaylistId;
  String? lastChannelKey;

  final _parsed = <String, IptvParsed>{};
  bool _loaded = false;
  Directory? _dir;

  Future<Directory> _root() async {
    if (_dir != null) return _dir!;
    final d = Directory('${(await getApplicationSupportDirectory()).path}/iptv');
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  Future<File> _file(String name) async => File('${(await _root()).path}/$name');

  Future<Map<String, dynamic>> _readJson(String name) async {
    try {
      final f = await _file(name);
      if (!await f.exists()) return {};
      return (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>();
    } catch (e) {
      _log.warning('read $name: $e');
      return {};
    }
  }

  Future<void> _writeJson(String name, Object data) async {
    final f = await _file(name);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(f.path);
  }

  Future<void> load() async {
    if (_loaded) return;
    final m = await _readJson('state.json');
    playlists.value = [for (final p in (m['playlists'] as List? ?? const [])) IptvPlaylist.fromJson(p as Map)];
    settings.value = IptvSettings.fromJson((m['settings'] as Map?) ?? const {});
    favorites.value = [for (final f in (m['fav'] as List? ?? const [])) '$f'];
    recent.value = [for (final f in (m['recent'] as List? ?? const [])) '$f'];
    currentPlaylistId = m['current'] as String?;
    lastChannelKey = m['last'] as String?;
    if (currentPlaylistId == null && playlists.value.isNotEmpty) currentPlaylistId = playlists.value.first.id;
    _loaded = true;
  }

  Future<void> _save() => _writeJson('state.json', {
        'playlists': [for (final p in playlists.value) p.toJson()],
        'settings': settings.value.toJson(),
        'fav': favorites.value,
        'recent': recent.value,
        'current': currentPlaylistId,
        'last': lastChannelKey,
      });

  IptvPlaylist? get current =>
      playlists.value.where((p) => p.id == currentPlaylistId).firstOrNull ?? playlists.value.firstOrNull;

  Future<void> setSettings(IptvSettings s) async {
    final mergeChanged = s.merge != settings.value.merge;
    settings.value = s;
    if (mergeChanged) _parsed.clear();
    await _save();
  }

  Future<void> selectPlaylist(String id) async {
    currentPlaylistId = id;
    await _save();
  }

  Future<void> toggleFavorite(String key) async {
    final f = [...favorites.value];
    f.contains(key) ? f.remove(key) : f.insert(0, key);
    favorites.value = f;
    await _save();
  }

  Future<void> markWatched(String key) async {
    lastChannelKey = key;
    recent.value = [key, ...recent.value.where((k) => k != key)].take(30).toList();
    await _save();
  }

  /// Добавить плейлист по ссылке: скачать, проверить, что это M3U, сохранить.
  Future<IptvPlaylist> addUrl(String url, {String name = '', String userAgent = '', String epgUrl = ''}) async {
    await load();
    url = url.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'http://$url';
    final text = await _download(url, userAgent);
    return _addText(text, name: name, url: url, userAgent: userAgent, epgUrl: epgUrl);
  }

  /// Добавить плейлист из текста (загрузка файла с телефона).
  Future<IptvPlaylist> addText(String text, {String name = '', String epgUrl = ''}) async {
    await load();
    return _addText(text, name: name, epgUrl: epgUrl);
  }

  Future<IptvPlaylist> _addText(String text,
      {String name = '', String url = '', String userAgent = '', String epgUrl = ''}) async {
    final parsed = await _parse(text);
    if (parsed.channels.isEmpty) throw 'В плейлисте не найдено ни одного канала';
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final p = IptvPlaylist(
        id: id,
        name: name.trim().isNotEmpty ? name.trim() : _nameFromUrl(url, parsed.channels.length),
        url: url,
        userAgent: userAgent.trim(),
        epgUrl: epgUrl.trim(),
        updated: DateTime.now());
    await (await _file('pl_$id.m3u')).writeAsString(text);
    _parsed[id] = parsed;
    playlists.value = [...playlists.value, p];
    currentPlaylistId = id;
    await _save();
    return p;
  }

  Future<void> remove(String id) async {
    playlists.value = playlists.value.where((p) => p.id != id).toList();
    _parsed.remove(id);
    try {
      await (await _file('pl_$id.m3u')).delete();
    } catch (_) {}
    if (currentPlaylistId == id) currentPlaylistId = playlists.value.firstOrNull?.id;
    await _save();
  }

  Future<void> update(IptvPlaylist p) async {
    playlists.value = [for (final x in playlists.value) x.id == p.id ? p : x];
    await _save();
  }

  /// Каналы плейлиста: из памяти, с диска, при устаревании — обновление по ссылке в фоне.
  Future<IptvParsed> channels(IptvPlaylist p, {bool force = false}) async {
    await load();
    final cached = _parsed[p.id];
    final stale = p.url.isNotEmpty &&
        DateTime.now().difference(p.updated) > Duration(hours: settings.value.refreshHours.clamp(1, 24 * 30));
    if (cached != null && !force && !stale) return cached;
    if (p.url.isNotEmpty && (force || stale || cached == null)) {
      try {
        final text = await _download(p.url, p.userAgent);
        final parsed = await _parse(text);
        if (parsed.channels.isNotEmpty) {
          await (await _file('pl_${p.id}.m3u')).writeAsString(text);
          _parsed[p.id] = parsed;
          await update(p.copyWith(updated: DateTime.now()));
          return parsed;
        }
      } catch (e) {
        _log.warning('playlist refresh ${p.name}: $e');
        if (cached != null) return cached;
      }
    }
    final f = await _file('pl_${p.id}.m3u');
    if (!await f.exists()) throw 'Плейлист не загружен — проверьте ссылку';
    final parsed = await _parse(await f.readAsString());
    _parsed[p.id] = parsed;
    return parsed;
  }

  Future<IptvParsed> _parse(String text) {
    final merge = settings.value.merge;
    // разбор в отдельном потоке: 20–50 тыс. строк не подвешивают интерфейс приставки
    return Isolate.run(() => parseM3u(text, merge: merge));
  }

  static Future<String> _download(String url, String ua) async {
    final r = await http.get(Uri.parse(url), headers: {
      'User-Agent': ua.isNotEmpty ? ua : 'Mozilla/5.0 (Linux; Android 12) CloudTube',
    }).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) throw 'Сервер плейлиста ответил ${r.statusCode}';
    if (r.bodyBytes.length > 60 * 1024 * 1024) throw 'Плейлист слишком большой (больше 60 МБ)';
    final text = utf8.decode(r.bodyBytes, allowMalformed: true);
    if (!text.contains('#EXTINF')) throw 'По ссылке не плейлист M3U';
    return text;
  }

  static String _nameFromUrl(String url, int n) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isNotEmpty ? '$host · $n каналов' : 'Плейлист · $n каналов';
  }
}
