import 'package:cloudtube/cloudtube/audio_tracks.dart';
import 'package:cloudtube/cloudtube/direct.dart';
import 'dart:async';
import 'package:cloudtube/videos/models/ided_video.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:cloudtube/downloads/models/downloaded_video.dart';
import 'package:cloudtube/extensions.dart';
import 'package:cloudtube/player/models/media_event.dart';
import 'package:cloudtube/settings/states/settings.dart';
import 'package:logging/logging.dart';
import 'package:river_player/river_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../globals.dart';
import '../../main.dart';
import '../../utils/pretty_bytes.dart';
import '../../videos/models/video.dart';
import '../../videos/models/format_stream.dart';
import '../views/components/player_controls.dart';
import '../views/tv/components/player_controls.dart';
import '../../cloudtube/afr.dart';
import '../../cloudtube/trace.dart';
import '../../cloudtube/hls_local.dart';
import '../core/recovery.dart';
import '../core/stream_source.dart';
import '../core/watchdog.dart';
import '../../cloudtube/tv_scale.dart';
import '../../cloudtube/up_next.dart';
import 'interfaces/media_player.dart';

part 'video_player.freezed.dart';

final log = Logger('VideoPlayer');


class VideoPlayerCubit extends MediaPlayerCubit<VideoPlayerState> {
  BetterPlayerController? videoController;
  final SettingsCubit settings;

  /// CloudTube: восстановление после сбоев (правила — lib/player/core/recovery.dart)
  /// и один сторож воспроизведения (lib/player/core/watchdog.dart).
  final _recovery = CtRecoveryPolicy();
  bool _forceProgressive = false;
  late final _watch = CtPlaybackWatchdog(
    read: () {
      final v = videoController?.videoPlayerController?.value;
      if (v == null) return null;
      return PlaybackSnapshot(
          initialized: v.initialized,
          playing: videoController?.isPlaying() == true,
          buffering: v.isBuffering,
          position: v.position);
    },
    nudgePlay: () => videoController?.play(),
    onFail: (why) => _recover(why),
  );

  void _startWatch() {
    if (state.video == null || state.offlineVideo != null) return;
    _watch.start();
  }

  VideoPlayerCubit(super.initialState, super.player, this.settings) {
    onInit();
  }

  void onInit() {
    log.fine("Ready, playing video");
    playVideo(state.offlineVideo != null, startAt: state.startAt);
  }

  @override
  close() async {
    _watch.stop();
    disposeControllers();
    super.close();
  }

  @override
  disposeControllers() {
    WakelockPlus.disable();
    unawaited(CtAfr.restore());
    log.fine("Disposing video controller");
    var state = this.state.copyWith();
    videoController?.exitFullScreen();
    videoController?.removeEventsListener(onVideoListener);
    videoController?.dispose();
    videoController = null;
    if (!isClosed) {
      emit(state);
    }
  }

  forwardEvent(BetterPlayerEvent event) {
    MediaEventType? type;
    MediaState mediaState = MediaState.playing;

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.setSpeed:
        type = MediaEventType.speedChanged;
        break;
      case BetterPlayerEventType.pause:
        type = MediaEventType.pause;
        break;
      case BetterPlayerEventType.setVolume:
        break;
      case BetterPlayerEventType.play:
        type = MediaEventType.play;
        break;

      case BetterPlayerEventType.progress:
        EasyThrottle.throttle(
            'video-player-progress', const Duration(seconds: 1), () {
          player.setEvent(MediaEvent(
              state: MediaState.playing,
              type: MediaEventType.progress,
              value: videoController?.videoPlayerController?.value.position ??
                  Duration.zero));
        });
      case BetterPlayerEventType.seekTo:
        // we bypass the rest so we can send the current progress
        player.setEvent(MediaEvent(
            state: MediaState.playing,
            type: MediaEventType.progress,
            value: videoController?.videoPlayerController?.value.position ??
                Duration.zero));
        return;
      case BetterPlayerEventType.bufferingEnd:
        mediaState = MediaState.playing;
        break;
      case BetterPlayerEventType.bufferingStart:
        mediaState = MediaState.buffering;
        break;
      case BetterPlayerEventType.changedPlayerVisibility:
        break;
      case BetterPlayerEventType.changedPlaylistItem:
        break;
      case BetterPlayerEventType.setupDataSource:
        mediaState = MediaState.loading;
        break;
      case BetterPlayerEventType.controlsVisible:
        break;
      case BetterPlayerEventType.openFullscreen:
        break;
      case BetterPlayerEventType.initialized:
        CtTrace.mark('плеер: поток открыт');
        player.setEvent(MediaEvent<double>(
            state: MediaState.ready,
            type: MediaEventType.aspectRatioChanged,
            value: getAspectRatio()));
        mediaState = MediaState.ready;
        _ctPreferHighQuality();
        break;
      case BetterPlayerEventType.hideFullscreen:
        break;
      case BetterPlayerEventType.finished:
        mediaState = MediaState.completed;
        break;
      case BetterPlayerEventType.exception:
        mediaState = MediaState.error;
        break;
      case BetterPlayerEventType.controlsHiddenStart:
        break;
      case BetterPlayerEventType.controlsHiddenEnd:
        break;
      case BetterPlayerEventType.changedTrack:
        break;
      case BetterPlayerEventType.changedSubtitles:
        break;
      case BetterPlayerEventType.changedResolution:
        break;
      default:
        return;
    }

    player.setEvent(MediaEvent(state: mediaState, type: type));
  }

  /// Сбой воспроизведения (ошибка плеера, не открылось, зависло) — одно место для всех режимов.
  Future<void> _recover(String why) async {
    final v = state.video;
    if (v == null || state.offlineVideo != null || isClosed) return;
    final id = v.videoId;
    _watch.stop();
    final tvDirect = _ctCurHeight != null;
    final action = _recovery.onFailure(id,
        tvDirect: tvDirect,
        ownDash: _ctDashHeight != null,
        usingDash: isUsingDash(),
        canLower: [2160, 1440, 1080, 720, 480, 360].any((h) => h < (_ctCurHeight ?? 0)));
    final n = _recovery.fails;
    log.warning('playback problem on $id: $why → $action (#$n)');
    switch (action) {
      case CtRecovery.giveUp:
        CtTrace.mark('плеер: $why — сбой №$n, больше не пробуем');
        return;
      case CtRecovery.retrySame:
        CtTrace.mark('плеер: $why — сбой №$n, перезапуск с той же секунды');
      case CtRecovery.switchToHls:
        _ctNoDashFor = id;
        CtTrace.mark('плеер: $why — сбой №$n, переход на HLS того же качества');
      case CtRecovery.lowerQuality:
        final lower = [2160, 1440, 1080, 720, 480, 360].firstWhere((h) => h < (_ctCurHeight ?? 99999));
        _ctCapFor = id;
        _ctCapOverride = lower;
        _ctItagFor = null;
        CtTrace.mark('плеер: $why — сбой №$n, качество до ${lower}p');
      case CtRecovery.progressive:
        _forceProgressive = true;
        CtTrace.mark('плеер: $why — сбой №$n, обычный поток вместо DASH');
    }
    final pos = videoController?.videoPlayerController?.value.position;
    if (ctDirectActive) ctDirectForget(id);
    try {
      final fresh = await service.getVideo(id);
      if (isClosed || state.video?.videoId != id) return;
      emit(state.copyWith(video: fresh));
    } catch (e) {
      log.warning('recovery fetch failed: $e');
    }
    if (isClosed || state.video?.videoId != id) return;
    playVideo(false, startAt: pos != null && pos > const Duration(seconds: 1) ? pos : null);
  }

  onVideoListener(BetterPlayerEvent event) {
    forwardEvent(event);
    if (event.betterPlayerEventType == BetterPlayerEventType.exception) {
      _recover('ошибка плеера');
    }

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.bufferingUpdate:
        EasyThrottle.throttle('video-buffering', const Duration(seconds: 1),
            () {
          final durations = (event.parameters?['buffered'] as List<DurationRange>?) ?? <DurationRange>[];
          emit(state.copyWith(
              bufferPosition:
                  durations.sortBy((e) => e.end).map((e) => e.end).last));
          player.setEvent(MediaEvent(
              state: MediaState.playing,
              type: MediaEventType.bufferChanged,
              value: state.bufferPosition));
        });
        break;
      case BetterPlayerEventType.play:
        double speed = 1.0;
        if (settings.state.rememberPlayBackSpeed) {
          log.fine("Setting playback speed to $speed");
          videoController?.setSpeed(settings.state.lastSpeed);
        }
        break;
      case BetterPlayerEventType.changedSubtitles:
        settings.setLastSubtitle(
            videoController?.betterPlayerSubtitlesSource?.name ?? '');
        break;
      case BetterPlayerEventType.setSpeed:
        if (event.parameters?.containsKey("speed") ?? false) {
          settings.setLastSpeed((event.parameters?["speed"] as num).toDouble());
        }
        break;
      default:
        break;
    }
  }

  @override
  toggleDash() async {
    log.fine('toggle dash');
    var state = this.state.copyWith();
    // saving progress before we reload new video format
    // saveProgress(videoController?.videoPlayerController?.value.position.inSeconds ?? 0);
    await player.saveProgress(position().inSeconds);

    // disposeControllers();

    await settings.toggleDash(!isUsingDash());

    emit(state);
    playVideo(false);
  }

  @override
  switchVideo(Video video, {Duration? startAt}) {
    if (video.videoId != state.video?.videoId) {
      _forceProgressive = false;
      _recovery.reset(video.videoId);
    }
    emit(state.copyWith(startAt: startAt, video: video));
    playVideo(false, startAt: startAt);
  }

  @override
  togglePlaying() {
    if (videoController != null) {
      _watch.userPaused = videoController?.isPlaying() ?? false;
      (videoController?.isPlaying() ?? false)
          ? videoController?.pause()
          : videoController?.play();
      emit(state.copyWith());
    }
  }

  @override
  toggleControls(bool visible) {
    videoController?.setControlsEnabled(visible);
  }

  @override
  playVideo(bool offline, {Duration? startAt}) async {
    if (player.state.isAudio) {
      return;
    }
    var newState = state.copyWith();

    // only used if the player is currently close because it is onReady that will actually play the video
    // need better way of handling this
    newState = newState.copyWith(startAt: startAt);
    if (newState.video != null || newState.offlineVideo != null) {
      IdedVideo idedVideo = offline ? newState.offlineVideo! : newState.video!;
      // videoController?.dispose();
      // videoController = null;
      newState = newState.copyWith(bufferPosition: Duration.zero);

      if (startAt == null && !offline) {
        double progress = db.getVideoProgress(idedVideo.videoId);
        if (progress > 0 && progress < 0.90) {
          startAt = Duration(
              seconds: (offline
                      ? newState.offlineVideo!.lengthSeconds
                      : (newState.video!.lengthSeconds ?? 0) * progress)
                  .floor());
        }
      }

      late BetterPlayerDataSource betterPlayerDataSource;

      // getting data sources
      if (offline) {
        String videoPath = await newState.offlineVideo!.effectivePath;

        betterPlayerDataSource = BetterPlayerDataSource(
          BetterPlayerDataSourceType.file,
          videoPath,
          videoFormat: BetterPlayerVideoFormat.other,
          liveStream: false,
        );
      } else {
        assert(newState.video!.formatStreams != null);
        assert(newState.video!.adaptiveFormats != null);

        var server = await db.getCurrentlySelectedServer();
        String baseUrl = (server).url;
        final v = newState.video!;
        final id = v.videoId;
        // свой сервер: тоже одно качество своим DASH (как без сервера). DASH сервера и
        // ExoPlayer сами держали 360p, а без DASH сервера у YouTube есть только 360p
        final ownQuality = ctDirectActive || (v.liveNow != true && (v.adaptiveFormats ?? const []).isNotEmpty);
        if (!ctDirectActive && ownQuality) {
          final proxy = service.useProxy();
          CtDashLocal.rememberInvidious(id, v.adaptiveFormats!, (v.lengthSeconds ?? 0) * 1000,
              (f) => f.url.startsWith('/')
                  ? '${server.url}${f.url}'
                  : proxy && f.url.contains('googlevideo.com')
                      ? '${server.url}/latest_version?id=$id&itag=${f.itag}&local=true'
                      : f.url);
        }
        // выбор потока — lib/player/core/stream_source.dart
        final choice = await ctPickStream(CtStreamRequest(
          videoId: id,
          hlsUrl: v.hlsUrl,
          dashUrl: v.dashUrl,
          formatStreams: v.formatStreams ?? const <FormatStream>[],
          serverUrl: server.url,
          serverHeaders: server.headersForUrl,
          useProxy: service.useProxy(),
          useServerDash: isUsingDash(),
          tvDirect: ownQuality,
          hlsSingle: ctDirectActive,
          noOwnDash: _ctNoDashFor == id,
          cap: _ctCapFor == id ? _ctCapOverride! : ctTvQualityCap,
          itag: _ctItagFor == id ? _ctItag : null,
        ));
        CtTrace.mark(choice.trace);
        ctNowQuality.value = choice.qualityLabel;
        _ctFiltered = choice.fixedQuality;
        _ctDashHeight = choice.kind == CtStreamKind.ownDash ? choice.height : null;
        _ctCurHeight = choice.fixedQuality ? choice.height : null;
        if (choice.kind == CtStreamKind.ownDash) _ctCurItag = choice.itag;
        // ТВ: частота экрана под ролик (25/50 к/с — 50 Гц, 24 — 24 Гц, 30/60 — 60 Гц)
        if (choice.kind == CtStreamKind.ownDash) unawaited(CtAfr.forFps(CtDashLocal.fpsOf(id, choice.itag)));
        final uhd = (choice.height ?? 0) >= 1440;
        final progressiveRes = choice.progressiveResolution;
        if (progressiveRes != null) {
          newState = newState.copyWith(selectedNonDashTrack: progressiveRes);
        }
        final videoUrl = choice.url;
        final streamHeaders = choice.headers;
        log.info('Playing url (${choice.kind.name}) $videoUrl');

        final format = switch (choice.kind) {
          CtStreamKind.ownDash || CtStreamKind.serverDash => BetterPlayerVideoFormat.dash,
          CtStreamKind.hls || CtStreamKind.hlsSingle => BetterPlayerVideoFormat.hls,
          CtStreamKind.progressive => BetterPlayerVideoFormat.other,
        };
        final resolutions = choice.resolutions;

        String lastSubtitle = '';
        if (settings.state.rememberSubtitles) {
          lastSubtitle = settings.state.lastSubtitles;
        }

        betterPlayerDataSource = BetterPlayerDataSource(
          BetterPlayerDataSourceType.network,
          videoUrl,
          headers: streamHeaders,
          videoFormat: format,
          liveStream: newState.video!.liveNow,
          subtitles: newState.video!.captions
              .map((s) => BetterPlayerSubtitlesSource(
                  type: BetterPlayerSubtitlesSourceType.network,
                  urls: ['$baseUrl${s.url}'],
                  name: s.label,
                  selectedByDefault: s.label == lastSubtitle))
              .toList(),
          resolutions: resolutions.isNotEmpty ? resolutions : null,
          // старт по первым ~0,6 с данных (по умолчанию ExoPlayer ждёт 2,5 с буфера — это и есть пауза перед стартом).
          // 1440p/4K: VP9 15–40 Мбит/с — буфер длиннее и старт после 1,5 с, иначе на Wi-Fi подкачки
          bufferingConfiguration: uhd
              ? const BetterPlayerBufferingConfiguration(
                  minBufferMs: 15000,
                  maxBufferMs: 60000,
                  bufferForPlaybackMs: 1500,
                  bufferForPlaybackAfterRebufferMs: 4000,
                )
              : const BetterPlayerBufferingConfiguration(
                  minBufferMs: 8000,
                  maxBufferMs: 40000,
                  bufferForPlaybackMs: 600,
                  bufferForPlaybackAfterRebufferMs: 2000,
                ),
        );
      }

      WakelockPlus.enable();

      bool fillVideo = settings.state.fillFullscreen;

      if (videoController == null) {
        CtTrace.mark('плеер: создаю ExoPlayer');
        videoController = BetterPlayerController(
            BetterPlayerConfiguration(
                overlay: isTv
                    ? const TvPlayerControls()
                    : PlayerControls(mediaPlayerCubit: this),
                deviceOrientationsOnFullScreen: [
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                  DeviceOrientation.portraitDown,
                  DeviceOrientation.portraitUp
                ],
                deviceOrientationsAfterFullScreen: [
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                  DeviceOrientation.portraitDown,
                  DeviceOrientation.portraitUp
                ],
                handleLifecycle: false,
                startAt: startAt,
                autoPlay: true,
                // ТВ: стандартная пауза «по видимости» срабатывала, пока экран плеера ещё открывался,
                // и видео не стартовало само
                playerVisibilityChangedBehavior: isTv ? (_) {} : null,
                allowedScreenSleep: false,
                fit: fillVideo ? BoxFit.cover : BoxFit.contain,
                subtitlesConfiguration: BetterPlayerSubtitlesConfiguration(
                    backgroundColor: settings.state.subtitlesBackground
                        ? Colors.black.withValues(alpha: 0.8)
                        : Colors.transparent,
                    fontSize: settings.state.subtitleSize,
                    outlineEnabled: true,
                    outlineColor: Colors.black,
                    outlineSize: 1),
                controlsConfiguration: const BetterPlayerControlsConfiguration(
                    showControls: false
                    // customControlsBuilder: (controller, onPlayerVisibilityChanged) => PlayerControls(mediaPlayerCubit: this),
                    // customControlsBuilder: (controller, onPlayerVisibilityChanged) => const PlayerControls(),
                    // enablePlayPause: false,
                    // overflowModalColor: colors.surface,
                    // overflowModalTextColor: overFlowTextColor,
                    // overflowMenuIconsColor: overFlowTextColor,
                    // overflowMenuCustomItems: [BetterPlayerOverflowMenuItem(useDash ? Icons.check_box_outlined : Icons.check_box_outline_blank, locals.useDash, toggleDash)])
                    )),
            betterPlayerDataSource: betterPlayerDataSource);
        videoController!.addEventsListener(onVideoListener);
        videoController!.setBetterPlayerGlobalKey(newState.key);
        // isPipSupported = await videoController?.isPictureInPictureSupported() ?? false;
        _startWatch();
      } else {
        try {
          // подвисшая подготовка прошлого потока не должна блокировать следующее видео
          await videoController?.setupDataSource(betterPlayerDataSource).timeout(const Duration(seconds: 20));
        } catch (e) {
          log.warning('setupDataSource stalled/failed: $e — recreating controller');
          final old = videoController;
          videoController = null;
          old?.removeEventsListener(onVideoListener);
          old?.dispose(forceDispose: true);
          if (!isClosed) return playVideo(offline, startAt: startAt);
          return;
        }
        seek(startAt ?? Duration.zero);
        _startWatch();
      }

      emit(newState);
    }

    super.playVideo(offline);
  }

  @override
  void switchToOfflineVideo(DownloadedVideo v) {
    // videoController?.exitFullScreen();
    // disposeControllers();
    emit(state.copyWith(offlineVideo: v));
    playVideo(true);
  }

  @override
  bool isPlaying() {
    return videoController?.isPlaying() ?? false;
  }

  @override
  void pause() {
    _watch.userPaused = true;
    videoController?.pause();
  }

  @override
  void play() {
    _watch.userPaused = false;
    videoController?.play();
  }

  @override
  void seek(Duration position) {
    videoController?.seekTo(position);
  }

  @override
  Duration? bufferedPosition() {
    return state.bufferPosition;
  }

  @override
  Duration position() {
    return videoController?.videoPlayerController?.value.position ??
        Duration.zero;
  }

  @override
  double? speed() {
    return videoController?.videoPlayerController?.value.speed ?? 1;
  }

  String _videoTrackToString(BetterPlayerAsmsTrack? track) {
    return '${track?.height}p - ${prettyBytes((track?.bitrate ?? 0).toDouble(), bits: true)}/s';
  }

  String _audioTrackToString(BetterPlayerAsmsAudioTrack? track) {
    return '${track?.label} ${track?.language != null ? '- ${track?.language}' : ''}';
  }

  String _subtitleToString(BetterPlayerSubtitlesSource? source) {
    return '${source?.name}';
  }

  /// ТВ: ExoPlayer начинает HLS с низкого качества и на приставках по Wi-Fi/VPN часто на нём и остаётся
  /// (360p). На ТВ сразу выбираем лучшее качество до 1080p; его можно сменить в меню качества.
  bool _ctFiltered = false;
  // свой DASH на ТВ дал ошибку — для этого ролика дальше HLS
  String? _ctNoDashFor;
  // высота кадра своего DASH на ТВ (null — обычный режим)
  int? _ctDashHeight;
  // высота кадра в режиме ТВ без сервера (свой DASH или HLS с одним качеством)
  int? _ctCurHeight;
  String? _ctCurItag;
  // формат, выбранный вручную в меню (для этого ролика)
  String? _ctItagFor, _ctItag;
  // временное понижение качества после повторных сбоев (для этого ролика)
  String? _ctCapFor;
  int? _ctCapOverride;

  /// Сейчас играет свой DASH ТВ (качество выбирается перезапуском с нужным потолком).
  bool get ctDashActive => _ctMenu;

  // меню «Видеоформат» (как в SmartTube) — и на своём DASH, и на запасном HLS
  bool get _ctMenu =>
      _ctCurHeight != null && state.video != null && CtDashLocal.formats(state.video!.videoId).isNotEmpty;


  void _ctPreferHighQuality({bool retry = true}) {
    // ТВ со своим сервером (или запасной HLS без фильтра): сразу лучшее качество не выше выбранного
    // потолка (по умолчанию 4K) — сам ExoPlayer на приставках застревает на низком.
    // Без сервера качество уже одно (_ctFiltered) — здесь делать нечего
    if (!isTv || _ctFiltered) return;
    final tracks = (videoController?.betterPlayerAsmsTracks ?? const <BetterPlayerAsmsTrack>[])
        .where((t) => (t.height ?? 0) > 0 && (t.height ?? 0) <= ctTvQualityCap)
        .toList();
    if (tracks.isEmpty) {
      // список качеств HLS иногда появляется чуть позже
      if (retry) Future.delayed(const Duration(seconds: 2), () => _ctPreferHighQuality(retry: false));
      return;
    }
    tracks.sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
    log.info('ТВ: качество ${tracks.first.height}p');
    videoController?.setTrack(tracks.first);
  }

  @override
  List<String> getVideoTracks() {
    if (_ctMenu) {
      return CtDashLocal.formats(state.video!.videoId).map(CtDashLocal.label).toList();
    }
    if (state.video != null) {
      if (videoController?.betterPlayerAsmsTracks.isNotEmpty ?? false) {
        return videoController?.betterPlayerAsmsTracks
                .map(_videoTrackToString)
                .toList() ??
            [];
      } else {
        return (state.video?.formatStreams ?? [])
            .map((e) => e.resolution)
            .toList();
      }
    }
    // for offline video we don't offer video track selection
    return [];
  }

  @override
  int selectedVideoTrack() {
    if (_ctMenu) {
      if (_ctDashHeight == null) return -1; // играет запасной HLS
      return CtDashLocal.formats(state.video!.videoId).indexWhere((f) => '${f['itag']}' == _ctCurItag);
    }
    if (state.video != null) {
      if (isUsingDash()) {
        var tracks = getVideoTracks();
        var track = _videoTrackToString(videoController?.betterPlayerAsmsTrack);
        log.fine("Current track: $track");
        return tracks.indexOf(track);
      } else {
        var tracks = getVideoTracks();

        return tracks.indexOf(state.selectedNonDashTrack);
      }
    }
    // for offline video we don't offer video track selection
    return -1;
  }

  /// Дорожки ролика (оригинал / дубляжи), если их несколько — выбор через перезапуск потока.
  List<CtAudioTrack> get _ctAudio => state.offlineVideo != null || state.video == null
      ? const [] // скачанный ролик — дорожка одна (иначе в меню были дорожки прошлого ролика)
      : CtAudio.tracks(state.video!.videoId);

  /// Есть выбор звуковой дорожки (оригинал / дубляжи).
  bool get ctHasAudioChoice => _ctAudio.length > 1;

  @override
  List<String> getAudioTracks() {
    if (_ctAudio.length > 1) {
      // одинаковые подписи (две «English») различаем по id — иначе на ТВ выбиралась первая
      final labels = _ctAudio.map((t) => t.label).toList();
      return [
        for (var i = 0; i < labels.length; i++)
          labels.where((l) => l == labels[i]).length > 1 ? '${labels[i]} · ${_ctAudio[i].id}' : labels[i]
      ];
    }
    if (state.video != null) {
      if (videoController?.betterPlayerAsmsAudioTracks?.isNotEmpty ?? false) {
        return videoController?.betterPlayerAsmsAudioTracks
                ?.map(_audioTrackToString)
                .toList() ??
            [];
      }
    }
    // for offline video we don't offer video track selection
    return [];
  }

  @override
  int selectedAudioTrack() {
    final t = _ctAudio;
    if (t.length > 1) {
      final id = CtAudio.pickedId(state.video!.videoId);
      return t.indexWhere((x) => x.id == id);
    }
    if (state.video != null) {
      if (settings.state.useDash) {
        var tracks = getAudioTracks();
        var track =
            _audioTrackToString(videoController?.betterPlayerAsmsAudioTrack);
        log.fine("Current audio track: $track");
        return tracks.indexOf(track);
      }
    }
    // for offline video we don't offer video track selection
    return -1;
  }

  @override
  List<String> getSubtitles() {
    return state.video != null
        ? videoController?.betterPlayerSubtitlesSourceList
                .map(_subtitleToString)
                .toList() ??
            []
        : [];
  }

  @override
  int selectedSubtitle() {
    var tracks = getSubtitles();
    var track = _subtitleToString(videoController?.betterPlayerSubtitlesSource);
    log.fine("Current subtitle track: $track");
    return tracks.indexOf(track);
  }

  @override
  selectAudioTrack(int index) {
    final t = _ctAudio;
    if (t.length > 1) {
      if (index < 0 || index >= t.length) return;
      final id = state.video!.videoId;
      if (CtAudio.pickedId(id) == t[index].id) return;
      final pos = videoController?.videoPlayerController?.value.position;
      CtTrace.mark('плеер: звук «${t[index].label}»');
      CtAudio.choose(id, t[index]).then((_) {
        if (isClosed || state.video?.videoId != id) return;
        playVideo(false, startAt: pos != null && pos > const Duration(seconds: 1) ? pos : null);
      });
      return;
    }
    var betterPlayerAsmsTrack =
        videoController?.betterPlayerAsmsAudioTracks?[index];
    log.fine("Selected audio track, ${betterPlayerAsmsTrack?.label}");
    if (betterPlayerAsmsTrack != null) {
      videoController?.setAudioTrack(betterPlayerAsmsTrack);
    }
  }

  @override
  selectSubtitle(int index) {
    var sub = videoController?.betterPlayerSubtitlesSourceList[index];
    if (sub != null) {
      videoController?.setupSubtitleSource(sub, sourceInitialize: true);
    }
  }

  @override
  selectVideoTrack(int index) {
    if (_ctMenu) {
      // формат из меню: этот ролик — ровно он, высота запоминается как потолок для следующих
      final id = state.video!.videoId;
      final fs = CtDashLocal.formats(id);
      if (index < 0 || index >= fs.length || (_ctDashHeight != null && '${fs[index]['itag']}' == _ctCurItag)) return;
      final f = fs[index];
      final pos = videoController?.videoPlayerController?.value.position;
      _ctItagFor = id;
      _ctItag = '${f['itag']}';
      _ctCapFor = null;
      _ctNoDashFor = null;
      _recovery.reset(id);
      ctSetTvQuality((f['height'] as num?)?.toInt() ?? 2160);
      CtTrace.mark('плеер: выбран формат ${CtDashLocal.label(f)}');
      playVideo(false, startAt: pos != null && pos > const Duration(seconds: 1) ? pos : null);
      return;
    }
    if (isUsingDash()) {
      var betterPlayerAsmsTrack =
          videoController?.betterPlayerAsmsTracks[index];
      if (betterPlayerAsmsTrack != null) {
        videoController?.setTrack(betterPlayerAsmsTrack);
      }
    } else {
      var track = getVideoTracks()[index];
      var url = videoController?.betterPlayerDataSource?.resolutions?[track];
      if (url != null) {
        videoController?.setResolution(url);
        emit(state.copyWith(selectedNonDashTrack: track));
      }
    }
  }

  @override
  bool isMuted() {
    return videoController?.videoPlayerController?.value.volume == 0;
  }

  @override
  void toggleVolume(bool soundOn) {
    videoController?.setVolume(soundOn ? 1 : 0);
  }

  @override
  void setSpeed(double d) {
    videoController?.setSpeed(d);
  }

  @override
  double getSpeed() {
    return videoController?.videoPlayerController?.value.speed ?? 1;
  }

  @override
  bool hasDashToggle() {
    return state.video != null;
  }

  @override
  bool isUsingDash() {
    // без сервера нет DASH-манифеста Invidious: HLS или обычный поток
    return settings.state.useDash && !_forceProgressive && !ctDirectActive;
  }

  @override
  Duration duration() {
    return videoController?.videoPlayerController?.value.duration ??
        const Duration(milliseconds: 1);
  }

  @override
  double getAspectRatio() {
    double width =
        videoController?.videoPlayerController?.value.size?.width ?? 16;
    double height =
        videoController?.videoPlayerController?.value.size?.height ?? 9;
    return width / height;
  }

  @override
  void onEnterFullScreen() {
    videoController?.setOverriddenAspectRatio(getAspectRatio());
  }

  @override
  void onExitFullScreen() {
    videoController?.setOverriddenAspectRatio(16 / 9);
  }
}

@freezed
sealed class VideoPlayerState extends MediaPlayerState with _$VideoPlayerState {
  const factory VideoPlayerState(
      {required ColorScheme colors,
      required Color overFlowTextColor,
      required GlobalKey key,
      Duration? startAt,
      @Default("") String selectedNonDashTrack,
      @Default(Duration.zero) Duration? bufferPosition,
      Video? video,
      DownloadedVideo? offlineVideo,
      bool? playNow,
      bool? disableControls}) = _VideoPlayerState;

  const VideoPlayerState._();
}
