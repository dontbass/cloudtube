/// Что делать после сбоя воспроизведения.
enum CtRecovery {
  /// Тот же поток со свежими ссылками, с той же секунды.
  retrySame,

  /// ТВ без сервера: со своего DASH на HLS того же качества.
  switchToHls,

  /// ТВ без сервера: ступенью ниже (только для этого ролика).
  lowerQuality,

  /// Со своим сервером: обычный поток вместо DASH.
  progressive,

  /// Больше не пробуем — показываем ошибку.
  giveUp,
}

/// Правила восстановления после сбоев — одни для всех режимов (раньше было два разных
/// обработчика). Счётчик сбоев свой у каждого ролика и сбрасывается после [resetAfter]
/// спокойного показа: редкие сбои в длинном видео не копятся до «сдаться».
class CtRecoveryPolicy {
  final Duration resetAfter;
  final int maxFails;

  CtRecoveryPolicy({this.resetAfter = const Duration(minutes: 3), this.maxFails = 6});

  String? _id;
  int _fails = 0;
  DateTime _last = DateTime(2000);

  int get fails => _fails;

  /// Новый ролик или ручной выбор формата — счёт с нуля.
  void reset([String? id]) {
    _id = id;
    _fails = 0;
  }

  /// Учесть сбой ролика [id] и решить, что делать.
  /// [tvDirect] — ТВ без сервера (своё качество), [ownDash] — сейчас играет свой DASH,
  /// [usingDash] — DASH сервера Invidious, [canLower] — есть качество ниже текущего.
  CtRecovery onFailure(
    String id, {
    required bool tvDirect,
    bool ownDash = false,
    bool usingDash = false,
    bool canLower = true,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    if (_id != id || t.difference(_last) > resetAfter) _fails = 0;
    _id = id;
    _last = t;
    _fails++;

    if (_fails > (tvDirect ? maxFails : 3)) return CtRecovery.giveUp;
    if (_fails == 1) return CtRecovery.retrySame;
    if (tvDirect) {
      if (_fails == 2 && ownDash) return CtRecovery.switchToHls;
      return canLower ? CtRecovery.lowerQuality : CtRecovery.retrySame;
    }
    if (_fails == 2 && usingDash) return CtRecovery.progressive;
    return CtRecovery.retrySame;
  }
}
