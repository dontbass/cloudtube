import '../../cloudtube/direct.dart' show ctDirectStreamHeaders, ctDirectActive;
import '../../cloudtube/hls_local.dart';
import '../../videos/models/format_stream.dart';

/// Откуда играем.
enum CtStreamKind {
  /// ТВ без сервера: свой DASH с одним качеством (как в SmartTube).
  ownDash,

  /// ТВ без сервера: HLS, оставлен один вариант качества.
  hlsSingle,

  /// HLS как есть (телефон без сервера).
  hls,

  /// DASH сервера Invidious.
  serverDash,

  /// Обычный поток (видео со звуком одним файлом), с выбором разрешения.
  progressive,
}

/// Что попросили сыграть.
class CtStreamRequest {
  final String videoId;
  final String? hlsUrl;
  final String? dashUrl;
  final List<FormatStream> formatStreams;

  /// Адрес выбранного сервера.
  final String serverUrl;

  /// Заголовки сервера (Basic Auth и т.п.) для адреса — только для своего же сервера.
  final Map<String, String>? Function(String url) serverHeaders;

  final bool useProxy;
  final bool useServerDash;

  /// Выбирать одно качество самим (свой DASH): без сервера — всегда, со своим сервером —
  /// для обычных (не прямых) трансляций.
  final bool tvDirect;

  /// Свой DASH для этого ролика уже давал сбой — сразу HLS.
  final bool noOwnDash;

  /// Запасной HLS с одним качеством (только без сервера: HLS сервера — это трансляции).
  final bool hlsSingle;

  /// Потолок качества и формат, выбранный в меню.
  final int cap;
  final String? itag;

  const CtStreamRequest({
    required this.videoId,
    required this.hlsUrl,
    required this.dashUrl,
    required this.formatStreams,
    required this.serverUrl,
    required this.serverHeaders,
    this.useProxy = false,
    this.useServerDash = false,
    this.tvDirect = false,
    this.noOwnDash = false,
    this.hlsSingle = true,
    this.cap = 2160,
    this.itag,
  });
}

/// Что выбрано.
class CtStreamChoice {
  final CtStreamKind kind;
  final String url;
  final Map<String, String> headers;

  /// Высота кадра, если качество выбрано нами (свой DASH / HLS с одним вариантом).
  final int? height;
  final String? itag;

  /// Подпись качества для панели плеера.
  final String? qualityLabel;

  /// Разрешения обычного потока (подпись → адрес) и текущее.
  final Map<String, String> resolutions;
  final String? progressiveResolution;

  const CtStreamChoice({
    required this.kind,
    required this.url,
    required this.headers,
    this.height,
    this.itag,
    this.qualityLabel,
    this.resolutions = const {},
    this.progressiveResolution,
  });

  /// Качество выбрали мы — ExoPlayer не может уйти на низкое.
  bool get fixedQuality => kind == CtStreamKind.ownDash || kind == CtStreamKind.hlsSingle;

  String get trace => switch (kind) {
        CtStreamKind.ownDash => 'плеер: DASH ${height}p (одно качество)',
        CtStreamKind.hlsSingle => 'плеер: HLS ${height}p (одно качество)',
        CtStreamKind.hls => 'плеер: HLS',
        CtStreamKind.serverDash => 'плеер: DASH сервера',
        CtStreamKind.progressive => 'плеер: обычный поток ${progressiveResolution ?? ''}',
      };
}

final _googleCdn = RegExp(r'https://(.+)googlevideo.com/');

/// Выбор потока — раньше было внутри 250-строчного метода плеера.
Future<CtStreamChoice> ctPickStream(CtStreamRequest r) async {
  final isHls = r.hlsUrl != null;
  final progressive = isHls || r.formatStreams.isEmpty ? null : r.formatStreams.last;
  final proxy = r.useProxy ? '?local=true' : '';

  var url = isHls
      ? '${r.hlsUrl}$proxy'
      : r.useServerDash
          ? '${r.dashUrl}$proxy'
          : progressive?.url ?? '';
  // Invidious присылает адрес Google даже при проксировании обычного потока
  if (!r.useServerDash && r.useProxy) url = url.replaceFirst(_googleCdn, '${r.serverUrl}/');
  final headers = <String, String>{...?r.serverHeaders(url), ...ctDirectStreamHeaders(url)};

  if (r.tvDirect && !r.noOwnDash) {
    final d = await CtDashLocal.build(r.videoId, cap: r.cap, itag: r.itag);
    if (d != null) {
      final f = CtDashLocal.formats(r.videoId).where((f) => '${f['itag']}' == d.$4).firstOrNull;
      return CtStreamChoice(
        kind: CtStreamKind.ownDash,
        url: d.$1,
        // свой DASH: заголовки для самих потоков (YouTube — клиент, свой сервер — пароль сайта)
        headers: {...?r.serverHeaders(d.$3), ...ctDirectStreamHeaders(d.$3)},
        height: d.$2,
        itag: d.$4,
        qualityLabel: f != null ? CtDashLocal.label(f).replaceAll(', ', ' · ') : '${d.$2}p',
      );
    }
  }
  if (r.tvDirect && isHls && r.hlsSingle) {
    final local = await CtHlsLocal.single(url, headers, cap: r.cap, videoId: r.videoId);
    if (local != null) {
      return CtStreamChoice(
          kind: CtStreamKind.hlsSingle, url: local.$1, headers: headers, height: local.$2, qualityLabel: '${local.$2}p');
    }
  }
  if (isHls) {
    // несколько звуковых дорожек — плееру только выбранная (по умолчанию оригинал)
    // (только YouTube напрямую: трансляции своего сервера с одной дорожкой не ждут лишний запрос)
    final a = ctDirectActive ? await CtHlsLocal.audioFiltered(r.videoId, url, headers) : null;
    return CtStreamChoice(kind: CtStreamKind.hls, url: a ?? url, headers: headers);
  }
  if (r.useServerDash) return CtStreamChoice(kind: CtStreamKind.serverDash, url: url, headers: headers);
  return CtStreamChoice(
    kind: CtStreamKind.progressive,
    url: url,
    headers: headers,
    qualityLabel: progressive?.resolution,
    progressiveResolution: progressive?.resolution,
    resolutions: {for (final f in r.formatStreams) f.qualityLabel: f.url},
  );
}
