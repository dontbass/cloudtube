import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

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
      body = await _CtDirect.instance.handle(request.method, request.url);
      if (body == null) code = 404;
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
  final _comments = <String, yt.Comment>{};

  Future<Object?> handle(String method, Uri u) async {
    final p = u.pathSegments;
    final q = u.queryParameters;
    if (method != 'GET') throw _Http(405, 'Без сервера это действие недоступно');
    if (p.length < 3 || p[0] != 'api' || p[1] != 'v1') return null;
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
        if (p.length >= 4) return _commentsFor(p[3], q['continuation']);
        return null;
      case 'playlists':
        if (p.length >= 4) return _playlist(p[3], int.tryParse(q['page'] ?? '1') ?? 1);
        return null;
      case 'auth':
        throw _Http(403, 'Без сервера аккаунт недоступен — подписки и история хранятся на устройстве');
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
  Future<Map<String, dynamic>> _video(String id) async {
    final hit = _videoCache[id];
    if (hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 30)) return hit.$2;
    final vFut = _yt.videos.get(id);
    final mFut = _manifest(id);
    final v = await vFut;
    final j = _brief(v);
    j['likeCount'] = v.engagement.likeCount ?? 0;
    j['keywords'] = v.keywords.toList();
    j['descriptionHtml'] = const HtmlEscape().convert(v.description).replaceAll('\n', '<br>');
    j['allowRatings'] = true;
    j['isListed'] = true;
    // канал и рекомендации — параллельно и с ограничением по времени, чтобы не задерживать запуск видео
    final chFut = _yt.channels.get(v.channelId).timeout(const Duration(seconds: 4));
    final relFut = _yt.videos.getRelatedVideos(v).timeout(const Duration(seconds: 5));
    try {
      final ch = await chFut;
      j['authorThumbnails'] = [
        {'url': ch.logoUrl, 'width': 176, 'height': 176},
      ];
      if (ch.subscribersCount != null) j['subCountText'] = _short(ch.subscribersCount!);
    } catch (_) {}
    try {
      final rel = await relFut;
      j['recommendedVideos'] = (rel ?? const <yt.Video>[]).map<Map<String, dynamic>>((e) => _brief(e)).toList();
    } catch (_) {
      j['recommendedVideos'] = [];
    }
    try {
      final m = await mFut;
      // HLS (от клиента iOS): одна ссылка на поток со звуком, ExoPlayer и mpv играют её сразу
      final hls = m.hls.whereType<yt.HlsMuxedStreamInfo>().toList()
        ..sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));
      final pick = hls.where((s) => s.videoResolution.height <= 1080).firstOrNull ?? hls.firstOrNull;
      if (pick != null) j['hlsUrl'] = pick.url.toString();
      j['formatStreams'] = m.muxed
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
      j['adaptiveFormats'] = [
        ...m.videoOnly.map((s) => {
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
        ...m.audioOnly.map((s) => {
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
    } catch (e) {
      _log.warning('streams $id: $e');
      j['formatStreams'] = [];
      j['adaptiveFormats'] = [];
    }
    _videoCache[id] = (DateTime.now(), j);
    if (_videoCache.length > 80) _videoCache.remove(_videoCache.keys.first);
    return j;
  }

  Future<yt.StreamManifest> _manifest(String id) async {
    // Нужен HLS (один поток со звуком, все качества): сначала iOS, затем Safari (WEB).
    // Если YouTube ни одному не дал HLS — стандартный набор (отдельные видео/звук + 360p со звуком).
    for (final c in [yt.YoutubeApiClient.ios, yt.YoutubeApiClient.safari]) {
      try {
        final m = await _yt.videos.streams.getManifest(id, ytClients: [c]).timeout(const Duration(seconds: 6));
        if (m.hls.isNotEmpty) return m;
      } catch (e) {
        _log.fine('manifest ${c.payload['context']?['client']?['clientName']}: $e');
      }
    }
    return _yt.videos.streams.getManifest(id);
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
      // «Главная» без сервера: чередуем несколько запросов — лента разнообразнее и не кончается
      final q = _homeQueries[(page - 1) % _homeQueries.length];
      final sub = (page - 1) ~/ _homeQueries.length + 1;
      return _videoSearchPage(q, yt.UploadDateFilter.lastWeek, sub);
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

  // ---------- каналы ----------
  Future<Map<String, dynamic>> _channel(String id) async {
    final c = await _yt.channels.get(id);
    String desc = '';
    try {
      desc = (await _yt.channels.getAboutPage(id)).description ?? '';
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
      'latestVideos': <Map>[],
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
  Future<Map<String, dynamic>> _commentsFor(String id, String? cont) async {
    List<yt.Comment> items;
    dynamic list;
    String key;
    if (cont != null && cont.startsWith('r:')) {
      // ответы на комментарий
      final c = _comments[cont.substring(2)];
      if (c == null) return {'comments': [], 'continuation': null};
      list = await _yt.videos.commentsClient.getReplies(c);
      items = list == null ? [] : (list as List<yt.Comment>).toList();
      key = 'cr|${cont.substring(2)}';
      _pagers[key] = _Pager<yt.Comment>()..list = list;
    } else if (cont != null && cont.startsWith('n:')) {
      key = cont.substring(2);
      final pg = _pagers[key];
      if (pg == null || pg.list == null) return {'comments': [], 'continuation': null};
      list = await (pg.list as yt.CommentsList).nextPage();
      pg.list = list;
      items = list == null ? [] : (list as List<yt.Comment>).toList();
    } else {
      final v = await _yt.videos.get(id);
      list = await _yt.videos.commentsClient.getComments(v);
      items = list == null ? [] : (list as List<yt.Comment>).toList();
      key = 'cm|$id|${DateTime.now().millisecondsSinceEpoch}';
      _pagers[key] = _Pager<yt.Comment>()..list = list;
    }
    final out = <Map<String, dynamic>>[];
    for (final c in items) {
      final cid = '${id}_${_comments.length}';
      _comments[cid] = c;
      out.add({
        'author': c.author,
        'authorId': c.channelId.value,
        'authorUrl': '/channel/${c.channelId.value}',
        'authorThumbnails': <Map>[],
        'content': c.text,
        'contentHtml': const HtmlEscape().convert(c.text),
        'published': 0,
        'publishedText': c.publishedTime,
        'likeCount': c.likeCount,
        'commentId': cid,
        'isEdited': false,
        'creatorHeart': c.isHearted ? {} : null,
        if (c.replyCount > 0) 'replies': {'replyCount': c.replyCount, 'continuation': 'r:$cid'},
      });
    }
    if (_comments.length > 3000) _comments.clear();
    final total = list is yt.CommentsList ? list.totalLength : out.length;
    final hasMore = list is yt.CommentsList && out.isNotEmpty && !key.startsWith('cr|');
    return {
      'videoId': id,
      'commentCount': total,
      'comments': out,
      'continuation': hasMore ? 'n:$key' : null,
    };
  }

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
