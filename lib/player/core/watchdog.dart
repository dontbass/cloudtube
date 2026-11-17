import 'dart:async';

/// Состояние плеера, которое смотрит сторож.
class PlaybackSnapshot {
  final bool initialized;
  final bool playing;
  final bool buffering;
  final Duration position;

  const PlaybackSnapshot(
      {required this.initialized, required this.playing, required this.buffering, required this.position});
}

/// Один сторож воспроизведения вместо трёх таймеров (запуск, автозапуск, зависание).
///
/// - **Не стартовало**: поток не открылся за [startTimeout] → [onFail].
/// - **Автозапуск**: первые [autoplayWindow] после открытия, если плеер готов, но стоит,
///   а паузу пользователь не нажимал → [nudgePlay] (ТВ-приставки, пауза «по видимости»).
/// - **Зависание**: картинка не двигается дольше [stallTimeout], хотя должна играть → [onFail].
///   Раньше это проверялось только на ТВ без сервера, теперь — везде.
///
/// Логика не зависит от плеера и таймеров: в тестах время подаётся через [tick].
class CtPlaybackWatchdog {
  final PlaybackSnapshot? Function() read;
  final void Function() nudgePlay;
  final void Function(String reason) onFail;
  final Duration startTimeout;
  final Duration autoplayWindow;
  final Duration stallTimeout;
  final Duration interval;

  CtPlaybackWatchdog({
    required this.read,
    required this.nudgePlay,
    required this.onFail,
    this.startTimeout = const Duration(seconds: 25),
    this.autoplayWindow = const Duration(seconds: 20),
    this.stallTimeout = const Duration(seconds: 12),
    this.interval = const Duration(milliseconds: 500),
  });

  Timer? _timer;
  Duration _elapsed = Duration.zero;
  Duration _still = Duration.zero;
  Duration _playedFor = Duration.zero;
  Duration? _lastPos;
  bool _stable = false;
  bool _failed = false;

  /// Пользователь сам поставил паузу — автозапуск не вмешивается.
  bool userPaused = false;

  bool get running => _timer != null;

  /// Новое видео (или перезапуск после сбоя): всё сначала.
  void start() {
    stop();
    _elapsed = _still = _playedFor = Duration.zero;
    _lastPos = null;
    _stable = false;
    _failed = false;
    userPaused = false;
    _timer = Timer.periodic(interval, (_) => tick(interval));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Один шаг проверки ([dt] — сколько прошло с прошлого шага).
  void tick(Duration dt) {
    if (_failed) return; // о сбое сообщаем один раз, до следующего start()
    _elapsed += dt;
    final s = read();
    if (s == null || !s.initialized) {
      if (_elapsed >= startTimeout) {
        stop();
        _failed = true;
        onFail('поток не открылся за ${startTimeout.inSeconds} с');
      }
      return;
    }

    // автозапуск: пока видео ни разу устойчиво не заиграло
    if (s.playing) {
      _playedFor += dt;
      if (_playedFor >= const Duration(seconds: 3)) _stable = true;
    } else if (!_stable && !userPaused && !s.buffering && _elapsed <= autoplayWindow) {
      nudgePlay();
    }

    // зависание: должно играть, а позиция не меняется
    final wants = s.playing || s.buffering;
    if (!wants || s.position != _lastPos) {
      _still = Duration.zero;
      _lastPos = s.position;
      return;
    }
    _still += dt;
    if (_still >= stallTimeout) {
      stop();
      _failed = true;
      onFail('зависание на ${s.position.inSeconds} с');
    }
  }
}
