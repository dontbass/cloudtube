import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';

import '../globals.dart';
import '../search/models/search_date.dart';
import '../search/models/search_duration.dart';
import '../search/models/search_sort_by.dart';
import '../search/models/search_type.dart';
import '../videos/models/video.dart';

final _log = Logger('CtServer');

/// Есть ли на сервере дополнения CloudTube (папка server/ в репозитории):
/// разделы «Навигатора», подборка Shorts, комментарии через yt-dlp, аватарки.
/// На обычном Invidious приложение работает в совместимом режиме.
class CtServer {
  static final Map<String, (DateTime, bool)> _cache = {};

  static Future<bool> hasAddons() async {
    final server = await db.getCurrentlySelectedServer();
    final hit = _cache[server.url];
    if (hit != null && DateTime.now().difference(hit.$1) < Duration(minutes: hit.$2 ? 60 : 5)) {
      return hit.$2;
    }
    var ok = false;
    try {
      final req = await service.buildRequest('/ct-api/caps');
      final r = await service.httpClient
          .get(req.uri, headers: req.headers)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        ok = j is Map && j['cloudtube'] != null;
      }
    } catch (e) {
      _log.fine('caps: $e');
    }
    _cache[server.url] = (DateTime.now(), ok);
    _log.info('server ${server.url}: add-ons ${ok ? 'есть' : 'нет'}');
    return ok;
  }

  /// Разделы для обычного Invidious: тренды по типу или поиск по запросу.
  static Future<List<Video>> fallbackSection(String id, int page) async {
    switch (id) {
      case 'music':
        return page == 1 ? service.getTrending(type: 'music') : [];
      case 'gaming':
        return page == 1 ? service.getTrending(type: 'gaming') : [];
      case 'movies':
        return page == 1 ? service.getTrending(type: 'movies') : [];
    }
    const queries = {
      'live': 'live',
      'news': 'новости',
      'sport': 'спорт обзор матча',
      'podcasts': 'подкаст',
    };
    final q = queries[id];
    if (q == null) return [];
    final r = await service.search(q,
        type: SearchType.video,
        page: page,
        sortBy: id == 'live' ? null : SearchSortBy.views,
        date: id == 'live' ? SearchDate.any : SearchDate.week,
        duration: id == 'podcasts' ? SearchDuration.long : SearchDuration.any);
    return id == 'live' ? r.videos.where((v) => v.liveNow == true).toList() : r.videos;
  }

  /// Shorts без дополнений: поиск #shorts, только короткие ролики (не трансляции).
  static Future<List<Video>> fallbackShorts(int page) async {
    const tags = ['#shorts', '#shorts funny', '#shorts music', '#shorts animals', '#shorts sport'];
    final q = tags[(page - 1) % tags.length];
    final r = await service.search(q,
        type: SearchType.video,
        page: (page - 1) ~/ tags.length + 1,
        sortBy: SearchSortBy.views,
        date: SearchDate.month,
        duration: SearchDuration.short);
    return r.videos
        .where((v) => v.liveNow != true && (v.lengthSeconds ?? 0) > 0 && (v.lengthSeconds ?? 0) <= 90)
        .toList();
  }
}
