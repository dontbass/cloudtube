part of '../service.dart';

/// Запросы: вход, лента подписок, история.
mixin AccountApi on ServiceBase {
  Future<String> loginWithCookies(
      String serverUrl, String username, String password,
      {Map<String, String>? headers}) async {
    try {
      String url = '$serverUrl/login?type=invidious';
      var map = {'email': username, 'password': password};

      final response =
          await httpClient.post(Uri.parse(url), body: map, headers: headers);
      if (response.statusCode == 302 &&
          response.headers.containsKey('set-cookie')) {
        // we have a cookie to parse
        return response.headers['set-cookie']!
            .split(';')
            .firstWhere((element) => element.startsWith('SID='));
      } else {
        throw InvidiousServiceError(
            'wrong error code (${response.statusCode}) or no cookie headers: ${response.headers['set-cookie']}');
      }
    } catch (err, stacktrace) {
      if (err is InvidiousServiceError) {
        log.severe('Failed to log in with cookies: \n ${err.message}', err,
            stacktrace);
      }
      throw InvidiousServiceError('Wrong username or password');
    }
  }

  Future<String?> logIn(String serverUrl) async {
    String url =
        '$serverUrl/authorize_token?scopes=:feed,:subscriptions*,:playlists*,:history*&callback_url=clipious-auth://';
    final result = await FlutterWebAuth2.authenticate(
        url: url, callbackUrlScheme: 'clipious-auth');

    final token = Uri.parse(result).queryParameters['token'];

    Server? server = db.getServer(serverUrl);

    if (server != null) {
      server = server.copyWith(authToken: Uri.decodeComponent(token ?? ''));

      await db.upsertServer(server);

      return server.authToken;
    } else {
      throw InvidiousServiceError('logging in to deleted server');
    }
  }

  Future<UserFeed> getUserFeed(
      {int? maxResults, int? page, bool saveLastSeen = true}) async {
    // for background service to be able to use
    final req = await buildRequest(urlGetUserFeed,
        query: {
          'max_results': maxResults?.toString(),
          'page': page?.toString()
        },
        authenticated: true);

    final response = await httpClient.get(req.uri, headers: req.headers);
    var feed = UserFeed.fromJson((await handleResponse(response)) as Map<String, dynamic>);
    feed.videos = (await postProcessVideos(feed.videos ?? [])).cast();
    feed.notifications =
        (await postProcessVideos(feed.notifications ?? [])).cast();

    // we only save the last video seen if we're on the first page otherwise it does not make sense
    if (saveLastSeen && (page ?? 1) == 1) {
      final videos = List<Video>.from(feed.notifications ?? <Video>[], growable: true);
      videos.addAll(feed.videos ?? []);
      if (videos.isNotEmpty) {
        var toSave = SubscriptionNotification(
            videos.first.videoId, DateTime.now().millisecondsSinceEpoch);
        await fileDb.setLastSubscriptionNotification(toSave);
      }
    }

    return feed;
  }

  Future<bool> isLoggedIn() async {
    return await db.isLoggedInToCurrentServer();
  }

  Future<List<String>> getUserHistory(int page, int maxResults) async {
    final req = await buildRequest(urlGetClearHistory,
        query: {'page': page.toString(), 'max_results': maxResults.toString()},
        authenticated: true,
        forceJson: true);

    final response = await httpClient.get(req.uri, headers: req.headers);
    final i = (await handleResponse(response)) as List<dynamic>;

    return List<String>.from(i.map((e) => e as String));
  }

  void syncHistory() async {
    try {
      if (await db.isLoggedInToCurrentServer()) {
        (await getUserHistory(1, 200))
            .where((element) => db.getVideoProgress(element) == 0)
            .forEach((element) async {
          await db.saveProgress(Progress.named(progress: 1, videoId: element));
          log.fine('updated watch status of $element');
        });
      }
    } catch (err) {
      log.fine('failed to sync history, probably not logged in');
    }
  }

  Future<void> clearUserHistory() async {
    var req = await buildRequest(urlGetClearHistory,
        authenticated: true, forceJson: true);

    final response = await httpClient.delete(req.uri, headers: req.headers);
    await handleResponse(response);
  }

  Future<void> deleteFromUserHistory(String videoId) async {
    var req = await buildRequest(urlAddDeleteHistory,
        pathParams: {':id': videoId}, authenticated: true, forceJson: true);
    final response = await httpClient.delete(req.uri, headers: req.headers);
    await handleResponse(response);
  }

  Future<void> addToUserHistory(String videoId) async {
    var req = await buildRequest(urlAddDeleteHistory,
        pathParams: {':id': videoId}, authenticated: true, forceJson: true);

    final response = await httpClient.post(req.uri, headers: req.headers);
    await handleResponse(response);
  }
}
