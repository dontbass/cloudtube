part of '../service.dart';

/// Запросы: видео, поиск, тренды, SponsorBlock, DeArrow, дизлайки.
mixin VideoApi on ServiceBase {
  Future<Video> getVideo(String videoId, {Server? serverOverride}) async {
    var req = await buildRequest(urlGetVideo,
        pathParams: {':id': videoId},
        utf16: true,
        serverOverride: serverOverride);
    final response = await httpClient.get(req.uri, headers: req.headers);

    var video = Video.fromJson((await handleResponse(response)) as Map<String, dynamic>);
    video = (await DeArrow.processVideos([video]))[0];
    video = video.copyWith(
        recommendedVideos:
            (await postProcessVideos(video.recommendedVideos)).cast());
    return video;
  }

  Future<List<Video>> getTrending({String? type}) async {
    String countryCode = db.getSettings(browsingCountry)?.value ?? 'US';
    // parse.queryParameters['region'] = countryCode;
    Map<String, String>? query = {'region': countryCode};

    if (type != null) {
      query.putIfAbsent('type', () => type);
    }

    var req = await buildRequest(urlGetTrending, query: query);
    final response = await httpClient.get(req.uri, headers: req.headers);

    final i = (await handleResponse(response)) as List<dynamic>;
    var list = List<Video>.from(i.map((e) => Video.fromJson(e as Map<String, dynamic>)));
    list = (await postProcessVideos(list));
    return list;
  }

  Future<List<Video>> getPopular() async {
    var req = await buildRequest(urlGetPopular);
    final response = await httpClient.get(req.uri, headers: req.headers);
    final i = (await handleResponse(response)) as List<dynamic>;
    var list = List<Video>.from(i.map((e) => Video.fromJson(e as Map<String, dynamic>)));
    list = (await postProcessVideos(list)).cast();
    return list;
  }

  Future<SearchResults> search(String query,
      {SearchType? type,
      int? page,
      SearchSortBy? sortBy,
      SearchDate date = SearchDate.any,
      SearchDuration duration = SearchDuration.any}) async {
    String countryCode = db.getSettings(browsingCountry)?.value ?? 'US';
    final req = await buildRequest(urlSearch, query: {
      'q': Uri.encodeQueryComponent(query),
      'type': type?.name,
      'page': page?.toString() ?? '1',
      'sort': sortBy?.name,
      'region': countryCode,
      'date': date != SearchDate.any ? date.name : null,
      'duration': duration != SearchDuration.any ? duration.name : null,
    });
    final response = await httpClient.get(req.uri, headers: req.headers);
    final i = (await handleResponse(response)) as List<dynamic>;
    // only getting videos for now
    SearchResults results = SearchResults();
    try {
      for (var e in i) {
        switch (e['type']) {
          case 'video':
            results.videos.add(Video.fromJson(e as Map<String, dynamic>));
            break;
          case 'playlist':
            results.playlists.add(Playlist.fromJson(e as Map<String, dynamic>));
            break;
          case 'channel':
            results.channels.add(Channel.fromJson(e as Map<String, dynamic>));
        }
      }
    } catch (err) {
      log.info((err as Error).stackTrace?.toString());
      rethrow;
    }
    log.info(results);

    results.videos = (await postProcessVideos(results.videos)).cast();
    return results;
  }

  /// Фрагменты SponsorBlock. 404 у SponsorBlock значит «фрагментов нет».
  /// Сетевые ошибки пробрасываются — вызывающий пишет их в журнал (раньше молча было «нет фрагментов»).
  Future<List<CtSponsorSeg>> getSponsorSegments(String videoId, List<SponsorSegmentType> categories) async {
    var url = urlGetSponsorSegments.replaceAll(':id', videoId);
    if (categories.isNotEmpty) {
      url += '&categories=${Uri.encodeQueryComponent('[${categories.map((e) => '"${e.segmentName}"').join(',')}]')}';
    }
    final response = await httpClient.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (response.statusCode == 404) return const [];
    if (response.statusCode != 200) throw 'SponsorBlock ответил ${response.statusCode}';
    return CtSponsorSkipper.parse(jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>);
  }


  Future<DeArrow?> getDeArrow(String videoId) async {
    try {
      String url = urlGetDeArrow.replaceAll(":id", videoId);

      log.fine("calling $url");
      final response = await httpClient.get((Uri.parse(url)));
      var body = utf8.decode(response.bodyBytes);
      var deArrow = DeArrow.fromJson(jsonDecode(body) as Map<String, dynamic>);
      deArrow.videoId = videoId;
      return deArrow;
    } catch (err) {
      return null;
    }
  }

  Future<bool> testDeArrowThumbnail(String? url) async {
    if (url != null) {
      final response = await httpClient.head(Uri.parse(url));
      log.fine("calling $url => ${response.statusCode}");
      return response.statusCode == 200;
    } else {
      return false;
    }
  }

  Future<SearchSuggestion> getSearchSuggestion(String query) async {
    if (query.isEmpty) return SearchSuggestion(query, []);
    var request = await buildRequest(urlSearchSuggestions,
        query: {"q": Uri.encodeQueryComponent(query)});
    final response =
        await httpClient.get(request.uri, headers: request.headers);
    SearchSuggestion search =
        SearchSuggestion.fromJson((await handleResponse(response)) as Map<String, dynamic>);
    if (search.suggestions.any((element) => element.contains(";"))) {
      search.suggestions = search.suggestions
          .map((s) => s.replaceAll(" ", "&#32;").replaceAllMapped(
              RegExp(r"&#\w*;"),
              (m) => String.fromCharCode(
                  int.parse(m[0]!.replaceAll(RegExp(r"&#|;"), "")))))
          .toList();
    }

    return search;
  }

  Future<Dislike> getDislikes(String videoId) async {
    final customUrl =
        db.getSettings(returnYoutubeDislikeUrlSettingName)?.value ?? '';

    Uri uri = Uri.parse((customUrl.trim().isNotEmpty
            ? '${customUrl}votes?videoId='
            : urlGetDislikes) +
        videoId);

    final response = await httpClient.get(uri);
    return Dislike.fromJson((await handleResponse(response)) as Map<String, dynamic>);
  }
}
