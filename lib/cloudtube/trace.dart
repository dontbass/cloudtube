import 'package:logging/logging.dart';

final _log = Logger('CtTrace');

/// Ход открытия видео (клиенты YouTube, выбранный поток, сбои) — только в журнал приложения.
/// Экран «Проверка скорости», где это показывалось, убран: он был нужен для отладки.
class CtTrace {
  static void start(String what) => _log.fine(what);

  static void mark(String what) => _log.fine(what);
}
