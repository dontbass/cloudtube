import 'dart:async';
import 'dart:io';

import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:logging/logging.dart';

import '../main.dart' show isTv;
import 'prefs.dart';

final _log = Logger('CtAfr');

/// Автопереключение частоты экрана под видео (AFR), как в OTT Navigator / Kodi:
/// эфирные каналы 25/50 кадров на экране 60 Гц идут рывками (особенно спорт и бегущая строка),
/// поэтому на время видео — 50 Гц, для 30/60 — 60 Гц, для 24 — 24 Гц (если телевизор умеет).
/// Только на ТВ (Android); после видео — прежний режим. Выключается в настройках.
class CtAfr {
  static DisplayMode? _orig;
  static double? _cur;
  static Timer? _pending;

  static bool get enabled => isTv && Platform.isAndroid && CtPrefs.afr.value;

  /// Частоты экрана, подходящие для [fps], в порядке предпочтения.
  static List<double> _targets(double fps) {
    if (fps <= 0) return const [];
    if ((fps - 23.976).abs() < 0.2 || (fps - 24).abs() < 0.2) return const [23.976, 24, 48];
    if ((fps - 25).abs() < 0.3 || (fps - 50).abs() < 0.5) return const [50, 25];
    if ((fps - 29.97).abs() < 0.2 || (fps - 59.94).abs() < 0.3) return const [59.94, 60, 29.97, 30];
    if ((fps - 30).abs() < 0.2 || (fps - 60).abs() < 0.5) return const [60, 59.94, 30];
    return const [];
  }

  static Future<void> forFps(double fps) async {
    if (!enabled) return;
    // следующий ролик/канал сразу за предыдущим — возврат частоты отменяется (иначе экран моргнёт дважды)
    _pending?.cancel();
    _pending = null;
    final targets = _targets(fps);
    if (targets.isEmpty || (_cur != null && targets.any((t) => (t - _cur!).abs() < 0.05))) return;
    try {
      final modes = await FlutterDisplayMode.supported;
      final active = await FlutterDisplayMode.active;
      _orig ??= active;
      final base = _orig!;
      for (final t in targets) {
        final m = modes
            .where((m) => m.width == base.width && m.height == base.height && (m.refreshRate - t).abs() < 0.05)
            .firstOrNull;
        if (m == null) continue;
        if ((active.refreshRate - m.refreshRate).abs() < 0.05) {
          _cur = m.refreshRate;
          return;
        }
        _log.info('частота экрана ${active.refreshRate} → ${m.refreshRate} Гц (видео $fps к/с)');
        await FlutterDisplayMode.setPreferredMode(m);
        _cur = m.refreshRate;
        return;
      }
    } catch (e) {
      _log.warning('afr: $e');
    }
  }

  /// Вернуть режим, который был до видео — через 1,5 с: если тут же начнётся следующее видео
  /// с той же частотой, экран не переключается туда-обратно.
  static Future<void> restore() async {
    if (_orig == null) return;
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 1500), () {
      _pending = null;
      unawaited(_restoreNow());
    });
  }

  static Future<void> _restoreNow() async {
    final o = _orig;
    _orig = null;
    _cur = null;
    if (o == null) return;
    try {
      await FlutterDisplayMode.setPreferredMode(o);
    } catch (e) {
      _log.warning('afr restore: $e');
    }
  }
}
