import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as mk;

import '../globals.dart';
import '../router.dart';
import '../settings/models/db/server.dart';
import '../videos/models/video.dart';
import 'platform.dart';
import 'direct.dart';
import 'watch.dart';
import '../videos/views/components/compact_video.dart';

final _log = Logger('CtDesktopPlayer');

/// Плеер для Windows/Linux/macOS на media_kit (mpv). На Android не используется.
/// Видео и звук берутся отдельными потоками через сервер (/latest_version?local=true) —
/// так mpv сразу получает нужное качество, без DASH-манифестов.
class CtDesktopPlayer extends StatefulWidget {
  final Video video;

  const CtDesktopPlayer({super.key, required this.video});

  static bool _inited = false;

  static void ensureInitialized() {
    if (_inited) return;
    MediaKit.ensureInitialized();
    _inited = true;
  }

  /// Открыть видео: если плеер уже открыт — заменить его, иначе открыть поверх.
  static void open(Video v) {
    final nav = appRouter.navigatorKey.currentState;
    if (nav == null) return;
    final route = MaterialPageRoute(builder: (_) => CtDesktopPlayer(video: v), settings: const RouteSettings(name: 'ct-desktop-player'));
    var replacing = false;
    nav.popUntil((r) {
      if (r.settings.name == 'ct-desktop-player') replacing = true;
      return true;
    });
    if (replacing) {
      nav.pushReplacement(route);
    } else {
      nav.push(route);
    }
  }

  @override
  State<CtDesktopPlayer> createState() => _CtDesktopPlayerState();
}

class _Quality {
  final String label;
  final String videoItag;
  final int height;

  _Quality(this.label, this.videoItag, this.height);
}

class _CtDesktopPlayerState extends State<CtDesktopPlayer> {
  late final Player _player = Player(configuration: const PlayerConfiguration(title: 'CloudTube'));
  late final mk.VideoController _controller = mk.VideoController(_player);
  Video? _full;
  String? _error;
  List<_Quality> _qualities = [];
  _Quality? _quality;
  String? _audioItag;
  StreamSubscription? _errSub;
  Timer? _watch;
  Duration _lastPos = Duration.zero;
  int _stuck = 0;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _errSub = _player.stream.error.listen((e) => _log.warning('mpv: $e'));
    // Сторож: mpv с отдельной звуковой дорожкой иногда «замирает» на старте, хотя данные уже
    // загружены (то же лечится паузой/плей вручную). Если позиция стоит 2,5 с при запасе буфера —
    // делаем это сами.
    _watch = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final st = _player.state;
      if (!st.playing || st.completed) {
        _stuck = 0;
        return;
      }
      if (st.position == _lastPos && st.buffer - st.position > const Duration(seconds: 2)) {
        if (++_stuck >= 5) {
          _stuck = 0;
          _log.info('mpv stalled at ${st.position}, kicking');
          _player.pause().then((_) => _player.play());
        }
      } else {
        _stuck = 0;
      }
      _lastPos = st.position;
    });
    _load();
  }

  @override
  void dispose() {
    _errSub?.cancel();
    _watch?.cancel();
    _player.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final v = await service.getVideo(widget.video.videoId);
      if (!mounted) return;
      _full = v;
      // качества видео: лучший поток на каждую высоту, до 4K
      final byHeight = <int, _Quality>{};
      for (final f in v.adaptiveFormats ?? const []) {
        if (!f.type.startsWith('video/')) continue;
        final h = int.tryParse(RegExp(r'(\d+)p').firstMatch(f.qualityLabel ?? f.resolution ?? '')?.group(1) ?? '') ?? 0;
        if (h == 0) continue;
        final prefer = f.type.contains('mp4') ? 1 : 0; // при равной высоте — mp4 (h264/av1), он легче декодируется
        final cur = byHeight[h];
        if (cur == null || prefer == 1) byHeight[h] = _Quality(f.qualityLabel ?? '${h}p', f.itag, h);
      }
      _qualities = byHeight.values.toList()..sort((a, b) => b.height - a.height);
      final audio = (v.adaptiveFormats ?? const []).where((f) => f.type.startsWith('audio/')).toList()
        ..sort((a, b) => (int.tryParse(b.bitrate ?? '') ?? 0).compareTo(int.tryParse(a.bitrate ?? '') ?? 0));
      final m4a = audio.where((f) => f.type.contains('mp4')).toList();
      _audioItag = (m4a.isNotEmpty ? m4a.first : (audio.isNotEmpty ? audio.first : null))?.itag;
      _quality = _qualities.isEmpty
          ? null
          : _qualities.firstWhere((q) => q.height <= 720, orElse: () => _qualities.last);
      setState(() {});
      await _play();
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось загрузить видео: $e');
    }
  }

  Future<void> _play({Duration? at}) async {
    final v = _full!;
    final server = await db.getCurrentlySelectedServer();
    final headers = server.headersForUrl(server.url) ?? {};
    final np = _player.platform;
    if (np is NativePlayer) {
      // быстрее старт: меньше анализа потока перед первым кадром
      await np.setProperty('demuxer-lavf-analyzeduration', '0.5');
      await np.setProperty('demuxer-lavf-probesize', '1000000');
      await np.setProperty('cache', 'yes');
      await np.setProperty('demuxer-readahead-secs', '20');
      await np.setProperty('force-seekable', 'yes');
    }
    if (np is NativePlayer) {
      await np.setProperty('user-agent', ctDirectActive ? kCtIosUserAgent : 'Mozilla/5.0 CloudTube');
    }
    if (np is NativePlayer && ctCaFile != null) {
      await np.setProperty('tls-ca-file', ctCaFile!);
      await np.setProperty('tls-verify', 'yes');
    }
    if (np is NativePlayer && headers.isNotEmpty) {
      await np.setProperty('http-header-fields', headers.entries.map((e) => '${e.key}: ${e.value}').join(','));
    }
    String url;
    if (ctDirectActive && (v.hlsUrl ?? '').isNotEmpty) {
      // без сервера: HLS от YouTube — один поток со звуком, стартует быстро
      url = v.hlsUrl!;
      if (np is NativePlayer) await np.setProperty('audio-files', '');
    } else if (ctDirectActive && _quality != null && _audioItag != null) {
      url = (v.adaptiveFormats ?? const []).firstWhere((f) => f.itag == _quality!.videoItag).url;
      final a = (v.adaptiveFormats ?? const []).firstWhere((f) => f.itag == _audioItag).url;
      if (np is NativePlayer) await np.setProperty('audio-files', a);
    } else if (v.liveNow == true && (v.hlsUrl ?? '').isNotEmpty) {
      url = v.hlsUrl!;
      if (np is NativePlayer) await np.setProperty('audio-files', '');
    } else if (_quality != null && _quality!.videoItag.isNotEmpty && _audioItag != null) {
      url = _stream(server, v.videoId, _quality!.videoItag);
      if (np is NativePlayer) await np.setProperty('audio-files', _stream(server, v.videoId, _audioItag!));
    } else if ((v.formatStreams ?? const []).isNotEmpty) {
      url = _stream(server, v.videoId, v.formatStreams!.last.itag);
      if (np is NativePlayer) await np.setProperty('audio-files', '');
    } else {
      setState(() => _error = 'У видео нет потоков');
      return;
    }
    await _player.open(Media(url, httpHeaders: headers, start: at));
  }

  String _stream(Server s, String id, String itag) => '${s.url}/latest_version?id=$id&itag=$itag&local=true';

  Future<void> _setQuality(_Quality q) async {
    final pos = _player.state.position;
    setState(() => _quality = q);
    await _play(at: pos);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final v = _full ?? widget.video;
    return Scaffold(
      appBar: AppBar(
        title: Text(v.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_qualities.isNotEmpty && !(ctDirectActive && (_full?.hlsUrl ?? '').isNotEmpty))
            PopupMenuButton<_Quality>(
              tooltip: 'Качество',
              icon: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.hd_outlined),
                const SizedBox(width: 4),
                Text(_quality?.label ?? ''),
              ]),
              onSelected: _setQuality,
              itemBuilder: (_) => [
                for (final q in _qualities)
                  CheckedPopupMenuItem(value: q, checked: q == _quality, child: Text(q.label)),
              ],
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: TextStyle(color: colors.error)))
          : LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 1000;
              final leftW = wide ? c.maxWidth - 420 : c.maxWidth;
              final pad = wide ? 16.0 : 0.0;
              final vh = ((leftW - pad * 2) * 9 / 16).clamp(180.0, c.maxHeight * (wide ? 0.72 : 0.6));
              final video = ClipRRect(
                borderRadius: BorderRadius.circular(wide ? 12 : 0),
                child: SizedBox(
                  height: vh,
                  child: mk.Video(
                    controller: _controller,
                    fill: Colors.black,
                    controls: (state) => mk.MaterialDesktopVideoControlsTheme(
                      normal: mk.MaterialDesktopVideoControlsThemeData(
                        seekBarThumbColor: const Color(0xFFFF0033),
                        seekBarPositionColor: const Color(0xFFFF0033),
                        keyboardShortcuts: _shortcuts(state),
                      ),
                      fullscreen: mk.MaterialDesktopVideoControlsThemeData(
                        seekBarThumbColor: const Color(0xFFFF0033),
                        seekBarPositionColor: const Color(0xFFFF0033),
                        keyboardShortcuts: _shortcuts(state),
                      ),
                      child: mk.MaterialDesktopVideoControls(state),
                    ),
                  ),
                ),
              );
              final info = _full == null
                  ? const Center(child: CircularProgressIndicator())
                  : CtWatchBody(video: _full!, showRecs: !wide);
              final left = Column(children: [
                Padding(padding: EdgeInsets.fromLTRB(pad, pad, pad, 0), child: video),
                Expanded(child: info),
              ]);
              if (!wide) return left;
              final recs = (_full?.recommendedVideos ?? const <Video>[]).where((e) => !e.filterHide).toList();
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: left),
                SizedBox(
                  width: 420,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                    itemCount: recs.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: CompactVideo(video: recs[i], onTap: () => CtDesktopPlayer.open(recs[i])),
                    ),
                  ),
                ),
              ]);
            }),
    );
  }

  /// Горячие клавиши как в YouTube: K/пробел — пауза, J/L — ±10 с, ←/→ — ±5 с, ↑/↓ — громкость,
  /// M — звук, F — полный экран (сам F обрабатывает media_kit), 0–9 — переход к 0–90 %.
  Map<ShortcutActivator, VoidCallback> _shortcuts(mk.VideoState vs) {
    void seekBy(int s) {
      final p = _player.state.position + Duration(seconds: s);
      _player.seek(p < Duration.zero ? Duration.zero : p);
    }

    void vol(double d) => _player.setVolume((_player.state.volume + d).clamp(0, 100));
    double lastVol = 100;
    final m = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.space): _player.playOrPause,
      const SingleActivator(LogicalKeyboardKey.keyK): _player.playOrPause,
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause): _player.playOrPause,
      const SingleActivator(LogicalKeyboardKey.keyJ): () => seekBy(-10),
      const SingleActivator(LogicalKeyboardKey.keyL): () => seekBy(10),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => seekBy(-5),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => seekBy(5),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => vol(5),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => vol(-5),
      const SingleActivator(LogicalKeyboardKey.keyM): () {
        if (_player.state.volume > 0) {
          lastVol = _player.state.volume;
          _player.setVolume(0);
        } else {
          _player.setVolume(lastVol);
        }
      },
    };
    m[const SingleActivator(LogicalKeyboardKey.keyF)] = () => vs.toggleFullscreen();
    m[const SingleActivator(LogicalKeyboardKey.escape)] = () => vs.exitFullscreen();
    for (var i = 0; i <= 9; i++) {
      m[SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + i))] = () {
        final d = _player.state.duration;
        if (d > Duration.zero) _player.seek(d * (i / 10));
      };
    }
    return m;
  }
}
