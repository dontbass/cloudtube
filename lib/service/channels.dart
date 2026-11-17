part of '../service.dart';

/// Запросы: каналы и подписки.
mixin ChannelApi on ServiceBase {
  Future<bool> subscribe(String channelId) async {
    if (!await isLoggedIn()) return false;
    final req = await buildRequest(urlAddDeleteSubscriptions,
        pathParams: {":ucid": channelId}, authenticated: true);

    final response = await httpClient.post(req.uri, headers: req.headers);
    log.info('${response.statusCode} - ${response.body}');

    if (response.statusCode == 204 || response.statusCode == 403) {
      return response.statusCode == 204;
    } else {
      throw InvidiousServiceError("Couldn't subscribe to channel");
    }
  }

  Future<bool> unSubscribe(String channelId) async {
    if (!await isLoggedIn()) return false;

    final req = await buildRequest(urlAddDeleteSubscriptions,
        pathParams: {":ucid": channelId}, authenticated: true);

    final response = await httpClient.delete(req.uri, headers: req.headers);
    log.info('${response.statusCode} - ${response.body}');

    if (response.statusCode == 204 || response.statusCode == 403) {
      return response.statusCode == 204;
    } else {
      throw InvidiousServiceError("Couldn't subscribe to channel");
    }
  }

  Future<bool> isSubscribedToChannel(String channelId) async {
    if (!await isLoggedIn()) return false;

    return (await getSubscriptions())
            .indexWhere((element) => element.authorId == channelId) >
        -1;
  }

  Future<List<Subscription>> getSubscriptions() async {
    if (!await isLoggedIn()) return [];

    var req = await buildRequest(urlGetSubscriptions, authenticated: true);

    final response = await httpClient.get(req.uri, headers: req.headers);
    final i = (await handleResponse(response)) as List<dynamic>;

    return List<Subscription>.from(i.map((e) => Subscription.fromJson(e as Map<String, dynamic>)));
  }

  Future<Channel> getChannel(String channelId) async {
    // sometimes the api gives the channel with /channel/<channelid> format
    channelId = channelId.replaceAll("/channel/", '');
    var req = await buildRequest(urlGetChannel,
        pathParams: {':id': channelId}, utf16: true);

    final response = await httpClient.get(req.uri, headers: req.headers);

    var channel = Channel.fromJson((await handleResponse(response)) as Map<String, dynamic>);
    channel.latestVideos =
        (await postProcessVideos(channel.latestVideos ?? [])).cast();

    if (channel.latestVideos != null && channel.latestVideos!.isNotEmpty) {
      await fileDb.setChannelNotificationLastViewedVideo(
          channel.authorUrl, channel.latestVideos![0].videoId);
    }
    return channel;
  }

  Future<VideosWithContinuation> getChannelVideos(
      String channelId, String? continuation,
      {bool saveLastSeen = true,
      ChannelSortBy sortBy = ChannelSortBy.newest}) async {
    final req = await buildRequest(urlGetChannelVideos,
        pathParams: {':id': channelId},
        query: {
          'continuation': continuation,
          'sort_by': sortBy.name,
        },
        utf16: true);
    final response = await httpClient.get(req.uri, headers: req.headers);

    var videosWithContinuation =
        VideosWithContinuation.fromJson((await handleResponse(response)) as Map<String, dynamic>);
    videosWithContinuation.videos =
        (await postProcessVideos(videosWithContinuation.videos)).cast();

    if (saveLastSeen && videosWithContinuation.videos.isNotEmpty) {
      await fileDb.setChannelNotificationLastViewedVideo(
          channelId, videosWithContinuation.videos.first.videoId);
    }
    return videosWithContinuation;
  }

  Future<VideosWithContinuation> getChannelStreams(
      String channelId, String? continuation) async {
    final req = await buildRequest(urlGetChannelStreams,
        pathParams: {':id': channelId},
        query: {'continuation': continuation},
        utf16: true);
    final response = await httpClient.get(req.uri, headers: req.headers);

    var videosWithContinuation =
        VideosWithContinuation.fromJson((await handleResponse(response)) as Map<String, dynamic>);
    videosWithContinuation.videos =
        (await postProcessVideos(videosWithContinuation.videos)).cast();
    return videosWithContinuation;
  }

  Future<VideosWithContinuation> getChannelShorts(
      String channelId, String? continuation) async {
    final req = await buildRequest(urlGetChannelShorts,
        pathParams: {':id': channelId},
        query: {'continuation': continuation},
        utf16: true);
    final response = await httpClient.get(req.uri, headers: req.headers);

    var videosWithContinuation =
        VideosWithContinuation.fromJson((await handleResponse(response)) as Map<String, dynamic>);
    videosWithContinuation.videos =
        (await postProcessVideos(videosWithContinuation.videos)).cast();
    return videosWithContinuation;
  }

  Future<ChannelPlaylists> getChannelPlaylists(String channelId,
      {String? continuation}) async {
    final req = await buildRequest(urlGetChannelPlaylists,
        pathParams: {':id': channelId}, query: {'continuation': continuation});

    final response = await httpClient.get(req.uri, headers: req.headers);
    var channelPlaylists = ChannelPlaylists.fromJson((await handleResponse(response)) as Map<String, dynamic>);
    for (int i = 0; i < channelPlaylists.playlists.length; i++) {
      var pl = channelPlaylists.playlists[i];
      pl = pl.copyWith(videos: await postProcessVideos(pl.videos));
      channelPlaylists.playlists[i] = pl;
    }
    return channelPlaylists;
  }
}
