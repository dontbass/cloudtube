import 'package:cloudtube/cloudtube/direct.dart';
import 'package:cloudtube/cloudtube/net.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart';
import 'package:cloudtube/channels/models/channel_sort_by.dart';
import 'package:cloudtube/extensions.dart';
import 'package:cloudtube/globals.dart';
import 'package:cloudtube/playlists/models/playlist.dart';
import 'package:cloudtube/search/models/search_date.dart';
import 'package:cloudtube/search/models/search_duration.dart';
import 'package:cloudtube/search/models/search_results.dart';
import 'package:cloudtube/search/models/search_sort_by.dart';
import 'package:cloudtube/search/models/search_type.dart';
import 'package:cloudtube/settings/models/db/settings.dart';
import 'package:cloudtube/settings/models/errors/cannot_add_server_error.dart';
import 'package:cloudtube/settings/models/errors/invidious_service_error.dart';
import 'package:cloudtube/settings/models/errors/missing_software_key.dart';
import 'package:cloudtube/settings/models/errors/unreacheable_server.dart';
import 'package:cloudtube/utils/video_post_processing.dart';
import 'package:cloudtube/videos/models/db/progress.dart';
import 'package:cloudtube/videos/models/dearrow.dart';
import 'package:cloudtube/videos/models/dislike.dart';
import 'package:cloudtube/videos/models/sponsor_segment.dart';
import 'package:cloudtube/videos/models/user_feed.dart';
import 'package:cloudtube/videos/models/video.dart';
import 'package:logging/logging.dart';

import 'channels/models/channel.dart';
import 'channels/models/channel_playlists.dart';
import 'channels/models/channel_videos.dart';
import 'notifications/models/db/subscription_notifications.dart';
import 'search/models/search_suggestion.dart';
import 'settings/models/db/server.dart';
import 'settings/models/invidious_public_server.dart';
import 'subscription_management/models/subscription.dart';
import 'videos/models/sponsor_segment_types.dart';

part 'service/videos.dart';
part 'service/channels.dart';
part 'service/playlists.dart';
part 'service/account.dart';
part 'service/server.dart';

const urlGetInvidiousPublicServers = 'https://api.invidious.io/instances.json';
const urlGetVideo = '/api/v1/videos/:id';
const urlGetTrending = '/api/v1/trending';
const urlGetPopular = '/api/v1/popular';
const urlGetUserFeed = '/api/v1/auth/feed';
const urlSearchSuggestions = '/api/v1/search/suggestions';
const urlSearch = '/api/v1/search';
const urlStats = '/api/v1/stats';
const urlGetSubscriptions = '/api/v1/auth/subscriptions';
const urlAddDeleteSubscriptions = '/api/v1/auth/subscriptions/:ucid';
const urlGetChannel = '/api/v1/channels/:id';
const urlGetChannelVideos = '/api/v1/channels/:id/videos';
const urlGetChannelStreams = '/api/v1/channels/:id/streams';
const urlGetChannelShorts = '/api/v1/channels/:id/shorts';
const urlGetSponsorSegments =
    'https://sponsor.ajay.app/api/skipSegments?videoID=:id';
const urlGetDeArrow = 'https://sponsor.ajay.app/api/branding?videoID=:id';
const urlGetUserPlaylists = '/api/v1/auth/playlists';
const urlGetUserPlaylist = '/api/v1/auth/playlists/:id';
const urlPostUserPlaylists = '/api/v1/auth/playlists';
const urlGetChannelPlaylists = '/api/v1/channels/:id/playlists';
const urlPostUserPlaylistVideo = '/api/v1/auth/playlists/:id/videos';
const urlDeleteUserPlaylist = '/api/v1/auth/playlists/:id';
const urlDeleteUserPlaylistVideo = '/api/v1/auth/playlists/:id/videos/:index';
const urlGetPublicPlaylist = '/api/v1/playlists/:id';
const urlGetDislikes = 'https://returnyoutubedislikeapi.com/votes?videoId=';
const urlGetClearHistory = '/api/v1/auth/history';
const urlAddDeleteHistory = '/api/v1/auth/history/:id';


const maxPing = 9007199254740991;

/// Основа запросов: клиент, сборка запроса, разбор ответа. Сами запросы — по разделам
/// в lib/service/*.dart (раньше всё было в одном файле на 800 строк).
abstract class ServiceBase {
  final log = Logger('Service');

  final Client httpClient;

  ServiceBase() : httpClient = CtHttpClient(ctHttp);

  /// Вошёл ли пользователь (реализация — в AccountApi; нужна и каналам).
  Future<bool> isLoggedIn();

  String urlFormatForLog(Uri? uri) {
    return kDebugMode ? uri.toString() : '${uri?.replace(host: 'xxxxxxxxxx')}';
  }

  /// Разбор ответа: крупный JSON — в фоновом изоляте. Запись о каждом ответе — уровня fine:
  /// раньше каждый запрос писался в базу журнала (INFO), лишняя запись на диск на каждый ответ.
  Future<dynamic> handleResponse(Response response) async {
    final bytes = response.bodyBytes;
    log.fine(
        "Response from ${response.request?.method} ${urlFormatForLog(response.request?.url)}, status: ${response.statusCode}");

    if (bytes.isNotEmpty) {
      final decoded = await ctJsonDecodeBytes(bytes);
      String? error;
      try {
        Map<String, dynamic> errorFinder = decoded as Map<String, dynamic>;
        error = errorFinder.containsKey('error') ? '${errorFinder['error']}' : null;
      } catch (err) {
        // no error we keep going
      }

      if (error != null) {
        log.severe('Error while calling service: $error');
        throw InvidiousServiceError(error);
      }

      return decoded;
    } else if (response.statusCode < 200 || response.statusCode >= 400) {
      log.severe(
          'Error making request to ${response.request?.url}, \n status: ${response.statusCode}, \n Body: ${response.body}');
      throw InvidiousServiceError(
          'Couldn\'t make request, response code: ${response.statusCode}');
    }
  }

  bool useProxy() {
    if (ctDirectActive) return false; // без сервера проксировать некому
    return db.getSettings(useProxySettingName)?.value == 'true';
  }

  Future<ServerRequest> buildRequest(String baseUrl,
      {Map<String, String>? pathParams,
      Map<String, String?>? query,
      bool authenticated = false,
      bool utf16 = false,
      bool forceJson = false,
      Server? serverOverride}) async {
    try {
      final server = serverOverride ?? (await db.getCurrentlySelectedServer());
      String url = '${(server).url}$baseUrl';

      pathParams?.forEach((key, value) {
        url = url.replaceAll(key, value);
      });

      if (useProxy()) {
        query ??= {};
        query['local'] = 'true';
      }

      List<String> queryStr = [];
      query?.forEach((key, value) {
        if (value != null) {
          queryStr.add('$key=$value');
        }
      });

      if (queryStr.isNotEmpty) {
        url += '?${queryStr.join('&')}';
      }

      var uri = Uri.parse(url);
      log.info('calling ${urlFormatForLog(uri)}');

      final Map<String, String> headers = Map.from(server.customHeaders);

      if (authenticated) {
        headers.addAll(getAuthenticationHeaders(server));
      }

      if (utf16) {
        headers['Content-Type'] = 'application/json; charset=utf-16';
      }

      if (forceJson) {
        headers['Content-Type'] = 'application/json';
      }

      return ServerRequest(uri: uri, headers: headers);
    } catch (err) {
      log.severe('Couldn\'t build url', err);
      rethrow;
    }
  }

  handleErrors(Response response) {}

  Map<String, String> getAuthenticationHeaders(Server s) {
    if (s.authToken != null && s.authToken!.isNotEmpty) {
      log.fine('logged in with token');
      return {'Authorization': 'Bearer ${s.authToken}'};
    } else if (s.sidCookie != null && s.sidCookie!.isNotEmpty) {
      log.fine('logged in with cookie');
      return {'Cookie': s.sidCookie!};
    } else {
      throw InvidiousServiceError(
          'No authentication method provided to access authenticated endpoint');
    }
  }
}

class Service extends ServiceBase with VideoApi, ChannelApi, PlaylistApi, AccountApi, ServerApi {
  Service();
}

class ServerRequest {
  final Uri uri;
  final Map<String, String> headers;

  ServerRequest({required this.uri, required this.headers});
}
