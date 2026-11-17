import 'server_caps.dart';
import 'direct.dart';
import '../utils/models/image_object.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:clipious/globals.dart';
import 'package:clipious/settings/models/db/server.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

final _log = Logger('CtAvatars');

/// Аватарки каналов пачками с сервера CloudTube: GET /ct-api/avatars?ids=UC..,UC..
/// Ответ: {"UC...": "/ggpht/..."}. Кэш в памяти на время работы приложения.
class CtAvatars {
  CtAvatars._();

  static final CtAvatars instance = CtAvatars._();

  final Map<String, String?> _cache = {};
  final Map<String, Completer<String?>> _waiting = {};
  final Set<String> _queue = {};
  Timer? _timer;

  /// [slow] — можно взять картинку по одному каналу (без дополнений сервера).
  /// Только для коротких списков (ряд подписок на ТВ): в лентах это сотни запросов
  /// к YouTube — тормоза и ограничение по IP (так было в 1.1.60–1.1.63).
  Future<String?> get(String channelId, {bool slow = false}) {
    if (channelId.isEmpty) return Future.value(null);
    if (_cache.containsKey(channelId) && (_cache[channelId] != null || !slow)) {
      return Future.value(_cache[channelId]);
    }
    final c = _waiting.putIfAbsent(channelId, () => Completer<String?>());
    if (slow) {
      _slowQueue.add(channelId);
      _pumpSlow();
    } else {
      _queue.add(channelId);
      _timer ??= Timer(const Duration(milliseconds: 150), _flush);
    }
    return c.future;
  }

  void _done(String id, String? url) {
    _cache[id] = url;
    _waiting.remove(id)?.complete(url);
  }

  // ---------- медленный путь: по одному каналу, не больше 2 запросов сразу ----------
  static final _yt = yt.YoutubeExplode();
  final List<String> _slowQueue = [];
  int _slowRunning = 0;
  int _slowFails = 0;

  void _pumpSlow() {
    while (_slowRunning < 2 && _slowQueue.isNotEmpty) {
      final id = _slowQueue.removeAt(0);
      // 3 ошибки подряд — YouTube/сервер не отвечает, больше не дёргаем до перезапуска
      if (_slowFails >= 3) {
        _done(id, null);
        continue;
      }
      _slowRunning++;
      unawaited(_slowOne(id).whenComplete(() {
        _slowRunning--;
        _pumpSlow();
      }));
    }
  }

  Future<void> _slowOne(String id) async {
    String? url;
    try {
      if (ctDirectActive) {
        url = (await _yt.channels.get(id).timeout(const Duration(seconds: 8))).logoUrl;
      } else {
        final c = await service.getChannel(id).timeout(const Duration(seconds: 8));
        url = ImageObject.getBestThumbnail(c.authorThumbnails)?.url;
      }
      _slowFails = 0;
    } catch (e) {
      _slowFails++;
      _log.fine('avatar $id: $e');
    }
    _done(id, url);
  }

  // ---------- быстрый путь: пачкой с сервера CloudTube (если есть дополнения) ----------
  Future<void> _flush() async {
    _timer = null;
    final ids = _queue.take(40).toList();
    _queue.removeAll(ids);
    if (_queue.isNotEmpty) _timer = Timer(const Duration(milliseconds: 50), _flush);
    Map<String, dynamic> res = {};
    try {
      if (!ctDirectActive && await CtServer.hasAddons()) {
        final req = await service.buildRequest('/ct-api/avatars', query: {'ids': ids.join(',')});
        final r = await service.httpClient.get(req.uri, headers: req.headers).timeout(const Duration(seconds: 10));
        if (r.statusCode == 200) {
          res = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        }
      }
    } catch (e) {
      _log.fine('avatars failed: $e');
    }
    for (final id in ids) {
      _done(id, res[id] as String?);
    }
  }
}

/// Круглая аватарка канала; пока не загрузилась — первая буква имени.
class CtChannelAvatar extends StatelessWidget {
  final String channelId;
  final String author;
  final double size;
  final VoidCallback? onTap;

  /// Картинка канала, если она уже пришла вместе с роликом — без лишних запросов.
  final String? url;

  /// Разрешить запрос по одному каналу (см. [CtAvatars.get]).
  final bool slow;

  const CtChannelAvatar(
      {super.key, required this.channelId, required this.author, this.size = 36, this.onTap, this.url, this.slow = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final letter = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colors.secondaryContainer, shape: BoxShape.circle),
      child: Text(author.isNotEmpty ? author.characters.first.toUpperCase() : '',
          style: TextStyle(fontSize: size * 0.42, color: colors.onSurface)),
    );
    return GestureDetector(
      onTap: onTap,
      child: FutureBuilder<(String, Map<String, String>?)?>(
        future: _resolve(),
        builder: (context, snap) {
          final r = snap.data;
          if (r == null) return letter;
          final (full, headers) = r;
          return ClipOval(
            child: CachedNetworkImage(
              imageUrl: full,
              cacheKey: full,
              httpHeaders: headers,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) => letter,
              errorWidget: (_, __, ___) => letter,
            ),
          );
        },
      ),
    );
  }

  /// Полный адрес картинки и заголовки (для относительного пути — через свой сервер).
  Future<(String, Map<String, String>?)?> _resolve() async {
    final url = (this.url?.isNotEmpty ?? false) ? this.url : await CtAvatars.instance.get(channelId, slow: slow);
    if (url == null || url.isEmpty) return null;
    Server? server;
    try {
      server = await db.getCurrentlySelectedServer();
    } catch (_) {}
    if (url.startsWith('/')) {
      if (server == null) return null;
      final full = server.url + url;
      return (full, server.headersForUrl(full));
    }
    return (url, server?.headersForUrl(url));
  }
}
