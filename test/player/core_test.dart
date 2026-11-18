import 'package:cloudtube/player/core/recovery.dart';
import 'package:cloudtube/player/core/watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

const step = Duration(milliseconds: 500);

void main() {
  group('сторож воспроизведения', () {
    late PlaybackSnapshot? snap;
    late List<String> fails;
    late int nudges;
    late CtPlaybackWatchdog w;

    setUp(() {
      snap = null;
      fails = [];
      nudges = 0;
      w = CtPlaybackWatchdog(read: () => snap, nudgePlay: () => nudges++, onFail: fails.add);
    });

    void run(Duration d) {
      for (var t = Duration.zero; t < d; t += step) {
        w.tick(step);
      }
    }

    PlaybackSnapshot s({bool playing = true, bool buffering = false, int pos = 0}) => PlaybackSnapshot(
        initialized: true, playing: playing, buffering: buffering, position: Duration(seconds: pos));

    test('поток не открылся за 25 с — сбой', () {
      run(const Duration(seconds: 24));
      expect(fails, isEmpty);
      run(const Duration(seconds: 1));
      expect(fails.single, contains('не открылся'));
    });

    test('готов, но стоит — подталкивает к запуску, пока не нажата пауза', () {
      snap = s(playing: false);
      run(const Duration(seconds: 2));
      expect(nudges, greaterThan(0));
      final n = nudges;
      w.userPaused = true;
      run(const Duration(seconds: 2));
      expect(nudges, n);
    });

    test('после устойчивого показа автозапуск не вмешивается', () {
      snap = s(pos: 1);
      run(const Duration(seconds: 4));
      snap = s(playing: false, pos: 5);
      run(const Duration(seconds: 2));
      expect(nudges, 0);
    });

    test('картинка стоит 12 с при воспроизведении — зависание', () {
      for (var i = 0; i < 10; i++) {
        snap = s(pos: i);
        w.tick(const Duration(seconds: 1));
      }
      expect(fails, isEmpty);
      snap = s(pos: 10, buffering: true, playing: false);
      run(const Duration(seconds: 13));
      expect(fails.single, contains('зависание'));
    });

    test('пауза — не зависание', () {
      snap = s(playing: false, pos: 7);
      w.userPaused = true;
      run(const Duration(seconds: 30));
      expect(fails, isEmpty);
    });
  });

  group('правила восстановления', () {
    final t0 = DateTime(2026, 1, 1);

    test('ТВ без сервера: тот же поток → HLS → ниже → … → сдаться', () {
      final p = CtRecoveryPolicy();
      CtRecovery f(int i, {bool own = true}) => p.onFailure('a', tvDirect: true, ownDash: own, now: t0.add(Duration(seconds: i)));
      expect(f(1), CtRecovery.retrySame);
      expect(f(2), CtRecovery.switchToHls);
      expect(f(3, own: false), CtRecovery.lowerQuality);
      expect(f(4, own: false), CtRecovery.lowerQuality);
      expect(f(5, own: false), CtRecovery.lowerQuality);
      expect(f(6, own: false), CtRecovery.lowerQuality);
      expect(f(7, own: false), CtRecovery.giveUp);
    });

    test('свой сервер с DASH: тот же поток → обычный поток → ещё раз → сдаться', () {
      final p = CtRecoveryPolicy();
      CtRecovery f(int i) => p.onFailure('a', tvDirect: false, usingDash: true, now: t0.add(Duration(seconds: i)));
      expect(f(1), CtRecovery.retrySame);
      expect(f(2), CtRecovery.progressive);
      expect(f(3), CtRecovery.retrySame);
      expect(f(4), CtRecovery.giveUp);
    });

    test('после 3 минут спокойного показа счёт с нуля; у другого ролика — свой счёт', () {
      final p = CtRecoveryPolicy();
      p.onFailure('a', tvDirect: false, now: t0);
      p.onFailure('a', tvDirect: false, now: t0.add(const Duration(seconds: 10)));
      expect(p.fails, 2);
      p.onFailure('a', tvDirect: false, now: t0.add(const Duration(minutes: 4)));
      expect(p.fails, 1);
      expect(p.onFailure('b', tvDirect: false, now: t0.add(const Duration(minutes: 4, seconds: 1))), CtRecovery.retrySame);
    });

    test('ниже некуда — перезапуск того же', () {
      final p = CtRecoveryPolicy();
      p.onFailure('a', tvDirect: true, now: t0);
      expect(p.onFailure('a', tvDirect: true, canLower: false, now: t0.add(const Duration(seconds: 1))), CtRecovery.retrySame);
    });
  });
}
