import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:cloudtube/videos/models/video.dart';
import 'package:easy_debounce/easy_debounce.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:cloudtube/player/states/player.dart';
import '../../cloudtube/up_next.dart';
import 'package:logging/logging.dart';

import '../../utils.dart';
import '../models/media_event.dart';

part 'tv_player_controls.freezed.dart';

const Duration controlFadeOut = Duration(seconds: 4);
const Duration throttleDuration = Duration(milliseconds: 250);

final log = Logger('TvPlayerController');

class TvPlayerControlsCubit extends Cubit<TvPlayerControlsState> {
  final PlayerCubit player;

  TvPlayerControlsCubit(super.initialState, this.player);

  fastForward() {
    player.fastForward();
  }

  fastRewind() {
    player.rewind();
  }

  displaySettings() {
    emit(state.copyWith(showSettings: true, displayControls: false));
  }

  showUi() {
    emit(state.copyWith(controlsOpacity: 1));
    hideControls();
  }

  KeyEventResult handleRemoteEvents(FocusNode node, KeyEvent event) {
    bool timeLineControl =
        !state.showQueue && !state.showSettings && !state.displayControls;
    log.fine(
        'Key: ${event.logicalKey}, Timeline control: $timeLineControl, showQueue: ${state.showQueue}, showSettings: ${state.showSettings}, showControls: ${state.displayControls}');
    // плашка «Далее»: OK — сразу следующее, «Назад» — отменить автопереход (и не выходить из плеера)
    if (ctUpNext.value != null) {
      final k = event.logicalKey;
      if (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.browserBack) {
        if (event is KeyUpEvent) player.ctUpNextCancel();
        return KeyEventResult.handled;
      }
      if (timeLineControl && isOk(k)) {
        if (event is KeyUpEvent) player.ctUpNextNow();
        return KeyEventResult.handled;
      }
    }
    // полоса перемотки (как в SmartTube): стрелки влево/вправо двигают метку, при удержании —
    // всё быстрее; видео перематывается, когда кнопку отпустили
    if (ctSeekMode) return _ctSeekKey(event);
    if (timeLineControl || state.displayControls) {
      final k = event.logicalKey;
      final arrows = k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight;
      if (timeLineControl && arrows && event is KeyDownEvent) {
        _ctEnterSeek();
        return _ctSeekKey(event);
      }
      if (k == LogicalKeyboardKey.arrowDown && (timeLineControl || state.displayControls)) {
        // вниз — к полосе перемотки (из панели кнопок тоже)
        if (event is KeyUpEvent) _ctEnterSeek();
        return KeyEventResult.handled;
      }
    }
    showUi();

    // looks like back is activate on pressdown and not press up
    if (event is KeyUpEvent &&
        !timeLineControl &&
        event.logicalKey == LogicalKeyboardKey.goBack) {
      emit(state.copyWith(
          showQueue: false,
          showSettings: false,
          displayControls: state.showQueue || state.showSettings));
      return KeyEventResult.handled;
    } else if (event is KeyUpEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.mediaPlay:
          player.play();
          break;
        case LogicalKeyboardKey.mediaPause:
          player.pause();
          break;
        case LogicalKeyboardKey.mediaPlayPause:
          player.togglePlaying();
          break;

        case LogicalKeyboardKey.mediaFastForward:
        case LogicalKeyboardKey.mediaStepForward:
        case LogicalKeyboardKey.mediaSkipForward:
          fastForward();
          break;
        case LogicalKeyboardKey.mediaRewind:
        case LogicalKeyboardKey.mediaStepBackward:
        case LogicalKeyboardKey.mediaSkipBackward:
          fastRewind();
          break;
        case LogicalKeyboardKey.mediaTrackNext:
          player.playNext();
          break;
        case LogicalKeyboardKey.mediaTrackPrevious:
          player.playPrevious();
          break;
      }

      // влево/вправо в режиме просмотра — полоса перемотки (см. выше)
      if (timeLineControl &&
          (isOk(event.logicalKey) || event.logicalKey == LogicalKeyboardKey.arrowUp)) {
        emit(state.copyWith(displayControls: true));
      }
    }
    return KeyEventResult.ignored;
  }

  // ——— полоса перемотки ———
  /// Метка перемотки (куда перемотаем); не null — открыта полоса перемотки.
  final ctSeek = ValueNotifier<Duration?>(null);
  bool get ctSeekMode => ctSeek.value != null;
  int _ctHold = 0;
  Timer? _ctCommit;
  Timer? _ctIdle;

  void _ctEnterSeek() {
    _ctCommit?.cancel();
    ctSeek.value = player.state.position;
    emit(state.copyWith(controlsOpacity: 1, displayControls: false, showSettings: false, showQueue: false));
    _ctArmIdle();
  }

  void _ctExitSeek({bool commit = true}) {
    _ctCommit?.cancel();
    _ctIdle?.cancel();
    final p = ctSeek.value;
    if (commit && p != null && (p - player.state.position).abs() > const Duration(milliseconds: 900)) player.seek(p);
    ctSeek.value = null;
    hideControls();
  }

  void _ctArmIdle() {
    _ctIdle?.cancel();
    _ctIdle = Timer(const Duration(seconds: 4), () {
      if (!isClosed) _ctExitSeek();
    });
  }

  KeyEventResult _ctSeekKey(KeyEvent event) {
    final k = event.logicalKey;
    final right = k == LogicalKeyboardKey.arrowRight, left = k == LogicalKeyboardKey.arrowLeft;
    if (right || left) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        _ctHold = event is KeyDownEvent ? 0 : _ctHold + 1;
        final len = player.duration;
        // шаг растёт при удержании; у длинных роликов — крупнее
        final base = _ctHold < 4 ? 5 : (_ctHold < 12 ? 15 : (_ctHold < 25 ? 30 : 60));
        final scale = len.inMinutes > 60 ? 3 : (len.inMinutes > 20 ? 2 : 1);
        final step = Duration(seconds: _ctHold < 4 ? base : base * scale);
        var p = (ctSeek.value ?? player.state.position) + (right ? step : -step);
        if (p < Duration.zero) p = Duration.zero;
        if (len > Duration.zero && p > len - const Duration(seconds: 1)) p = len - const Duration(seconds: 1);
        ctSeek.value = p;
        _ctCommit?.cancel();
        _ctArmIdle();
      } else if (event is KeyUpEvent) {
        // отпустили — перематываем через мгновение (если не нажмут снова)
        _ctCommit?.cancel();
        _ctCommit = Timer(const Duration(milliseconds: 450), () {
          final p = ctSeek.value;
          if (!isClosed && p != null) player.seek(p);
        });
      }
      return KeyEventResult.handled;
    }
    if (event is! KeyUpEvent) return KeyEventResult.handled;
    if (isOk(k)) {
      _ctExitSeek();
      player.play();
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _ctExitSeek();
      emit(state.copyWith(controlsOpacity: 1, displayControls: true));
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _ctExitSeek();
      displaySettings();
    } else if (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.browserBack) {
      _ctExitSeek(commit: false);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ——— мышь ———
  DateTime _ctMouseAt = DateTime(2000);

  /// Движение мыши над видео — показать панель кнопок (не чаще раза в 0,4 с).
  void ctMouseMoved() {
    final now = DateTime.now();
    if (now.difference(_ctMouseAt) < const Duration(milliseconds: 400)) return;
    _ctMouseAt = now;
    if (state.showSettings || state.showQueue || ctSeekMode) return;
    if (!state.displayControls) emit(state.copyWith(displayControls: true));
    showUi();
  }

  /// Колесо над видео — перемотка ±10 с (в настройках и очереди колесо листает списки).
  void ctMouseWheel(bool forward) {
    if (state.showSettings || state.showQueue) return;
    forward ? fastForward() : fastRewind();
    showUi();
  }

  /// Клик/перетаскивание по полосе перемотки: [f] — доля длительности.
  void ctMouseSeek(double f, {bool commit = false}) {
    final len = player.duration;
    if (len <= Duration.zero) return;
    final p = Duration(milliseconds: (len.inMilliseconds * f).round());
    if (commit) {
      _ctIdle?.cancel();
      ctSeek.value = null;
      player.seek(p);
      showUi();
    } else {
      ctSeek.value = p;
      emit(state.copyWith(controlsOpacity: 1));
      _ctArmIdle();
    }
  }

  @override
  Future<void> close() {
    _ctCommit?.cancel();
    _ctIdle?.cancel();
    ctSeek.dispose();
    return super.close();
  }

  hideSettings() {
    emit(state.copyWith(
        controlsOpacity: 0,
        showSettings: false,
        showQueue: false,
        displayControls: false));
  }

  hideControls() {
    EasyDebounce.debounce('tv-controls', controlFadeOut, () {
      // открытые настройки/очередь/полосу перемотки не прячем сами
      if (!isClosed && !state.showSettings && !state.showQueue && !ctSeekMode) {
        emit(state.copyWith(
            controlsOpacity: 0,
            showSettings: false,
            showQueue: false,
            displayControls: false));
      }
    });
  }

  displayQueue() {
    emit(state.copyWith(showQueue: true, displayControls: false));
  }

  Future<void> playFromQueue(Video video) async {
    emit(state.copyWith(showQueue: false, loading: true));
    player.switchToVideo(video);
    emit(state.copyWith(loading: false));
  }

  onStreamEvent(MediaEvent event) {
    log.fine('Event: ${event.state}, ${event.type}');
    switch (event.state) {
      case MediaState.buffering:
        // showControls();
        break;
      case MediaState.loading:
      case MediaState.ready:
        showUi();
        break;
      default:
        break;
    }
  }
}

@freezed
sealed class TvPlayerControlsState with _$TvPlayerControlsState {
  const factory TvPlayerControlsState({
    @Default(0) double controlsOpacity,
    @Default(false) bool showSettings,
    @Default(false) bool showQueue,
    @Default(false) bool loading,
    @Default(false) bool displayControls,
  }) = _TvPlayerControlsState;

  bool get isShowUi => controlsOpacity == 1;

  const TvPlayerControlsState._();
}
