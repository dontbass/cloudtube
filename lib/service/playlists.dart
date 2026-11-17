part of '../service.dart';

/// Запросы: плейлисты.
mixin PlaylistApi on ServiceBase {
  Future<List<Playlist>> getUserPlaylists({bool postProcessing = true}) async {
    try {
      var req = await buildRequest(urlGetUserPlaylists, authenticated: true);

      final response = await httpClient.get(req.uri, headers: req.headers);
      final i = (await handleResponse(response)) as List<dynamic>;
      var list = List<Playlist>.from(i.map((e) => Playlist.fromJson(e as Map<String, dynamic>)));
      if (postProcessing) {
        for (int i = 0; i < list.length; i++) {
          var pl = list[i];
          pl = pl.copyWith(videos: await postProcessVideos(pl.videos));
          list[i] = pl;
        }
      }
      return list.sortByReversed((e) => e.updated ?? 0).toList();
    } catch (e) {
      return [];
    }
  }

  Future<String?> createPlayList(String name, String type) async {
    var req = await buildRequest(urlPostUserPlaylists,
        authenticated: true, forceJson: true);

    Map<String, String> body = {
      'title': name,
      'privacy': type,
    };

    log.info(jsonEncode(body));

    final response = await httpClient.post(req.uri,
        headers: req.headers, body: jsonEncode(body));
    final playlist = (await handleResponse(response)) as Map<String, dynamic>;
    return playlist['playlistId'] as String;
  }

  Future<void> addVideoToPlaylist(String playListId, String videoId) async {
    var req = await buildRequest(urlPostUserPlaylistVideo,
        pathParams: {":id": playListId}, authenticated: true, forceJson: true);

    Map<String, String> body = {
      'videoId': videoId,
    };

    final response = await httpClient.post(req.uri,
        headers: req.headers, body: jsonEncode(body));
    await handleResponse(response);
  }

  Future<void> deleteUserPlaylist(String playListId) async {
    var req = await buildRequest(urlDeleteUserPlaylist,
        pathParams: {":id": playListId}, authenticated: true, forceJson: true);

    final response = await httpClient.delete(req.uri, headers: req.headers);
    await handleResponse(response);
  }

  Future<void> deleteUserPlaylistVideo(
      String playListId, String indexId) async {
    final req = await buildRequest(urlDeleteUserPlaylistVideo,
        pathParams: {':id': playListId, ':index': indexId},
        authenticated: true,
        forceJson: true);

    final response = await httpClient.delete(req.uri, headers: req.headers);
    await handleResponse(response);
  }

  Future<Playlist> getPublicPlaylists(String playlistId,
      {int? page, bool saveLastSeen = true}) async {
    final req = await buildRequest(urlGetPublicPlaylist,
        pathParams: {':id': playlistId}, query: {'page': page?.toString()});

    final response = await httpClient.get(req.uri, headers: req.headers);
    var playlist = Playlist.fromJson((await handleResponse(response)) as Map<String, dynamic>);
    var oldLength = playlist.videos.length;
    playlist = playlist.copyWith(
        videos: await postProcessVideos(playlist.videos),
        removedByFilter: oldLength - playlist.videos.length);

    if (saveLastSeen) {
      await fileDb.setPlaylistNotificationLastViewedVideo(
          playlist.playlistId, playlist.videoCount);
    }

    return playlist;
  }

  Future<Playlist> getUserPlaylist(String playlistId) async {
    final req = await buildRequest(urlGetUserPlaylist,
        pathParams: {':id': playlistId}, authenticated: true);

    final response = await httpClient.get(req.uri, headers: req.headers);
    var playlist = Playlist.fromJson((await handleResponse(response)) as Map<String, dynamic>);
    var oldLength = playlist.videos.length;
    playlist = playlist.copyWith(
        videos: await postProcessVideos(playlist.videos),
        removedByFilter: oldLength - playlist.videos.length);

    return playlist;
  }
}
