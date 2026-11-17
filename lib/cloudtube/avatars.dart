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

  Future<String?> get(String channelId) {
    if (channelId.isEmpty) return Future.value(null);
    if (_cache.containsKey(channelId)) return Future.value(_cache[channelId]);
    final c = _waiting.putIfAbsent(channelId, () => Completer<String?>());
    _queue.add(channelId);
    _timer ??= Timer(const Duration(milliseconds: 150), _flush);
    return c.future;
  }

  static final _yt = yt.YoutubeExplode();

  /// Без дополнений CloudTube: напрямую — из YouTube (1 лёгкий запрос), со своего
  /// Invidious — из карточки канала. Не больше 4 запросов одновременно.
  Future<Map<String, dynamic>> _oneByOne(List<String> ids) async {
    final out = <String, dynamic>{};
    Future<void> one(String id) async {
      try {
        if (ctDirectActive) {
          out[id] = (await _yt.channels.get(id).timeout(const Duration(seconds: 8))).logoUrl;
        } else {
          final c = await service.getChannel(id).timeout(const Duration(seconds: 8));
          out[id] = ImageObject.getBestThumbnail(c.authorThumbnails)?.url;
        }
      } catch (_) {}
    }

    for (var i = 0; i < ids.length; i += 4) {
      await Future.wait(ids.skip(i).take(4).map(one));
    }
    return out;
  }

  Future<void> _flush() async {
    _timer = null;
    final ids = _queue.take(40).toList();
    _queue.removeAll(ids);
    if (_queue.isNotEmpty) _timer = Timer(const Duration(milliseconds: 50), _flush);
    Map<String, dynamic> res = {};
    try {
      if (ctDirectActive || !await CtServer.hasAddons()) {
        res = await _oneByOne(ids);
      } else {
        final req = await service.buildRequest('/ct-api/avatars', query: {'ids': ids.join(',')});
        final r = await service.httpClient.get(req.uri, headers: req.headers);
        if (r.statusCode == 200) {
          res = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        }
      }
    } catch (e) {
      _log.fine('avatars failed: $e');
    }
    for (final id in ids) {
      final u = res[id] as String?;
      _cache[id] = u;
      _waiting.remove(id)?.complete(u);
    }
  }
}

/// Круглая аватарка канала; пока не загрузилась — первая буква имени.
class CtChannelAvatar extends StatelessWidget {
  final String channelId;
  final String author;
  final double size;
  final VoidCallback? onTap;

  const CtChannelAvatar(
      {super.key, required this.channelId, required this.author, this.size = 36, this.onTap});

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
    final url = await CtAvatars.instance.get(channelId);
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
