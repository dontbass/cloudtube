import 'dart:ui' show FrameTiming;

import 'package:flutter/scheduler.dart';
import 'package:logging/logging.dart';

final _log = Logger('Скорость');

/// Замеры скорости — пишутся в «Журнал приложения» (Настройки → Журнал), чтобы сравнивать
/// версии на одном и том же устройстве:
/// - «Запуск: первый кадр» — от старта до появления интерфейса;
/// - «Запуск: первые ролики» — до первой загруженной страницы «Главной»;
/// - «Кадры» — сводка плавности за время прокрутки (сколько кадров не уложились в 16,7 мс).
class CtPerf {
  static final Stopwatch _start = Stopwatch();
  static bool _firstFrame = false, _firstVideos = false;

  static final List<int> _frames = []; // время кадра, мкс
  static DateTime _windowStart = DateTime.now();

  static void appStarted() {
    _start.start();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void firstFrame() {
    if (_firstFrame) return;
    _firstFrame = true;
    _log.info('Запуск: первый кадр ${_start.elapsedMilliseconds} мс');
  }

  static void firstVideos() {
    if (_firstVideos || !_start.isRunning) return;
    _firstVideos = true;
    _log.info('Запуск: первые ролики ${_start.elapsedMilliseconds} мс');
  }

  static void _onTimings(List<FrameTiming> timings) {
    final now = DateTime.now();
    // паузы дольше 3 с — новое «окно» активности (не смешиваем прокрутку и простой)
    if (_frames.isNotEmpty && now.difference(_windowStart) > const Duration(seconds: 30)) _flush();
    if (_frames.isEmpty) _windowStart = now;
    for (final t in timings) {
      _frames.add(t.totalSpan.inMicroseconds);
    }
  }

  static void _flush() {
    final f = List<int>.of(_frames);
    _frames.clear();
    if (f.length < 120) return; // меньше 2 секунд движения — не показательно
    f.sort();
    final slow = f.where((us) => us > 16700).length;
    final p90 = f[(f.length * 0.9).floor()] / 1000;
    final worst = f.last / 1000;
    _log.info('Кадры: ${f.length}, медленных ${(slow * 100 / f.length).toStringAsFixed(1)}%, '
        '90% кадров быстрее ${p90.toStringAsFixed(1)} мс, худший ${worst.toStringAsFixed(0)} мс');
  }
}
