import 'package:clipious/cloudtube/direct.dart';
import 'dart:async';
import 'package:clipious/videos/models/ided_video.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:clipious/downloads/models/downloaded_video.dart';
import 'package:clipious/extensions.dart';
import 'package:clipious/player/models/media_event.dart';
import 'package:clipious/settings/states/settings.dart';
import 'package:logging/logging.dart';
import 'package:river_player/river_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../globals.dart';
import '../../main.dart';
import '../../utils/pretty_bytes.dart';
import '../../videos/models/video.dart';
import '../views/components/player_controls.dart';
import '../views/tv/components/player_controls.dart';
import '../../cloudtube/trace.dart';
import '../../cloudtube/hls_local.dart';
import '../../cloudtube/tv_scale.dart';
import 'interfaces/media_player.dart';

part 'video_player.freezed.dart';

final log = Logger('VideoPlayer');

final _googleCdnRegex = RegExp(r'https://(.+)googlevideo.com/');

class VideoPlayerCubit extends MediaPlayerCubit<VideoPlayerState> {
  BetterPlayerController? videoController;
  final SettingsCubit settings;

  /// CloudTube: автоповтор при ошибке воспроизведения (ссылки протухли, прокси Invidious моргнул):
  /// 1-я ошибка — заново запрашиваем видео и продолжаем с той же секунды,
  /// 2-я — пробуем обычный поток вместо DASH (только для этого видео).
  String? _recoverFor;
  int _recoverTries = 0;
  bool _forceProgressive = false;

  /// Сторож: если поток не стартовал за 25 с — считаем это ошибкой и восстанавливаемся (идея из Videre)
  Timer? _stallTimer;

  void _armStallWatch() {
    _stallTimer?.cancel();
    final id = state.video?.videoId;
    if (id == null || state.offlineVideo != null) return;
    _stallTimer = Timer(const Duration(seconds: 25), () {
      if (isClosed || state.video?.videoId != id) return;
      final v = videoController?.videoPlayerController?.value;
      if (v == null || !v.initialized) {
        log.warning('playback of $id did not start in 25s');
        _recover();
      }
    });
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
    _stallTimer?.cancel();
    _autoplayTimer?.cancel();
    disposeControllers();
    super.close();
  }

  @override
  disposeControllers() {
    WakelockPlus.disable();
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
        if (CtTrace.marks.isNotEmpty && !CtTrace.marks.last.$2.startsWith('плеер: пошло')) {
          CtTrace.mark('плеер: пошло воспроизведение');
        }
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
        CtTrace.mark('плеер: поток открыт (initialized), кадр ${videoController?.videoPlayerController?.value.size?.height.toInt() ?? '?'}p');
        Future.delayed(const Duration(seconds: 6), () {
          final h = videoController?.videoPlayerController?.value.size?.height.toInt();
          if (h != null) CtTrace.mark('плеер: через 6 с кадр ${h}p');
        });
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

  Future<void> _recover() async {
    final v = state.video;
    if (v == null || state.offlineVideo != null || isClosed) return;
    if (_recoverFor != v.videoId) {
      _recoverFor = v.videoId;
      _recoverTries = 0;
    }
    if (_recoverTries >= 2) return;
    _recoverTries++;
    final pos = videoController?.videoPlayerController?.value.position;
    log.warning('playback error on ${v.videoId}, recovery #$_recoverTries');
    if (_recoverTries == 2 && isUsingDash()) _forceProgressive = true;
    if (isTv && ctDirectActive) {
      _ctNoDashFor = v.videoId;
      CtTrace.mark('плеер: ошибка — переход на HLS');
    }
    try {
      final fresh = await service.getVideo(v.videoId);
      if (isClosed || state.video?.videoId != v.videoId) return;
      emit(state.copyWith(video: fresh));
    } catch (e) {
      log.warning('recovery fetch failed: $e');
    }
    if (isClosed) return;
    playVideo(false,
        startAt: pos != null && pos > const Duration(seconds: 1) ? pos : null);
  }

  onVideoListener(BetterPlayerEvent event) {
    forwardEvent(event);
    if (event.betterPlayerEventType == BetterPlayerEventType.exception) {
      _stallTimer?.cancel();
      _recover();
    } else if (event.betterPlayerEventType == BetterPlayerEventType.initialized) {
      _stallTimer?.cancel();
      // подстраховка: видео должно стартовать само (плеер мог поставить паузу «по видимости»,
      // пока экран плеера ещё открывался — на ТВ и медленных устройствах)
      final startedFor = state.video?.videoId;
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!isClosed && state.video?.videoId == startedFor && videoController?.isPlaying() != true) {
          videoController?.play();
        }
      });
      if (_recoverFor != state.video?.videoId) _recoverTries = 0;
    }

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.bufferingUpdate:
        EasyThrottle.throttle('video-buffering', const Duration(seconds: 1),
            () {
          List<DurationRange> durations = event.parameters?['buffered'] ?? [];
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
          settings.setLastSpeed(event.parameters?["speed"]);
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
      _recoverFor = null;
      _recoverTries = 0;
    }
    emit(state.copyWith(startAt: startAt, video: video));
    playVideo(false, startAt: startAt);
  }

  @override
  togglePlaying() {
    if (videoController != null) {
      _userPaused = videoController?.isPlaying() ?? false;
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

        Map<String, String> resolutions = {};

        bool isHls = newState.video!.hlsUrl != null;

        var formatStream = isHls || newState.video!.formatStreams!.isEmpty
            ? null
            : newState.video!
                .formatStreams![newState.video!.formatStreams!.length - 1];

        var useProxy = service.useProxy();

        String videoUrl = isHls
            ? '${newState.video!.hlsUrl!}${useProxy ? '?local=true' : ''}'
            : isUsingDash()
                ? '${newState.video!.dashUrl}${useProxy ? '?local=true' : ''}'
                : formatStream?.url ?? '';
        if (!isUsingDash() && formatStream != null) {
          newState =
              newState.copyWith(selectedNonDashTrack: formatStream.resolution);
        }

        // somehow invidious is sending google url even when using local proxy when not using dash
        if (!isUsingDash() && useProxy) {
          // we replace google's cdn by invidious server url.
          videoUrl = videoUrl.replaceFirst(_googleCdnRegex, '${(server).url}/');
        }

        var streamHeaders = !offline
            ? <String, String>{...?server.headersForUrl(videoUrl), ...ctDirectStreamHeaders(videoUrl)}
            : <String, String>{};
        // ТВ без сервера: как в SmartTube — свой DASH с одним (лучшим до 1080p) качеством,
        // иначе ExoPlayer на приставке берёт 360p и не поднимается. Запасной вариант — HLS 720–1080p.
        var ctDash = false;
        _ctFiltered = false;
        _ctDashHeight = null;
        if (isTv && ctDirectActive && _ctNoDashFor != newState.video!.videoId) {
          final d = await CtDashLocal.build(newState.video!.videoId, cap: ctTvQualityCap);
          if (d != null) {
            ctDash = true;
            _ctDashHeight = d.$2;
            _ctFiltered = true;
            streamHeaders = {...ctDirectStreamHeaders(d.$3)};
            videoUrl = d.$1;
            CtTrace.mark('плеер: DASH ${d.$2}p (одно качество)');
          }
        }
        if (!ctDash && isHls && isTv && ctDirectActive) {
          final local = await CtHlsLocal.atLeast(videoUrl, streamHeaders);
          CtTrace.mark(local != null ? 'плеер: HLS 720–1080p' : 'плеер: HLS без фильтра качества');
          _ctFiltered = local != null;
          if (local != null) videoUrl = local;
        } else if (!ctDash) {
          CtTrace.mark(isHls ? 'плеер: HLS' : (isUsingDash() ? 'плеер: DASH' : 'плеер: обычный поток ${formatStream?.resolution ?? ''}'));
        }

        log.info(
            'Playing url (dash ${isUsingDash()},  hasHls ? ${newState.video!.hlsUrl != null})  $videoUrl');

        BetterPlayerVideoFormat format = ctDash
            ? BetterPlayerVideoFormat.dash
            : isHls
            ? BetterPlayerVideoFormat.hls
            : isUsingDash()
                ? BetterPlayerVideoFormat.dash
                : BetterPlayerVideoFormat.other;

        if (format == BetterPlayerVideoFormat.other) {
          for (var value in (newState.video!.formatStreams ?? [])) {
            resolutions[value.qualityLabel] = value.url;
          }
        }

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
          // старт по первым ~0,6 с данных (по умолчанию ExoPlayer ждёт 2,5 с буфера — это и есть пауза перед стартом)
          bufferingConfiguration: const BetterPlayerBufferingConfiguration(
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
        _armStallWatch();
        _armAutoplay();
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
        _armStallWatch();
        _armAutoplay();
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
    _userPaused = true;
    videoController?.pause();
  }

  @override
  void play() {
    _userPaused = false;
    videoController?.play();
  }

  /// Пользователь сам поставил паузу — сторож автозапуска не вмешивается.
  bool _userPaused = false;
  Timer? _autoplayTimer;

  /// Сторож автозапуска: первые 20 с после открытия видео, если плеер готов, но стоит,
  /// а пользователь паузу не нажимал — запускаем. Лечит «открылось, но не играет»
  /// (ТВ-приставки, медленные устройства, пауза «по видимости» во время открытия экрана).
  void _armAutoplay() {
    _autoplayTimer?.cancel();
    _userPaused = false;
    final id = state.video?.videoId;
    var ticks = 0;
    _autoplayTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      ticks++;
      final c = videoController;
      if (isClosed || ticks > 40 || _userPaused || state.video?.videoId != id || c == null) {
        t.cancel();
        return;
      }
      final v = c.videoPlayerController?.value;
      if (v == null || !v.initialized) return;
      if (c.isPlaying() == true) {
        if (ticks > 6) t.cancel(); // играет устойчиво — дальше не следим
        return;
      }
      c.play();
    });
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

  /// Сейчас играет свой DASH ТВ (качество выбирается перезапуском с нужным потолком).
  bool get ctDashActive => _ctDashHeight != null;

  static String _ctQualityLabel(int h) => switch (h) {
        2160 => '2160p 4K',
        1440 => '1440p 2K',
        _ => '${h}p',
      };

  void _ctPreferHighQuality({bool retry = true}) {
    // плейлист уже без низких качеств — между 720p и 1080p пусть выбирает ExoPlayer
    if (!isTv || _ctFiltered) return;
    final tracks = (videoController?.betterPlayerAsmsTracks ?? const <BetterPlayerAsmsTrack>[])
        .where((t) => (t.height ?? 0) > 0 && (t.height ?? 0) <= 1080)
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
    if (_ctDashHeight != null && state.video != null) {
      return CtDashLocal.heights(state.video!.videoId).map(_ctQualityLabel).toList();
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
    if (_ctDashHeight != null && state.video != null) {
      return CtDashLocal.heights(state.video!.videoId).indexOf(_ctDashHeight!);
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

  @override
  List<String> getAudioTracks() {
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
    if (_ctDashHeight != null && state.video != null) {
      // своё качество на ТВ: запоминаем как потолок и перезапускаем с той же секунды
      final hs = CtDashLocal.heights(state.video!.videoId);
      if (index < 0 || index >= hs.length || hs[index] == _ctDashHeight) return;
      final pos = videoController?.videoPlayerController?.value.position;
      ctSetTvQuality(hs[index]);
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
