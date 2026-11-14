import 'server_caps.dart';
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

  Future<void> _flush() async {
    _timer = null;
    final ids = _queue.take(40).toList();
    _queue.removeAll(ids);
    if (_queue.isNotEmpty) _timer = Timer(const Duration(milliseconds: 50), _flush);
    Map<String, dynamic> res = {};
    try {
      if (!await CtServer.hasAddons()) throw 'нет дополнений';
      final req = await service.buildRequest('/ct-api/avatars', query: {'ids': ids.join(',')});
      final r = await service.httpClient.get(req.uri, headers: req.headers);
      if (r.statusCode == 200) {
        res = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
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
      child: FutureBuilder<List<Object?>>(
        future: Future.wait([CtAvatars.instance.get(channelId), db.getCurrentlySelectedServer()]),
        builder: (context, snap) {
          final url = snap.data?[0] as String?;
          final server = snap.data?[1] as Server?;
          if (url == null || url.isEmpty || server == null) return letter;
          final full = url.startsWith('/') ? server.url + url : url;
          return ClipOval(
            child: CachedNetworkImage(
              imageUrl: full,
              cacheKey: full,
              httpHeaders: server.headersForUrl(full),
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
}
