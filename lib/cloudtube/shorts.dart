import 'direct.dart';
import 'dart:convert';
import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:clipious/globals.dart';
import 'package:clipious/player/states/player.dart';
import 'package:clipious/router.dart';
import 'package:clipious/settings/models/db/server.dart';
import 'package:clipious/settings/models/db/settings.dart';
import 'package:clipious/utils/models/image_object.dart';
import 'package:clipious/videos/models/video.dart';
import 'package:clipious/videos/views/components/add_to_playlist_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:river_player/river_player.dart';
import 'package:share_plus/share_plus.dart';

import 'avatars.dart';
import 'comments.dart';
import 'server_caps.dart';
import 'theme.dart';

final _log = Logger('CtShorts');
final _cdn = RegExp(r'https://(.+)googlevideo.com/');
const _seenKey = 'ct-shorts-seen';
const _blockKey = 'ct-shorts-blocked-channels';

/// Shorts: вертикальное листание как в YouTube.
/// Подборка ct:shorts с сервера, перемешивается, уже просмотренные уходят в конец.
class CtShortsPage extends StatefulWidget {
  const CtShortsPage({super.key});

  @override
  State<CtShortsPage> createState() => _CtShortsPageState();
}

class _CtShortsPageState extends State<CtShortsPage> {
  final List<Video> _videos = [];
  final Set<String> _ids = {};
  final PageController _pages = PageController();
  final _rnd = Random();
  late final List<String> _seen;
  late final Set<String> _blocked;
  int _page = 1;
  int _current = 0;
  bool _loading = false;
  bool _end = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    try {
      context.read<PlayerCubit>().pause();
    } catch (_) {}
    try {
      _seen = List<String>.from(jsonDecode(db.getSettings(_seenKey)?.value ?? '[]') as List);
    } catch (_) {
      _seen = [];
    }
    try {
      _blocked = Set<String>.from(jsonDecode(db.getSettings(_blockKey)?.value ?? '[]') as List);
    } catch (_) {
      _blocked = {};
    }
    _load();
  }

  void _next() {
    if (_current + 1 < _videos.length) {
      _pages.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _notInterested(String id) {
    _markSeen(id);
    _next();
  }

  void _blockChannel(String channelId) {
    if (channelId.isEmpty) return;
    _blocked.add(channelId);
    db.saveSetting(SettingsValue(_blockKey, jsonEncode(_blocked.toList())));
    setState(() {
      final cur = _videos[_current];
      _videos.removeWhere((v) => v.authorId == channelId && v != cur);
    });
    _next();
  }

  void _markSeen(String id) {
    _seen.remove(id);
    _seen.add(id);
    if (_seen.length > 600) _seen.removeRange(0, _seen.length - 600);
    db.saveSetting(SettingsValue(_seenKey, jsonEncode(_seen)));
  }

  /// Берём две страницы подборки за раз, перемешиваем; просмотренные — в конец.
  Future<void> _load() async {
    if (_loading || _end) return;
    setState(() => _loading = true);
    var again = false;
    try {
      final batch = <Video>[];
      // сервер отдаёт подборку по кругу — берём страницы, пока не наберём новых
      for (var i = 0; i < 8 && !_end && batch.length < 12; i++) {
        final addons = ctDirectActive || await CtServer.hasAddons(); // без сервера — подборка Shorts из YouTube
        final vids = addons
            ? (await service.search('ct:shorts', page: _page)).videos
            : await CtServer.fallbackShorts(_page);
        _page++;
        if (!addons && _page > 25) _end = true;
        final add = vids
            .where((v) => !_blocked.contains(v.authorId) && _ids.add(v.videoId))
            .toList();
        if (vids.isEmpty && addons && !ctDirectActive) _end = true;
        if (ctDirectActive && _page > 60) _end = true;
        batch.addAll(add);
      }
      if (batch.isEmpty && !_end && _videos.isNotEmpty) {
        again = true;
        // всё уже показано в этой сессии — начинаем новый круг (сервер к этому времени пересобирает подборку)
        _ids.clear();
        _ids.addAll(_videos.skip(_videos.length > 30 ? _videos.length - 30 : 0).map((v) => v.videoId));
      }
      final seen = _seen.toSet();
      final fresh = batch.where((v) => !seen.contains(v.videoId)).toList()..shuffle(_rnd);
      final old = batch.where((v) => seen.contains(v.videoId)).toList()..shuffle(_rnd);
      final wasEmpty = _videos.isEmpty;
      _videos.addAll(fresh);
      if (fresh.length < 4) _videos.addAll(old); // уже виденные — только если новых нет
      _error = null;
      if (wasEmpty && _videos.isNotEmpty) _prefetch(-1);
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
    if (again && mounted) Future.microtask(_load);
    // подборка на сервере ещё собирается — пробуем снова сами
    if (_videos.isEmpty && mounted && _retries < 12) {
      _retries++;
      Future.delayed(const Duration(seconds: 10), () {
        if (!mounted || _videos.isNotEmpty) return;
        _end = false;
        _page = 1;
        _load();
      });
    }
  }

  int _retries = 0;

  /// данные следующих роликов (ссылки на потоки) — заранее, чтобы при свайпе не ждать Invidious
  void _prefetch(int i) {
    for (var j = i + 1; j <= i + 3 && j < _videos.length; j++) {
      _getVideo(_videos[j].videoId).catchError((_) => _videos[j]);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_videos.isEmpty) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: _loading
            ? const CircularProgressIndicator(color: Colors.white)
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                    _error != null
                        ? 'Не удалось загрузить Shorts'
                        : _retries < 12
                            ? 'Подборка Shorts готовится на сервере…'
                            : 'Shorts пока нет',
                    style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 12),
                FilledButton.tonal(
                    onPressed: () {
                      _end = false;
                      _load();
                    },
                    child: const Text('Обновить')),
              ]),
      );
    }
    return Stack(children: [
      Container(
        color: Colors.black,
        child: PageView.builder(
          controller: _pages,
          allowImplicitScrolling: true,
          scrollDirection: Axis.vertical,
          itemCount: _videos.length,
          onPageChanged: (i) {
            setState(() => _current = i);
            if (i >= _videos.length - 5) _load();
            _prefetch(i);
          },
          itemBuilder: (context, i) => CtShortItem(
            key: ValueKey(_videos[i].videoId),
            video: _videos[i],
            active: i == _current,
            preload: i == _current + 1 || i == _current - 1,
            onWatched: _markSeen,
            onNotInterested: _notInterested,
            onBlockChannel: _blockChannel,
          ),
        ),
      ),
    ]);
  }
}

class CtShortItem extends StatefulWidget {
  final Video video;
  final bool active;
  final bool preload;
  final void Function(String id) onWatched;
  final void Function(String id) onNotInterested;
  final void Function(String channelId) onBlockChannel;

  const CtShortItem(
      {super.key,
      required this.video,
      required this.active,
      this.preload = false,
      required this.onWatched,
      required this.onNotInterested,
      required this.onBlockChannel});

  @override
  State<CtShortItem> createState() => _CtShortItemState();
}

/// Общий кэш данных видео: следующий ролик подгружается заранее.
/// Ссылки на потоки живут несколько часов, поэтому запись старше 40 минут запрашивается заново.
final Map<String, (DateTime, Future<Video>)> _videoCache = {};

Future<Video> _getVideo(String id) {
  final hit = _videoCache[id];
  if (hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 40)) {
    return hit.$2;
  }
  if (_videoCache.length > 60) _videoCache.remove(_videoCache.keys.first);
  final f = service.getVideo(id).catchError((e) {
    _videoCache.remove(id);
    throw e;
  });
  _videoCache[id] = (DateTime.now(), f);
  return f;
}

class _CtShortItemState extends State<CtShortItem> {
  BetterPlayerController? _ctl;
  Video? _full;
  bool _paused = false;
  bool _failed = false;
  bool _watched = false;
  double _progress = 0;
  int? _comments;
  bool? _subscribed;
  bool _clean = false;

  @override
  void initState() {
    super.initState();
    if (widget.active || widget.preload) _start();
  }

  @override
  void didUpdateWidget(covariant CtShortItem old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _paused = false;
      if (_ctl == null) {
        _start();
      } else {
        _ensurePlaying();
      }
    } else if (!widget.active && old.active) {
      _kick++;
      if (widget.preload && _ctl != null) {
        final c = _ctl!;          // соседний ролик держим готовым — свайп назад без загрузки
        if (c.videoPlayerController?.value.initialized == true) {
          c.pause().catchError((_) {});
          c.seekTo(Duration.zero).catchError((_) {});
        }
      } else {
        _stop();
      }
    } else if (widget.preload && !old.preload && _ctl == null) {
      _start();
    } else if (!widget.preload && !widget.active && (old.preload || old.active)) {
      _stop();
    }
  }

  bool _starting = false;
  int _kick = 0;

  /// Активный ролик должен играть. play() до готовности плеера молча игнорируется,
  /// поэтому повторяем, пока не заиграет (до ~6 с) — пока пользователь сам не поставил паузу.
  void _ensurePlaying() {
    final token = ++_kick;
    void tick(int n) {
      final c = _ctl;
      if (!mounted || token != _kick || !widget.active || _paused || c == null) return;
      final v = c.videoPlayerController?.value;
      if (v != null && v.initialized && !(c.isPlaying() ?? false)) {
        if (_played && v.position > const Duration(milliseconds: 300)) {
          c.seekTo(Duration.zero);
        }
        c.play().catchError((_) {});
      }
      if (n < 20 && !(v?.initialized == true && (c.isPlaying() ?? false))) {
        Future.delayed(const Duration(milliseconds: 300), () => tick(n + 1));
      }
    }

    tick(0);
  }

  bool _played = false;
  bool _noDash = false;
  bool _noHls = false; // HLS не завёлся — обычный поток со звуком

  Future<void> _start() async {
    if (_starting || _ctl != null) return;
    _starting = true;
    try {
      await _start0();
    } finally {
      _starting = false;
    }
  }

  Future<void> _start0() async {
    if (widget.active) _extras();
    try {
      final Server server = await db.getCurrentlySelectedServer();
      final v = _full ?? await _getVideo(widget.video.videoId);
      if (!mounted || !(widget.active || widget.preload)) return;
      _full = v;
      final streams = v.formatStreams ?? [];
      final hlsUrl = _noHls && streams.isNotEmpty ? null : v.hlsUrl;
      if (streams.isEmpty && hlsUrl == null && (v.dashUrl ?? '').isEmpty) throw 'нет потоков';
      final useProxy = service.useProxy();
      String url;
      BetterPlayerVideoFormat format = BetterPlayerVideoFormat.other;
      // DASH, как в обычном плеере: progressive-поток itag 18 через прокси Invidious стартует медленно
      if (!_noDash && (v.dashUrl ?? '').isNotEmpty && hlsUrl == null) {
        url = '${v.dashUrl}${useProxy ? '?local=true' : ''}';
        if (url.startsWith('/')) url = server.url + url;
        format = BetterPlayerVideoFormat.dash;
      } else if (streams.isNotEmpty && hlsUrl == null) {
        url = streams.last.url;
        if (useProxy) url = url.replaceFirst(_cdn, '${server.url}/');
        if (url.startsWith('/')) url = server.url + url;
      } else {
        url = '$hlsUrl${useProxy ? '?local=true' : ''}';
        format = BetterPlayerVideoFormat.hls;
      }
      if (!mounted) return;
      final size = MediaQuery.sizeOf(context);
      final ctl = BetterPlayerController(
        BetterPlayerConfiguration(
          aspectRatio: size.width / size.height,
          autoPlay: false,
          looping: true,
          fit: BoxFit.cover,
          expandToFill: true,
          handleLifecycle: true,
          autoDispose: false,
          // своя логика play/pause: стандартная по видимости ставила на паузу соседний ролик во время свайпа
          playerVisibilityChangedBehavior: (_) {},
          controlsConfiguration: const BetterPlayerControlsConfiguration(showControls: false),
        ),
        betterPlayerDataSource: BetterPlayerDataSource(
          BetterPlayerDataSourceType.network,
          url,
          headers: {...?server.headersForUrl(url), ...ctDirectStreamHeaders(url)},
          videoFormat: format,
          bufferingConfiguration: const BetterPlayerBufferingConfiguration(
            minBufferMs: 1500,
            maxBufferMs: 12000,
            bufferForPlaybackMs: 250,
            bufferForPlaybackAfterRebufferMs: 1000,
          ),
        ),
      );
      ctl.addEventsListener((e) {
        if (!mounted) return;
        if (e.betterPlayerEventType == BetterPlayerEventType.initialized) {
          if (widget.active && !_paused) _ensurePlaying();
        } else if (e.betterPlayerEventType == BetterPlayerEventType.play) {
          _played = true;
        } else if (e.betterPlayerEventType == BetterPlayerEventType.progress) {
          final p = e.parameters?['progress'] as Duration?;
          final d = e.parameters?['duration'] as Duration?;
          if (p != null && d != null && d.inMilliseconds > 0) {
            setState(() => _progress = p.inMilliseconds / d.inMilliseconds);
            if (!_watched && p.inSeconds >= 3) {
              _watched = true;
              widget.onWatched(widget.video.videoId);
            }
          }
        } else if (e.betterPlayerEventType == BetterPlayerEventType.exception) {
          _log.warning('short ${widget.video.videoId} ${format.name}: ${e.parameters}');
          if (format == BetterPlayerVideoFormat.hls && !_noHls && streams.isNotEmpty) {
            _noHls = true; // HLS не завёлся — пробуем обычный поток
            final c = _ctl;
            _ctl = null;
            c?.dispose(forceDispose: true);
            _start();
            return;
          }
          if (format == BetterPlayerVideoFormat.dash && !_noDash) {
            _noDash = true;            // DASH не завёлся — пробуем обычный поток
            final c = _ctl;
            _ctl = null;
            c?.dispose(forceDispose: true);
            _start();
            return;
          }
          setState(() => _failed = true);
        }
      });
      setState(() => _ctl = ctl);
      if (widget.active && !_paused) _ensurePlaying();
    } catch (e) {
      _log.warning('short ${widget.video.videoId}: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  /// число комментариев и статус подписки — в фоне, не мешая видео
  Future<void> _extras() async {
    if (_comments == null) {
      CtComments.load(widget.video.videoId, invidiousOnly: true).then((p) {
        if (mounted) setState(() => _comments = p.count ?? p.items.length);
      }).catchError((_) {});
    }
    final id = widget.video.authorId;
    if (_subscribed == null && id != null && id.isNotEmpty) {
      try {
        final s = await service.isSubscribedToChannel(id);
        if (mounted) setState(() => _subscribed = s);
      } catch (_) {}
    }
  }

  Future<void> _toggleSubscribe() async {
    final id = widget.video.authorId;
    if (id == null || _subscribed == null) return;
    final was = _subscribed!;
    setState(() => _subscribed = !was);
    try {
      was ? await service.unSubscribe(id) : await service.subscribe(id);
    } catch (e) {
      if (mounted) {
        setState(() => _subscribed = was);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Войдите в аккаунт («Профиль»), чтобы подписываться')));
      }
    }
  }

  void _stop() {
    _kick++;
    _played = false;
    final c = _ctl;
    _ctl = null;
    if (c != null) {
      c.pause();
      c.dispose(forceDispose: true);
    }
    if (mounted) setState(() => _progress = 0);
  }

  @override
  void dispose() {
    final c = _ctl;
    _ctl = null;
    c?.dispose(forceDispose: true);
    super.dispose();
  }

  void _toggle() {
    if (_clean) {
      setState(() => _clean = false);
      return;
    }
    final c = _ctl;
    if (c == null) return;
    setState(() => _paused = !_paused);
    _paused ? c.pause() : c.play();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final playlists = await service.getUserPlaylists();
      if (!mounted) return;
      AddToPlaylistDialog.showAddToPlaylistDialog(context,
          videoId: widget.video.videoId,
          playlists: playlists, onAdd: (pid) async {
        try {
          await service.addVideoToPlaylist(pid, widget.video.videoId);
          messenger.showSnackBar(const SnackBar(content: Text('Сохранено в плейлист')));
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text('Не удалось сохранить: $e')));
        }
      });
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Войдите в аккаунт («Профиль»), чтобы сохранять в плейлисты')));
    }
  }

  void _description() {
    final text = (_full?.description ?? '').trim();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (c, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          Text(widget.video.title ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SelectableText(text.isEmpty ? 'Описания нет' : text, style: const TextStyle(fontSize: 14, height: 1.4)),
        ]),
      ),
    );
  }

  void _menu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (c) {
        Widget item(IconData i, String t, VoidCallback f) => ListTile(
              leading: Icon(i, size: 28),
              title: Text(t, style: const TextStyle(fontSize: 16)),
              onTap: () {
                Navigator.pop(c);
                f();
              },
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            item(Icons.notes, 'Описание', _description),
            item(Icons.open_in_full, 'Чистый экран', () => setState(() => _clean = true)),
            item(Icons.smart_display_outlined, 'Открыть в обычном плеере', _openFull),
            item(Icons.block, 'Не интересует', () => widget.onNotInterested(widget.video.videoId)),
            item(Icons.cancel_outlined, 'Не рекомендовать видео с этого канала',
                () => widget.onBlockChannel(widget.video.authorId ?? '')),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
  }

  void _openFull() {
    _ctl?.pause();
    AutoRouter.of(context).push(VideoRoute(videoId: widget.video.videoId));
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    final thumbs = ImageObject.getThumbnailUrlsByPreferredOrder(v.videoThumbnails);
    final likes = _full?.likeCount ?? 0;
    const shadow = [Shadow(blurRadius: 8, color: Colors.black54)];
    const white = TextStyle(color: Colors.white, shadows: shadow);
    return GestureDetector(
      onTap: _toggle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_ctl == null && thumbs.isNotEmpty)
            FutureBuilder<Server>(
              future: db.getCurrentlySelectedServer(),
              builder: (c, s) => s.hasData
                  ? Image.network(
                      thumbs.first.startsWith('/') ? s.data!.url + thumbs.first : thumbs.first,
                      headers: s.data!.headersForUrl(
                          thumbs.first.startsWith('/') ? s.data!.url + thumbs.first : thumbs.first),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    )
                  : const SizedBox.shrink(),
            ),
          if (_ctl != null) SizedBox.expand(child: BetterPlayer(controller: _ctl!)),
          if (_ctl == null && !_failed && widget.active)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (_failed)
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Не удалось воспроизвести', style: white),
                TextButton(
                    onPressed: () {
                      _videoCache.remove(widget.video.videoId); // свежие ссылки на потоки
                      final c = _ctl;
                      _ctl = null;
                      c?.dispose(forceDispose: true);
                      setState(() {
                        _failed = false;
                        _noDash = false;
                        _noHls = false;
                        _full = null;
                      });
                      _start();
                    },
                    child: const Text('Повторить')),
                TextButton(onPressed: _openFull, child: const Text('Открыть в плеере')),
              ]),
            ),
          if (_paused)
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, size: 44, color: Colors.white),
              ),
            ),
          if (!_clean)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 260,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0x99000000), Colors.transparent]),
              ),
            ),
          ),
          // верх справа: поиск и «ещё»
          if (!_clean)
            Positioned(
              top: 4,
              right: 4,
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.white, size: 28, shadows: shadow),
                  onPressed: () {
                    _ctl?.pause();
                    AutoRouter.of(context).push(SearchRoute());
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.more_horiz, color: Colors.white, size: 30, shadows: shadow),
                  onPressed: _menu,
                ),
              ]),
            ),
          // кнопки справа — контурные, без подложки, как в YouTube
          if (!_clean)
            Positioned(
              right: 4,
              bottom: 16,
              child: Column(children: [
                _side(Icons.favorite_border, likes > 0 ? ctShortNumber(likes) : 'Нравится', null),
                _side(Icons.textsms_outlined,
                    (_comments ?? 0) > 0 ? ctShortNumber(_comments!) : 'Комм.',
                    () => ctShowComments(context, v.videoId)),
                _side(Icons.bookmark_border, 'Сохранить', _save),
                _side(Icons.shortcut, 'Поделиться',
                    () => SharePlus.instance.share(ShareParams(text: 'https://youtu.be/${v.videoId}'))),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () {
                    _ctl?.pause();
                    AutoRouter.of(context).push(ChannelRoute(channelId: v.authorId ?? ''));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(10)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: CtChannelAvatar(channelId: v.authorId ?? '', author: v.author ?? '', size: 38),
                    ),
                  ),
                ),
              ]),
            ),
          // канал, «Подписаться», название
          if (!_clean)
          Positioned(
            left: 12,
            right: 80,
            bottom: 18,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CtChannelAvatar(
                  channelId: v.authorId ?? '',
                  author: v.author ?? '',
                  size: 34,
                  onTap: () {
                    _ctl?.pause();
                    AutoRouter.of(context).push(ChannelRoute(channelId: v.authorId ?? ''));
                  },
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                      (v.author ?? '').startsWith('@') ? v.author! : '@${v.author ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: white.copyWith(fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                const SizedBox(width: 10),
                if (_subscribed != null)
                  GestureDetector(
                    onTap: _toggleSubscribe,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _subscribed! ? Colors.white24 : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(_subscribed! ? 'Вы подписаны' : 'Подписаться',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _subscribed! ? Colors.white : Colors.black)),
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              Text(v.title ?? '',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: white.copyWith(fontSize: 14)),
            ]),
          ),
          // прогресс — красный, как в YouTube
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 2,
            child: Container(
              color: Colors.white24,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: _progress.clamp(0, 1).toDouble(),
                child: Container(color: CtColors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _side(IconData icon, String label, VoidCallback? onTap, {bool mirror = false}) {
    Widget ic = Icon(icon, color: Colors.white, size: 32, shadows: const [Shadow(blurRadius: 8, color: Colors.black54)]);
    if (mirror) ic = Transform.flip(flipX: true, child: ic);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        width: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Column(children: [
            ic,
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)])),
          ]),
        ),
      ),
    );
  }
}
