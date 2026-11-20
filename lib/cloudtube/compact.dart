import 'package:flutter/widgets.dart';

import '../main.dart' show isTv;
import 'prefs.dart';

/// Компактный вид для невысоких экранов (магнитолы 7–9″ 1024×600, 1280×720, небольшие планшеты):
/// меню слева вместо нижней панели, низкая шапка, плитки каналов-«таблетки», 3 колонки роликов.
/// Решается на лету по текущему размеру окна: поворот, разделение экрана, окно в Windows.
enum CtCompactMode {
  auto('Авто'),
  on('Вкл'),
  off('Выкл');

  final String label;
  const CtCompactMode(this.label);
}

final ValueNotifier<CtCompactMode> ctCompactMode = ValueNotifier(CtCompactMode.auto);

/// Порог высоты (условные точки): ниже — экран «низкий».
const kCtCompactMaxHeight = 600.0;

CtCompactMode ctCompactModeFromPrefs() =>
    CtCompactMode.values.where((m) => m.name == CtPrefs.compactMode.value).firstOrNull ?? CtCompactMode.auto;

Future<void> ctSetCompactMode(CtCompactMode m) async {
  ctCompactMode.value = m;
  await CtPrefs.compactMode.set(m.name);
}

/// Включён ли компактный вид для текущего окна.
bool ctIsCompact(BuildContext context) {
  if (isTv) return false; // у ТВ свой интерфейс
  final s = MediaQuery.sizeOf(context);
  return switch (ctCompactMode.value) {
    CtCompactMode.on => true,
    CtCompactMode.off => false,
    // авто: горизонтальный и невысокий экран
    CtCompactMode.auto => s.width > s.height && s.height < kCtCompactMaxHeight,
  };
}
