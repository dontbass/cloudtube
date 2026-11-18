import 'server_caps.dart';
import 'direct.dart';
import 'yt_fast.dart';
import '../utils/models/image_object.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'dart:async';
import 'dart:isolate';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:clipious/globals.dart';
import 'package:clipious/settings/models/db/server.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'prefs.dart';

final _log = Logger('CtAvatars');

/// Аватарки каналов.
/// • свой сервер с дополнениями CloudTube — пачкой: GET /ct-api/avatars?ids=UC..,UC..
/// • напрямую (и по просьбе [slow]) — по одному каналу у YouTube, бережно: не больше 2 запросов
///   сразу, разбор страницы в отдельном изоляте, после 3 ошибок подряд — пауза 10 минут.
/// Найденные адреса хранятся в базе 30 дней, так что каждый канал запрашивается редко.
class CtAvatars {
  CtAvatars._();

  static final CtAvatars instance = CtAvatars._();

  static const _keepDays = 30;

  final Map<String, String?> _cache = {};
  final Map<String, int> _savedDay = {};
  final Map<String, Completer<String?>> _waiting = {};
  final Set<String> _queue = {};
  Timer? _timer;
  Timer? _saveTimer;
  bool _loaded = false;

  static int get _today => DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  void _load() {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = CtPrefs.avatars.value;
      if (raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final today = _today;
      m.forEach((id, v) {
        final l = v as List<dynamic>;
        final day = (l[1] as num).toInt();
        if (today - day <= _keepDays) {
          _cache[id] = l[0] as String;
          _savedDay[id] = day;
        }
      });
    } catch (e) {
      _log.fine('avatars cache: $e');
    }
  }

  void _remember(String id, String url) {
    _savedDay[id] = _today;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 5), () async {
      // не больше 3000 каналов — самые свежие
      final ids = _savedDay.keys.toList()..sort((a, b) => _savedDay[b]!.compareTo(_savedDay[a]!));
      final m = <String, Object>{
        for (final i in ids.take(3000))
          if (_cache[i] != null) i: [_cache[i]!, _savedDay[i]!]
      };
      try {
        await CtPrefs.avatars.set(jsonEncode(m));
      } catch (_) {}
    });
  }

  Future<String?> get(String channelId, {bool slow = false}) {
    if (channelId.isEmpty) return Future.value(null);
    _load();
    final hit = _cache[channelId];
    if (hit != null) return Future.value(hit);
    final useSlow = slow || ctDirectActive;
    if (_cache.containsKey(channelId) && !useSlow) return Future.value(null);
    final pending = _waiting[channelId];
    if (pending != null) return pending.future;
    final c = Completer<String?>();
    _waiting[channelId] = c;
    if (useSlow && ctDirectActive) {
      _slowQueue.add(channelId);
      _pumpSlow();
    } else {
      _queue.add(channelId);
      _timer ??= Timer(const Duration(milliseconds: 150), () => _flush(slowFallback: slow));
    }
    return c.future;
  }

  void _done(String id, String? url) {
    _cache[id] = url;
    if (url != null && url.isNotEmpty) _remember(id, url);
    _waiting.remove(id)?.complete(url);
  }

  // ---------- по одному каналу ----------
  final List<String> _slowQueue = [];
  int _slowRunning = 0;
  int _slowFails = 0;
  DateTime? _pausedUntil;

  void _pumpSlow() {
    while (_slowRunning < 2 && _slowQueue.isNotEmpty) {
      // последние запрошенные — первыми: это то, что сейчас на экране
      final id = _slowQueue.removeLast();
      final paused = _pausedUntil != null && DateTime.now().isBefore(_pausedUntil!);
      if (paused) {
        _waiting.remove(id)?.complete(null);
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
        url = await _ytLogoIsolated(id).timeout(const Duration(seconds: 10));
      } else {
        final c = await service.getChannel(id).timeout(const Duration(seconds: 8));
        url = ImageObject.getBestThumbnail(c.authorThumbnails)?.url;
      }
      _slowFails = 0;
    } catch (e) {
      _log.fine('avatar $id: $e');
      if (++_slowFails >= 3) {
        _pausedUntil = DateTime.now().add(const Duration(minutes: 10));
        _slowFails = 0;
      }
    }
    if (url == null) {
      // ошибку не запоминаем навсегда — попробуем при следующем показе
      _waiting.remove(id)?.complete(null);
    } else {
      _done(id, url);
    }
  }

  // ---------- пачкой с сервера CloudTube ----------
  Future<void> _flush({bool slowFallback = false}) async {
    _timer = null;
    final ids = _queue.take(40).toList();
    _queue.removeAll(ids);
    if (_queue.isNotEmpty) _timer = Timer(const Duration(milliseconds: 50), _flush);
    Map<String, dynamic> res = {};
    var batch = false;
    try {
      if (!ctDirectActive && await CtServer.hasAddons()) {
        batch = true;
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
      final u = res[id] as String?;
      if (u == null && !batch && slowFallback) {
        // свой Invidious без дополнений и короткий список (ТВ) — по одному
        unawaited(_slowOneServer(id));
      } else {
        _done(id, u);
      }
    }
  }

  Future<void> _slowOneServer(String id) async {
    while (_slowRunning >= 2) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _slowRunning++;
    try {
      await _slowOne(id);
    } finally {
      _slowRunning--;
    }
  }
}

/// Канал по ролику (напрямую). В ленте «Главная» аккаунта YouTube (как на ТВ) у плиток
/// нет id канала — без него не открыть канал и не взять аватарку. Берём из короткого
/// ответа player (videoDetails.channelId), не больше 2 запросов сразу, с запоминанием.
class CtVideoChannel {
  CtVideoChannel._();

  static final _cache = <String, String?>{};
  static final _wait = <String, Future<String?>>{};
  static int _running = 0;

  static Future<String?> of(String videoId) {
    if (videoId.isEmpty || !ctDirectActive) return Future.value(null);
    if (_cache.containsKey(videoId)) return Future.value(_cache[videoId]);
    return _wait[videoId] ??= _fetch(videoId).whenComplete(() => _wait.remove(videoId));
  }

  static Future<String?> _fetch(String videoId) async {
    while (_running >= 2) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    _running++;
    try {
      // как на странице просмотра: ответ «next» (WEB) содержит владельца ролика —
      // id канала и его аватарку сразу (player у части роликов отвечает без videoDetails)
      final n = await CtYtFast.next(videoId).timeout(const Duration(seconds: 8));
      final owner = CtYtFast.findKey(n, 'videoOwnerRenderer');
      String? id;
      String? avatar;
      if (owner is Map) {
        final b = CtYtFast.findKey(owner['navigationEndpoint'], 'browseId');
        if (b is String && b.startsWith('UC')) id = b;
        final th = CtYtFast.findKey(owner['thumbnail'], 'thumbnails');
        if (th is List && th.isNotEmpty && th.last is Map) {
          final u = '${(th.last as Map)['url'] ?? ''}';
          avatar = u.startsWith('//') ? 'https:$u' : u;
        }
      }
      _cache[videoId] = id;
      if (id != null && (avatar ?? '').isNotEmpty) CtAvatars.instance._done(id, avatar);
      return id;
    } catch (e) {
      _log.info('канал ролика $videoId: $e');
      return null;
    } finally {
      _running--;
    }
  }
}

/// В отдельном изоляте: загрузка и разбор страницы канала не тормозят интерфейс.
Future<String?> _ytLogoIsolated(String id) => Isolate.run(() => _ytLogo(id));

Future<String?> _ytLogo(String id) async {
  final y = yt.YoutubeExplode();
  try {
    final c = await y.channels.get(id);
    return c.logoUrl.isEmpty ? null : c.logoUrl;
  } finally {
    y.close();
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

  /// Ролик, по которому можно найти канал, если [channelId] пустой.
  final String? videoId;

  const CtChannelAvatar(
      {super.key, required this.channelId, required this.author, this.size = 36, this.onTap, this.url, this.slow = false, this.videoId});

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
    var id = channelId;
    final vid = videoId ?? '';
    if (id.isEmpty && vid.isNotEmpty) id = await CtVideoChannel.of(vid) ?? '';
    var url = (this.url?.isNotEmpty ?? false) ? this.url : await CtAvatars.instance.get(id, slow: slow);
    // страница канала не отдала картинку — берём её из данных ролика
    if ((url == null || url.isEmpty) && vid.isNotEmpty && ctDirectActive) {
      final ch = await CtVideoChannel.of(vid);
      if (ch != null) url = await CtAvatars.instance.get(ch);
    }
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
