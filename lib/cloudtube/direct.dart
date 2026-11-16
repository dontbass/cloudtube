import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import 'yt_account.dart';
import 'yt_comments.dart';
import 'trace.dart';
import 'yt_fast.dart';

final _log = Logger('CtDirect');

/// Адрес «сервера» для режима без сервера: приложение ходит в YouTube напрямую.
const kCtDirectUrl = 'https://youtube.direct';
const _host = 'youtube.direct';

/// Потоки YouTube, полученные от клиента iOS, отдаются только с его User-Agent (иначе 403/зависание).
const kCtIosUserAgent = 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)';

/// Заголовки для воспроизведения ссылок YouTube в режиме без сервера.
/// Поток отдаётся только с User-Agent того клиента, для которого YouTube выдал ссылку
/// (параметр c= в адресе: IOS, ANDROID, ANDROID_VR, WEB…), иначе 403.
Map<String, String> ctDirectStreamHeaders(String url) {
  if (!ctDirectActive || !(url.contains('googlevideo.com') || url.contains('youtube.com'))) return {};
  final c = RegExp(r'[?&/]c[=/]([A-Z_0-9]+)').firstMatch(url)?.group(1) ?? 'IOS';
  return {'User-Agent': ctUserAgentForClient(c)};
}

String ctUserAgentForClient(String c) {
  switch (c) {
    case 'ANDROID':
    case 'ANDROID_MUSIC':
      return 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
    case 'ANDROID_VR':
      return 'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12; eureka-user Build/SQ3A.220605.009.A1) gzip';
    case 'IOS':
      return kCtIosUserAgent;
    default:
      return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  }
}

/// Сейчас выбран режим «без сервера» (обновляется при смене сервера).
bool ctDirectActive = false;

/// Сбросить кэш видео (для проверки скорости).
void ctDirectClearCache() => _CtDirect.instance._videoCache.clear();

bool ctIsDirectUrl(String? url) => url != null && Uri.tryParse(url)?.host == _host;

/// HTTP-клиент приложения. Запросы к обычным серверам уходят как есть, а запросы к youtube.direct
/// обрабатываются здесь: вместо Invidious ответ собирается из YouTube (youtube_explode) в том же
/// формате, что у Invidious API. Поэтому весь остальной код приложения не знает, что сервера нет.
class CtHttpClient extends http.BaseClient {
  final http.Client _inner;

  CtHttpClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.host != _host) return _inner.send(request);
    int code = 200;
    Object? body;
    try {
      final auth = request.headers['Authorization'] ?? request.headers['authorization'];
      body = await _CtDirect.instance.handle(request.method, request.url,
          refresh: ctYtRefreshToken ?? (auth != null && auth.startsWith('Bearer ') ? auth.substring(7) : null));
      if (body == null) code = 404;
    } on CtYtAuthError catch (e) {
      code = 401;
      body = {'error': e.message};
    } on _Http catch (e) {
      code = e.code;
      body = {'error': e.message};
    } catch (e, s) {
      _log.warning('direct ${request.url.path}: $e', e, s);
      code = 500;
      body = {'error': '$e'};
    }
    final bytes = utf8.encode(jsonEncode(body ?? {'error': 'not found'}));
    return http.StreamedResponse(Stream.value(bytes), code,
        request: request, headers: {'content-type': 'application/json; charset=utf-8'}, contentLength: bytes.length);
  }

  @override
  void close() => _inner.close();
}

class _Http implements Exception {
  final int code;
  final String message;

  _Http(this.code, this.message);
}

/// Пагинация YouTube идёт «следующими страницами», а Invidious — номером страницы.
/// Храним уже полученные страницы по ключу запроса.
class _Pager<T> {
  final List<List<T>> pages = [];
  dynamic list; // объект youtube_explode со свойством nextPage()
  DateTime at = DateTime.now();
}

class _CtDirect {
  static final instance = _CtDirect();
  final _yt = yt.YoutubeExplode();
  final _pagers = <String, _Pager>{};
  final _videoCache = <String, (DateTime, Map<String, dynamic>)>{};

  String? _refresh;

  Future<Object?> handle(String method, Uri u, {String? refresh}) async {
    final p = u.pathSegments;
    final q = u.queryParameters;
    _refresh = (refresh?.isNotEmpty ?? false) ? refresh : null;
    if (p.length < 3 || p[0] != 'api' || p[1] != 'v1') return null;
    if (p[2] == 'auth') return _auth(method, p, q);
    if (method != 'GET') throw _Http(405, 'Без сервера это действие недоступно');
    switch (p[2]) {
      case 'stats':
        return {
          'version': '2.0',
          'software': {'name': 'cloudtube-direct', 'version': '1', 'branch': 'direct'},
          'openRegistrations': false,
          'usage': {'users': {'total': 0}},
        };
      case 'videos':
        if (p.length >= 4) return _video(p[3]);
      case 'search':
        if (p.length >= 4 && p[3] == 'suggestions') {
          final s = await _yt.search.getQuerySuggestions(q['q'] ?? '');
          return {'query': q['q'] ?? '', 'suggestions': s};
        }
        return _search(q);
      case 'trending':
      case 'popular':
        return _trending(q['type'] ?? (p[2] == 'popular' ? '' : 'default'));
      case 'channels':
        if (p.length == 4) return _channel(p[3]);
        if (p.length >= 5) {
          switch (p[4]) {
            case 'videos':
              return _channelVideos(p[3], yt.VideoType.normal, q['continuation'], q['sort_by']);
            case 'shorts':
              return _channelVideos(p[3], yt.VideoType.shorts, q['continuation'], q['sort_by']);
            case 'streams':
              return {'videos': [], 'continuation': null};
            case 'playlists':
              return {'playlists': [], 'continuation': null};
          }
        }
        return null;
      case 'comments':
        if (p.length >= 4) {
          // свой разбор InnerTube: в youtube_explode комментарии сломаны
          final cont = q['continuation'];
          if (cont != null && cont.startsWith('y:')) return CtYtComments.more(p[3], cont.substring(2));
          return CtYtComments.load(p[3], q['sort_by'] == 'new' ? 'new' : 'top');
        }
        return null;
      case 'playlists':
        if (p.length >= 4) return _playlist(p[3], int.tryParse(q['page'] ?? '1') ?? 1);
        return null;
    }
    return null;
  }

  // ---------- общие преобразования ----------
  List<Map<String, dynamic>> _thumbs(String id) => [
        {'quality': 'maxres', 'url': 'https://i.ytimg.com/vi/$id/maxresdefault.jpg', 'width': 1280, 'height': 720},
        {'quality': 'sddefault', 'url': 'https://i.ytimg.com/vi/$id/sddefault.jpg', 'width': 640, 'height': 480},
        {'quality': 'high', 'url': 'https://i.ytimg.com/vi/$id/hqdefault.jpg', 'width': 480, 'height': 360},
        {'quality': 'medium', 'url': 'https://i.ytimg.com/vi/$id/mqdefault.jpg', 'width': 320, 'height': 180},
      ];

  Map<String, dynamic> _brief(yt.Video v) {
    final id = v.id.value;
    final views = v.engagement.viewCount;
    return {
      'type': 'video',
      'videoId': id,
      'title': v.title,
      'author': v.author,
      'authorId': v.channelId.value,
      'authorUrl': '/channel/${v.channelId.value}',
      'lengthSeconds': v.duration?.inSeconds ?? 0,
      'viewCount': views,
      'published': (v.uploadDate ?? v.publishDate)?.millisecondsSinceEpoch == null
          ? 0
          : (v.uploadDate ?? v.publishDate)!.millisecondsSinceEpoch ~/ 1000,
      'publishedText': v.uploadDateRaw ?? '',
      'liveNow': v.isLive,
      'videoThumbnails': _thumbs(id),
      'description': v.description,
    };
  }

  // ---------- видео ----------
  final _inflight = <String, Future<Map<String, dynamic>>>{};

  /// Страница видео и плеер запрашивают одно и то же одновременно — делаем один запрос на двоих.
  Future<Map<String, dynamic>> _video(String id) {
    final hit = _videoCache[id];
    if (hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 30)) return Future.value(hit.$2);
    // ВАЖНО: обработчик whenComplete не должен возвращать Future (remove() вернул бы этот же Future,
    // и whenComplete ждал бы сам себя — вечное ожидание; так сломался запуск видео в 1.1.19)
    return _inflight[id] ??= _video0(id).timeout(const Duration(seconds: 25)).whenComplete(() {
      _inflight.remove(id);
    });
  }

  Future<Map<String, dynamic>> _video0(String id) async {
    CtTrace.mark('адаптер: начало');
    // быстрый путь: сразу «player» без страницы просмотра (как NewPipe/LibreTube)
    try {
      final f = await CtYtFast.video(id);
      if (f != null) {
        _videoCache[id] = (DateTime.now(), f);
        if (_videoCache.length > 80) _videoCache.remove(_videoCache.keys.first);
        return f;
      }
    } catch (e) {
      CtTrace.mark('адаптер: ошибка быстрого пути: $e');
      _log.info('fast $id: $e');
    }
    CtTrace.mark('адаптер: запасной путь (медленный)');
    final sw = Stopwatch()..start();
    // Запасной путь — Всё параллельно: страница видео (описание и т.п.) + два «быстрых» клиента без загрузки страницы.
    // iOS даёт HLS-мастер (все качества со звуком), ANDROID_VR — 360p со звуком и раздельные потоки
    // (для них не нужен PO-токен). Замеры: каждый ~0,2–0,3 с против 1,3–1,5 с со страницей просмотра.
    final vFut = _yt.videos.get(id).timeout(const Duration(seconds: 10));
    final iosFut = _manifestFor(id, yt.YoutubeApiClient.ios);
    final vrFut = _manifestFor(id, yt.YoutubeApiClient.androidVr);
    final anFut = _manifestFor(id, yt.YoutubeApiClient.androidSdkless);
    final v = await vFut;
    final j = _brief(v);
    j['likeCount'] = v.engagement.likeCount ?? 0;
    j['keywords'] = v.keywords.toList();
    j['descriptionHtml'] = const HtmlEscape().convert(v.description).replaceAll('\n', '<br>');
    j['allowRatings'] = true;
    j['isListed'] = true;
    // канал и рекомендации — с коротким ограничением по времени, чтобы не задерживать запуск видео
    final chFut = _yt.channels.get(v.channelId).timeout(const Duration(seconds: 3));
    final relFut = _yt.videos.getRelatedVideos(v).timeout(const Duration(seconds: 4));

    var ios = await iosFut;
    var vr = await vrFut;
    // запасной клиент ANDROID — если VR не дал потока со звуком (бывает у Shorts)
    if (vr == null || vr.muxed.isEmpty) {
      final an = await anFut;
      if (an != null && an.muxed.isNotEmpty) vr = an;
    }
    if (ios == null && vr == null) {
      // оба быстрых клиента отказали — стандартный путь библиотеки (медленнее, со страницей просмотра)
      try {
        vr = await _yt.videos.streams.getManifest(id).timeout(const Duration(seconds: 12));
      } catch (e) {
        _log.warning('streams $id: $e');
      }
    }
    final master = ios?.hlsManifestUrl ?? vr?.hlsManifestUrl;
    if (master != null) j['hlsUrl'] = master;
    final muxed = (vr?.muxed.isNotEmpty ?? false) ? vr!.muxed : (ios?.muxed ?? const <yt.MuxedStreamInfo>[]);
    final adaptive = (vr?.videoOnly.isNotEmpty ?? false) ? vr! : ios;
    j['formatStreams'] = muxed
        .map((s) => {
              'url': s.url.toString(),
              'itag': '${s.tag}',
              'type': '${s.codec.mimeType}; codecs="${s.videoCodec}, ${s.audioCodec}"',
              'quality': s.qualityLabel,
              'container': s.container.name,
              'encoding': s.videoCodec,
              'qualityLabel': s.qualityLabel,
              'resolution': '${s.videoResolution.height}p',
              'size': '${s.videoResolution.width}x${s.videoResolution.height}',
            })
        .toList();
    j['adaptiveFormats'] = adaptive == null
        ? []
        : [
            ...adaptive.videoOnly.map((s) => {
                  'url': s.url.toString(),
                  'itag': '${s.tag}',
                  'type': '${s.codec.mimeType}; codecs="${s.videoCodec}"',
                  'bitrate': '${s.bitrate.bitsPerSecond}',
                  'clen': '${s.size.totalBytes}',
                  'lmt': '0',
                  'projectionType': 'RECTANGULAR',
                  'container': s.container.name,
                  'encoding': s.videoCodec,
                  'qualityLabel': s.qualityLabel,
                  'resolution': '${s.videoResolution.height}p',
                  'size': '${s.videoResolution.width}x${s.videoResolution.height}',
                }),
            ...adaptive.audioOnly.map((s) => {
                  'url': s.url.toString(),
                  'itag': '${s.tag}',
                  'type': '${s.codec.mimeType}; codecs="${s.audioCodec}"',
                  'bitrate': '${s.bitrate.bitsPerSecond}',
                  'clen': '${s.size.totalBytes}',
                  'lmt': '0',
                  'projectionType': 'RECTANGULAR',
                  'container': s.container.name,
                  'encoding': s.audioCodec,
                }),
          ];
    final streamsMs = sw.elapsedMilliseconds;
    // канал и рекомендации ждём не дольше ~0,8 с после готовности потоков — видео важнее;
    // если не успели, допишем их в кэш позже (при следующем открытии будут)
    final budget = Future.delayed(const Duration(milliseconds: 800));
    unawaited(Future.wait([chFut, relFut].map((f) => f.then((_) => null, onError: (_) => null))).then((_) async {
      final hit = _videoCache[id]?.$2;
      if (hit == null) return;
      try {
        final ch = await chFut;
        hit['authorThumbnails'] ??= [
          {'url': ch.logoUrl, 'width': 176, 'height': 176},
        ];
      } catch (_) {}
      try {
        if ((hit['recommendedVideos'] as List?)?.isEmpty ?? true) {
          hit['recommendedVideos'] = ((await relFut) ?? const <yt.Video>[]).map<Map<String, dynamic>>((e) => _brief(e)).toList();
        }
      } catch (_) {}
    }));
    try {
      final ch = await Future.any([chFut, budget.then((_) => throw 'late')]);
      j['authorThumbnails'] = [
        {'url': ch.logoUrl, 'width': 176, 'height': 176},
      ];
      if (ch.subscribersCount != null) j['subCountText'] = _short(ch.subscribersCount!);
    } catch (_) {}
    try {
      final rel = await Future.any([relFut, budget.then((_) => throw 'late')]);
      j['recommendedVideos'] = (rel ?? const <yt.Video>[]).map<Map<String, dynamic>>((e) => _brief(e)).toList();
    } catch (_) {
      j['recommendedVideos'] = [];
    }
    _log.info('video $id: потоки ${streamsMs}мс, всего ${sw.elapsedMilliseconds}мс, '
        'hls=${master != null} muxed=${muxed.length} adaptive=${(j['adaptiveFormats'] as List).length}');
    _videoCache[id] = (DateTime.now(), j);
    if (_videoCache.length > 80) _videoCache.remove(_videoCache.keys.first);
    return j;
  }

  /// Манифест одного клиента без загрузки страницы просмотра; null — если клиент не дал потоков.
  Future<yt.StreamManifest?> _manifestFor(String id, yt.YoutubeApiClient c) async {
    try {
      return await _yt.videos.streams
          .getManifest(id, ytClients: [c], requireWatchPage: false)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      _log.info('manifest ${c.payload['context']?['client']?['clientName']} $id: $e');
      return null;
    }
  }

  // ---------- поиск ----------
  yt.SearchFilter _filter(Map<String, String> q) {
    switch (q['date']) {
      case 'hour':
        return yt.UploadDateFilter.lastHour;
      case 'today':
        return yt.UploadDateFilter.today;
      case 'week':
        return yt.UploadDateFilter.lastWeek;
      case 'month':
        return yt.UploadDateFilter.lastMonth;
      case 'year':
        return yt.UploadDateFilter.lastYear;
    }
    switch (q['duration']) {
      case 'short':
        return yt.DurationFilters.short;
      case 'long':
        return yt.DurationFilters.long;
    }
    if (q['features'] == 'live') return yt.FeatureFilters.live;
    return yt.TypeFilters.video;
  }

  Future<List<Map<String, dynamic>>> _videoSearchPage(String query, yt.SearchFilter f, int page) async {
    final key = 's|$query|${f.value}';
    var pg = _pagers[key];
    if (pg == null || DateTime.now().difference(pg.at) > const Duration(minutes: 20)) {
      pg = _Pager<yt.Video>();
      yt.VideoSearchList first;
      try {
        first = await _yt.search.search(query, filter: f);
      } catch (e) {
        _log.info('search retry "$query": $e');
        await Future.delayed(const Duration(milliseconds: 800));
        first = await _yt.search.search(query, filter: f);
      }
      pg.list = first;
      pg.pages.add(first.toList());
      _pagers[key] = pg;
      if (_pagers.length > 60) _pagers.remove(_pagers.keys.first);
    }
    while (pg.pages.length < page && pg.list != null) {
      final next = await (pg.list as yt.VideoSearchList).nextPage();
      pg.list = next;
      if (next == null || next.isEmpty) break;
      pg.pages.add(next.toList());
    }
    if (page > pg.pages.length) return [];
    return (pg.pages[page - 1] as List<yt.Video>).map(_brief).toList();
  }

  Future<List<Map<String, dynamic>>> _search(Map<String, String> q) async {
    var query = (q['q'] ?? '').trim();
    final page = int.tryParse(q['page'] ?? '1') ?? 1;
    if (query.isEmpty) return [];
    // разделы «Навигатора» (ct:music и т.п.) — запросами поиска
    if (query.toLowerCase().startsWith('ct:')) return _trending(query.substring(3), page: page);
    if (q['type'] == 'channel') {
      if (page > 1) return [];
      final r = await _yt.search.searchContent(query, filter: yt.TypeFilters.channel);
      return r.whereType<yt.SearchChannel>().map((c) => {
            'type': 'channel',
            'author': c.name,
            'authorId': c.id.value,
            'authorUrl': '/channel/${c.id.value}',
            'authorThumbnails': c.thumbnails.map((t) => {'url': t.url.toString(), 'width': t.width, 'height': t.height}).toList(),
            'subCount': 0,
            'videoCount': c.videoCount,
            'description': c.description,
            'autoGenerated': false,
          }).toList();
    }
    if (q['type'] == 'playlist') return [];
    return _videoSearchPage(query, _filter(q), page);
  }

  // ---------- разделы (у YouTube больше нет «трендов» — собираем поиском) ----------
  static const _sections = {
    '': 'популярное сегодня',
    'default': 'популярное сегодня',
    'music': 'новые клипы',
    'gaming': 'игры обзор',
    'movies': 'трейлер фильма',
    'news': 'новости',
    'live': 'прямой эфир',
    'sport': 'спорт обзор матча',
    'podcasts': 'подкаст',
    'shorts': '#shorts',
  };

  static const _homeQueries = ['популярное сегодня', 'новое видео', 'интересное', 'лучшее за неделю', 'обзор', 'влог'];

  Future<List<Map<String, dynamic>>> _trending(String type, {int page = 1}) async {
    final t = type.toLowerCase();
    if (t == 'home' || t.isEmpty || t == 'default') {
      // вошли в аккаунт YouTube — настоящие рекомендации, как на ТВ
      if (_refresh != null) {
        try {
          final r = await _tvPage('default', page);
          if (r.isNotEmpty || page > 1) return r;
        } catch (e) {
          _log.warning('рекомендации аккаунта: $e');
          if (e is CtYtAuthError) rethrow;
        }
      }
      // «Главная» без сервера: чередуем несколько запросов — лента разнообразнее и не кончается
      final q = _homeQueries[(page - 1) % _homeQueries.length];
      final sub = (page - 1) ~/ _homeQueries.length + 1;
      return _videoSearchPage(q, yt.UploadDateFilter.lastWeek, sub);
    }
    if (t == 'shorts') {
      // Shorts: чередуем запросы, чтобы лента не кончалась; длительность в выдаче часто пустая (0) — пропускаем
      const qs = ['shorts', 'shorts смешные', 'shorts животные', 'shorts музыка', 'shorts спорт', 'shorts лайфхак'];
      // поиск через InnerTube (JSON) — надёжнее HTML-поиска; если запрос не удался — следующий
      for (var k = 0; k < qs.length; k++) {
        final n = page - 1 + k;
        final q = qs[n % qs.length];
        final sub = n ~/ qs.length + 1;
        try {
          final out = await _shortsPage(q, sub);
          if (out.isNotEmpty) return out;
        } catch (e) {
          _log.info('shorts "$q": $e');
        }
      }
      return [];
    }
    final query = _sections[t] ?? t;
    final f = t == 'live'
        ? yt.FeatureFilters.live
        : t == 'shorts'
            ? yt.DurationFilters.short
            : yt.UploadDateFilter.lastWeek;
    final r = await _videoSearchPage(query, f, page);
    return t == 'shorts' ? r.where((v) => (v['lengthSeconds'] as int? ?? 0) <= 90).toList() : r;
  }

  final _shortsPagers = <String, ({List<List<Map<String, dynamic>>> pages, String? next})>{};

  Future<List<Map<String, dynamic>>> _shortsPage(String q, int page) async {
    var pg = _shortsPagers[q];
    if (pg == null || page == 1) {
      final (list, next) = await CtYtFast.searchShorts(q);
      pg = (pages: [list], next: next);
      _shortsPagers[q] = pg;
    }
    while (pg!.pages.length < page && pg.next != null) {
      final (list, next) = await CtYtFast.searchShorts(q, continuation: pg.next);
      pg = (pages: [...pg.pages, list], next: list.isEmpty ? null : next);
      _shortsPagers[q] = pg;
    }
    final r = page <= pg.pages.length ? pg.pages[page - 1] : <Map<String, dynamic>>[];
    return r.where((v) => (v['lengthSeconds'] as int? ?? 0) <= 180).toList();
  }

  // ---------- аккаунт YouTube (вход кодом, как на ТВ) ----------
  final _tvPagers = <String, ({List<List<Map<String, dynamic>>> pages, String? next, DateTime at})>{};
  List<Map<String, dynamic>>? _subsCache;
  DateTime _subsAt = DateTime(2000);

  Future<List<Map<String, dynamic>>> _tvPage(String browseId, int page) async {
    final refresh = _refresh!;
    final key = '$browseId|${refresh.hashCode}';
    var pg = _tvPagers[key];
    if (pg == null || page == 1 && DateTime.now().difference(pg.at) > const Duration(minutes: 3)) {
      final first = await CtYtAccount.browse(refresh, browseId: browseId);
      if (browseId == 'FEsubscriptions' && first.channels.isNotEmpty) {
        _subsCache = first.channels;
        _subsAt = DateTime.now();
      }
      pg = (pages: [first.videos], next: first.continuation, at: DateTime.now());
      _tvPagers[key] = pg;
    }
    while (pg!.pages.length < page && pg.next != null) {
      final more = await CtYtAccount.browse(refresh, continuation: pg.next);
      final fresh = more.videos.where((v) => !pg!.pages.any((l) => l.any((x) => x['videoId'] == v['videoId']))).toList();
      pg = (pages: [...pg.pages, fresh], next: fresh.isEmpty ? null : more.continuation, at: pg.at);
      _tvPagers[key] = pg;
    }
    return page <= pg.pages.length ? pg.pages[page - 1] : [];
  }

  Future<Object?> _auth(String method, List<String> p, Map<String, String> q) async {
    if (_refresh == null) throw _Http(401, 'Войдите в аккаунт YouTube (вкладка «Вы»)');
    final page = int.tryParse(q['page'] ?? '1') ?? 1;
    final what = p.length > 3 ? p[3] : '';
    switch (what) {
      case 'feed':
        return {'notifications': [], 'videos': await _tvPage('FEsubscriptions', page)};
      case 'subscriptions':
        if (p.length >= 5) {
          if (method == 'POST' || method == 'DELETE') {
            await CtYtAccount.subscribe(_refresh!, p[4], method == 'POST');
            _subsCache = null;
            _tvPagers.removeWhere((k, _) => k.startsWith('FEsubscriptions'));
            return {};
          }
          return null;
        }
        if (_subsCache == null || DateTime.now().difference(_subsAt) > const Duration(minutes: 10)) {
          _tvPagers.removeWhere((k, _) => k.startsWith('FEsubscriptions'));
          await _tvPage('FEsubscriptions', 1);
        }
        return _subsCache ?? [];
      case 'history':
        if (method != 'GET') return {};
        return (await _tvPage('FEhistory', page)).map((v) => v['videoId']).toList();
      case 'playlists':
        if (method == 'GET' && p.length == 4) return [];
        throw _Http(405, 'Плейлисты аккаунта YouTube пока недоступны');
      case 'notifications':
      case 'preferences':
        return method == 'GET' ? (what == 'notifications' ? [] : {}) : {};
    }
    return null;
  }

  // ---------- каналы ----------
  Future<Map<String, dynamic>> _channel(String id) async {
    // всё параллельно: шапка канала, описание и последние видео (раньше — по очереди и без видео)
    final aboutF = _yt.channels.getAboutPage(id).timeout(const Duration(seconds: 4));
    final latestF = _channelVideos(id, yt.VideoType.normal, null, null).timeout(const Duration(seconds: 6));
    unawaited(aboutF.then((_) {}, onError: (_) {}));
    unawaited(latestF.then((_) {}, onError: (_) {}));
    final c = await _yt.channels.get(id);
    String desc = '';
    try {
      desc = (await aboutF).description ?? '';
    } catch (_) {}
    var latest = <Map>[];
    try {
      latest = ((await latestF)['videos'] as List).cast<Map>().take(15).toList();
    } catch (_) {}
    return {
      'author': c.title,
      'authorId': c.id.value,
      'authorUrl': '/channel/${c.id.value}',
      'authorBanners': c.bannerUrl.isEmpty
          ? []
          : [
              {'url': c.bannerUrl, 'width': 2560, 'height': 424}
            ],
      'authorThumbnails': [
        {'url': c.logoUrl, 'width': 176, 'height': 176}
      ],
      'subCount': c.subscribersCount ?? 0,
      'totalViews': 0,
      'joined': 0,
      'autoGenerated': false,
      'isFamilyFriendly': true,
      'description': desc,
      'allowedRegions': <String>[],
      'latestVideos': latest,
    };
  }

  Future<Map<String, dynamic>> _channelVideos(String id, yt.VideoType type, String? cont, String? sort) async {
    final page = cont == null || cont.isEmpty ? 1 : int.tryParse(cont.replaceFirst('p', '')) ?? 1;
    final sorting = sort == 'popular' ? yt.VideoSorting.popularity : yt.VideoSorting.newest;
    final key = 'c|$id|${type.name}|${sorting.name}';
    var pg = _pagers[key];
    if (pg == null || DateTime.now().difference(pg.at) > const Duration(minutes: 20)) {
      pg = _Pager<yt.Video>();
      final first = await _yt.channels.getUploadsFromPage(id, videoSorting: sorting, videoType: type);
      pg.list = first;
      pg.pages.add(first.toList());
      _pagers[key] = pg;
    }
    while (pg.pages.length < page && pg.list != null) {
      final next = await (pg.list as yt.ChannelUploadsList).nextPage();
      pg.list = next;
      if (next == null || next.isEmpty) break;
      pg.pages.add(next.toList());
    }
    if (page > pg.pages.length) return {'videos': [], 'continuation': null};
    final vids = (pg.pages[page - 1] as List<yt.Video>).map((v) {
      final m = _brief(v);
      m['author'] = (m['author'] as String).isEmpty ? '' : m['author'];
      return m;
    }).toList();
    final more = pg.list != null && (pg.pages.length > page || (pg.list as List).isNotEmpty);
    return {'videos': vids, 'continuation': more ? 'p${page + 1}' : null};
  }

  // ---------- комментарии ----------


  // ---------- плейлисты ----------
  Future<Map<String, dynamic>> _playlist(String id, int page) async {
    final pl = await _yt.playlists.get(id);
    final vids = await _yt.playlists.getVideos(id).skip((page - 1) * 100).take(100).toList();
    var i = (page - 1) * 100;
    return {
      'type': 'playlist',
      'title': pl.title,
      'playlistId': pl.id.value,
      'author': pl.author,
      'authorId': '',
      'description': pl.description,
      'videoCount': pl.videoCount ?? vids.length,
      'videos': vids.map((v) => _brief(v)..['index'] = i++).toList(),
    };
  }

  String _short(int n) =>
      n >= 1000000 ? '${(n / 1000000).toStringAsFixed(1)}M' : n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : '$n';
}
