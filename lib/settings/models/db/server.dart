import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:logging/logging.dart';

part 'server.freezed.dart';

part 'server.g.dart';

final _log = Logger('Server');

@freezed
sealed class Server with _$Server {
  const factory Server(
      {required String url,
      String? authToken,
      String? sidCookie,
      @JsonKey(includeFromJson: false, includeToJson: false) Duration? ping,
      @JsonKey(includeFromJson: false, includeToJson: false) String? flag,
      @JsonKey(includeFromJson: false, includeToJson: false) String? region,
      @Default({}) Map<String, String> customHeaders,
      @Default(false) bool inUse}) = _Server;

  const Server._();

  /// Заголовки сервера (пароль сайта и т.п.) — только для точно того же адреса: схема, хост и порт.
  /// Раньше сравнивалось начало строки, и https://srv.example совпадал с https://srv.example.evil.com.
  Map<String, String>? headersForUrl(String url) {
    var useHeaders = sameOrigin(url);
    _log.fine('need header for $url ? $useHeaders');
    return useHeaders ? customHeaders : null;
  }

  bool sameOrigin(String url) {
    try {
      final a = Uri.parse(this.url), b = Uri.parse(url);
      if (!b.hasScheme || b.host.isEmpty) return false;
      return a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
          a.host.toLowerCase() == b.host.toLowerCase() &&
          a.port == b.port; // Uri подставляет порт по умолчанию: 443 для https, 80 для http
    } catch (_) {
      return false;
    }
  }

  factory Server.fromJson(Map<String, Object?> json) => _$ServerFromJson(json);
}
