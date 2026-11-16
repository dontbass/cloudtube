import 'package:clipious/player/models/sleep_timer.dart';
import 'package:river_player/river_player.dart';
import 'package:bloc/bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:clipious/player/states/video_player.dart';
import 'package:logging/logging.dart';

import '../../settings/states/settings.dart';

part 'tv_player_settings.freezed.dart';

const List<String> tvAvailablePlaybackSpeeds = [
  '0.5x',
  '0.75x',
  '1x',
  '1.25x',
  '1.5x',
  '1.75x',
  '2x',
  '2.25x',
  '2.5x',
  '2.75x',
  '3x'
];
final Logger log = Logger('TvSettingsController');

enum Tabs {
  video,
  audio,
  captions,
  playbackSpeed,
  sleepTimer;
}

class TvPlayerSettingsCubit extends Cubit<TvPlayerSettingsState> {
  final VideoPlayerCubit player;
  final SettingsCubit settings;

  TvPlayerSettingsCubit(super.initialState, this.player, this.settings);

  /// Текущее качество отмечено «✓ ».
  List<String> get videoTrackNames {
    List<String> names;
    int sel = -1;
    if (player.ctDashActive) {
      names = player.getVideoTracks();
      sel = player.selectedVideoTrack();
    } else if (settings.state.useDash ||
        (player.state.video?.liveNow ?? false) ||
        (player.videoController?.betterPlayerAsmsTracks.isNotEmpty ?? false)) {
      // HLS/DASH: качества из манифеста (раньше на HLS без DASH список был пуст)
      final tracks = player.videoController?.betterPlayerAsmsTracks ?? const <BetterPlayerAsmsTrack>[];
      final hs = tracks.map((e) => e.height ?? 0).where((h) => h > 0).toSet().toList()
        ..sort((a, b) => b.compareTo(a));
      names = hs.map((h) => '${h}p').toList();
      final cur = player.videoController?.betterPlayerAsmsTrack?.height;
      if (cur != null) sel = names.indexOf('${cur}p');
    } else {
      names = player.videoController?.betterPlayerDataSource?.resolutions?.keys.toList() ?? [];
    }
    return [for (var i = 0; i < names.length; i++) i == sel ? '✓ ${names[i]}' : names[i]];
  }

  List<String> get audioTrackNames => settings.state.useDash
      ? player.videoController?.betterPlayerAsmsAudioTracks
              ?.map((e) => '${e.label}')
              .toList() ??
          []
      : [];

  List<String> get availableCaptions =>
      player.videoController?.betterPlayerSubtitlesSourceList
          .map((e) => '${e.name}')
          .toList() ??
      [];

  BetterPlayerController? get videoController => player.videoController;

  videoButtonFocusChange(bool focus) {
    if (focus) {
      emit(state.copyWith(selected: Tabs.video));
    }
  }

  audioButtonFocusChange(bool focus) {
    if (focus) {
      emit(state.copyWith(selected: Tabs.audio));
    }
  }

  captionsButtonFocusChange(bool focus) {
    if (focus) {
      emit(state.copyWith(selected: Tabs.captions));
    }
  }

  sleepTimerButtonFocusChange(bool focus) {
    if (focus) {
      emit(state.copyWith(selected: Tabs.sleepTimer));
    }
  }

  playbackSpeedButtonFocusChange(bool focus) {
    if (focus) {
      emit(state.copyWith(selected: Tabs.playbackSpeed));
    }
  }

  changeVideoTrack(String selected) {
    selected = selected.replaceFirst('✓ ', '');
    log.fine('Video quality selected $selected');

    if (player.ctDashActive) {
      player.selectVideoTrack(player.getVideoTracks().indexOf(selected));
      return;
    }
    final tracks = videoController?.betterPlayerAsmsTracks ?? const <BetterPlayerAsmsTrack>[];
    if (tracks.isNotEmpty) {
      final track = tracks.where((element) => '${element.height}p' == selected).firstOrNull;
      if (track != null) {
        log.fine('Changing video track to $selected');
        videoController?.setTrack(track);
      }
    } else {
      String? url =
          videoController?.betterPlayerDataSource?.resolutions?[selected];
      if (url != null) {
        videoController?.setResolution(url);
      }
    }
  }

  changeChangeAudioTrack(String selected) {
    log.fine('Audio quality selected $selected');
    BetterPlayerAsmsAudioTrack? track = videoController
        ?.betterPlayerAsmsAudioTracks
        ?.firstWhere((e) => '${e.label}' == selected);

    if (track != null) {
      log.fine('Changing audio track to $selected');
      videoController?.setAudioTrack(track);
    }
  }

  changeSubtitles(String selected) {
    log.fine('Subtitles selected $selected');
    BetterPlayerSubtitlesSource? track = videoController
        ?.betterPlayerSubtitlesSourceList
        .firstWhere((e) => '${e.name}' == selected);

    settings.setLastSubtitle(selected);

    if (track != null) {
      log.fine('Changing subtitles to $selected');
      videoController?.setupSubtitleSource(track);
    }
  }

  changePlaybackSpeed(String selected) {
    String speed = selected.replaceAll('x', '');
    videoController?.setSpeed(double.parse(speed));
  }
}

@freezed
sealed class TvPlayerSettingsState with _$TvPlayerSettingsState {
  const factory TvPlayerSettingsState(
      {@Default(Tabs.video) Tabs selected,
      @Default(SleepTimer()) SleepTimer sleepTimer}) = _TvPlayerSettingsState;
}
