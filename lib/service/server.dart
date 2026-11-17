part of '../service.dart';

/// Запросы: проверка и выбор сервера.
mixin ServerApi on ServiceBase {
  Future<void> validateServer(
      String serverUrl, Map<String, String>? headers) async {
    try {
      String url = serverUrl + urlStats;
      log.info('Calling $url');
      final response = await httpClient.get(Uri.parse(url), headers: headers);
      final json = (await handleResponse(response)) as Map<String, dynamic>;

      if (json.containsKey("software") &&
          json['software']['name'] == 'invidious') {
        return;
      } else {
        throw MissingSoftwareKeyError(jsonEncode(json));
      }
    } catch (err) {
      if (err is InvidiousServiceError) {
        throw UnreachableServerError(error: err.message);
      } else if (err is CannotAddServerError) {
        rethrow;
      } else {
        throw CannotAddServerError(error: err.toString());
      }
    }
  }

  Future<Duration?> pingServer(String url) async {
    int start = DateTime.now().millisecondsSinceEpoch;
    String fullUri = '$url$urlStats';
    log.fine('ping $fullUri');
    final response = await httpClient.get(Uri.parse(fullUri),
        headers: {'Content-Type': 'application/json; charset=utf-16'});

    try {
      await handleResponse(response);
      var diff = DateTime.now().millisecondsSinceEpoch - start;
      return Duration(milliseconds: diff);
    } catch (err, stacktrace) {
      log.severe('couldn;t ping $url', err, stacktrace);
      return null;
    }
  }

  Future<List<InvidiousPublicServer>> getPublicServers() async {
    final response =
        await httpClient.get(Uri.parse(urlGetInvidiousPublicServers));
    List<InvidiousPublicServer> servers = [];
    final i = (await handleResponse(response)) as List<dynamic>;

    for (var element in i) {
      Iterable s = element as Iterable;
      if (s.length == 2) {
        servers.add(InvidiousPublicServer.fromJson(
            s.toList()[1] as Map<String, dynamic>));
      }
    }

    return servers
        .where((s) => (s.api ?? false) && (s.stats?.openRegistrations ?? false))
        .toList();
  }
}
