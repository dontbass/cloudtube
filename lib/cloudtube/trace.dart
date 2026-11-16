/// Хронометраж последнего открытия видео: метки времени от нажатия до начала воспроизведения.
/// Показывается в «Проверке скорости» — так видно, на каком шаге теряется время на устройстве.
class CtTrace {
  static DateTime? _t0;
  static final List<(int, String)> marks = [];

  static void start(String what) {
    _t0 = DateTime.now();
    marks
      ..clear()
      ..add((0, what));
  }

  static void mark(String what) {
    final t0 = _t0;
    if (t0 == null || marks.length > 60) return;
    final ms = DateTime.now().difference(t0).inMilliseconds;
    if (ms > 60000) return;
    marks.add((ms, what));
  }

  static String report() => marks.map((m) => '${m.$1.toString().padLeft(6)} мс  ${m.$2}').join('\n');
}
