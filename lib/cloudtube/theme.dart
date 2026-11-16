import 'package:flutter/material.dart';

/// Цвета CloudTube — те же, что у сайта (yt.css).
class CtColors {
  static const red = Color(0xFFFF0033);
  static const logoRed = Color(0xFFE85D4A);
}

const ColorScheme ctLightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF0F0F0F),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFF2F2F2),
  onPrimaryContainer: Color(0xFF0F0F0F),
  secondary: Color(0xFF606060),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFF2F2F2),
  onSecondaryContainer: Color(0xFF0F0F0F),
  tertiary: CtColors.red,
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFFFE5EA),
  onTertiaryContainer: Color(0xFF3A0010),
  error: Color(0xFFCC0000),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF0F0F0F),
  onSurfaceVariant: Color(0xFF606060),
  surfaceDim: Color(0xFFF2F2F2),
  surfaceBright: Color(0xFFFFFFFF),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF9F9F9),
  surfaceContainer: Color(0xFFF2F2F2),
  surfaceContainerHigh: Color(0xFFEDEDED),
  surfaceContainerHighest: Color(0xFFE5E5E5),
  outline: Color(0xFFCCCCCC),
  outlineVariant: Color(0xFFE5E5E5),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFF0F0F0F),
  onInverseSurface: Color(0xFFF1F1F1),
  inversePrimary: Color(0xFFF1F1F1),
  surfaceTint: Colors.transparent,
);

const ColorScheme ctDarkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFF1F1F1),
  onPrimary: Color(0xFF0F0F0F),
  primaryContainer: Color(0xFF272727),
  onPrimaryContainer: Color(0xFFF1F1F1),
  secondary: Color(0xFFAAAAAA),
  onSecondary: Color(0xFF0F0F0F),
  secondaryContainer: Color(0xFF272727),
  onSecondaryContainer: Color(0xFFF1F1F1),
  tertiary: CtColors.red,
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFF5C0016),
  onTertiaryContainer: Color(0xFFFFD9DF),
  error: Color(0xFFFF6B6B),
  onError: Color(0xFF0F0F0F),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF0F0F0F),
  onSurface: Color(0xFFF1F1F1),
  onSurfaceVariant: Color(0xFFAAAAAA),
  surfaceDim: Color(0xFF0F0F0F),
  surfaceBright: Color(0xFF272727),
  surfaceContainerLowest: Color(0xFF0A0A0A),
  surfaceContainerLow: Color(0xFF181818),
  surfaceContainer: Color(0xFF212121),
  surfaceContainerHigh: Color(0xFF272727),
  surfaceContainerHighest: Color(0xFF3F3F3F),
  outline: Color(0xFF3F3F3F),
  outlineVariant: Color(0xFF303030),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFFF1F1F1),
  onInverseSurface: Color(0xFF0F0F0F),
  inversePrimary: Color(0xFF0F0F0F),
  surfaceTint: Colors.transparent,
);

/// Акцент для переключателей, чекбоксов и фокуса пульта (синий, как у YouTube) —
/// хорошо виден и на белом, и на тёмном фоне.
Color ctAccent(ColorScheme c) =>
    c.brightness == Brightness.dark ? const Color(0xFF3EA6FF) : const Color(0xFF065FD4);

/// Рамка выделения для Android TV: заметная рамка вокруг элемента в фокусе.
/// Прозрачная рамка той же толщины без фокуса — чтобы элемент не «прыгал».
BoxBorder ctFocusBorder(ColorScheme c, bool focused) =>
    Border.all(color: focused ? ctAccent(c) : Colors.transparent, width: 3);

/// Чекбоксы, переключатели и радиокнопки, заметные в любой теме.
CheckboxThemeData ctCheckboxTheme(ColorScheme c) => CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? ctAccent(c) : Colors.transparent),
      checkColor: WidgetStatePropertyAll(c.brightness == Brightness.dark ? Colors.black : Colors.white),
      side: WidgetStateBorderSide.resolveWith((s) => BorderSide(
          color: s.contains(WidgetState.selected) ? ctAccent(c) : c.onSurfaceVariant, width: 2)),
    );

SwitchThemeData ctSwitchTheme(ColorScheme c) => SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? Colors.white
          : (c.brightness == Brightness.dark ? const Color(0xFFBDBDBD) : const Color(0xFF8A8A8A))),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? ctAccent(c)
          : (c.brightness == Brightness.dark ? const Color(0xFF4A4A4A) : const Color(0xFFDADADA))),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    );

RadioThemeData ctRadioTheme(ColorScheme c) => RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? ctAccent(c) : c.onSurfaceVariant),
    );

// ---------------- Промежуточные темы ----------------
/// «Мягкая»: светлая, но не белая — тёплый светло-серый фон.
final ColorScheme ctSoftScheme = ctLightScheme.copyWith(
  surface: const Color(0xFFEDEBE7),
  surfaceBright: const Color(0xFFF5F3EF),
  surfaceDim: const Color(0xFFE2DFD9),
  surfaceContainerLowest: const Color(0xFFF5F3EF),
  surfaceContainerLow: const Color(0xFFE7E4DF),
  surfaceContainer: const Color(0xFFE0DDD7),
  surfaceContainerHigh: const Color(0xFFD9D6D0),
  surfaceContainerHighest: const Color(0xFFD1CEC7),
  primaryContainer: const Color(0xFFDDDAD4),
  secondaryContainer: const Color(0xFFDDDAD4),
  outline: const Color(0xFFBDB9B2),
  outlineVariant: const Color(0xFFD1CEC7),
  onSurface: const Color(0xFF1C1B19),
  onSurfaceVariant: const Color(0xFF55524D),
);

/// «Сумерки»: тёмная, но не чёрная — графитово-серый фон, мягче для глаз.
final ColorScheme ctDimScheme = ctDarkScheme.copyWith(
  surface: const Color(0xFF26282C),
  surfaceDim: const Color(0xFF202226),
  surfaceBright: const Color(0xFF3A3D42),
  surfaceContainerLowest: const Color(0xFF1E2023),
  surfaceContainerLow: const Color(0xFF2B2D31),
  surfaceContainer: const Color(0xFF303237),
  surfaceContainerHigh: const Color(0xFF373A3F),
  surfaceContainerHighest: const Color(0xFF45484E),
  primaryContainer: const Color(0xFF3A3D42),
  secondaryContainer: const Color(0xFF3A3D42),
  outline: const Color(0xFF55585E),
  outlineVariant: const Color(0xFF45484E),
  onSurface: const Color(0xFFE8E8E8),
  onSurfaceVariant: const Color(0xFFB0B2B6),
);

/// true — промежуточный вариант текущей яркости (мягкая светлая / сумерки).
final ValueNotifier<bool> ctSoftTheme = ValueNotifier(false);
const ctSoftThemeKey = 'ct-theme-soft';

/// Темы по кругу для кнопки в шапке.
enum CtTheme {
  light('Светлая', Icons.light_mode_outlined),
  soft('Мягкая', Icons.wb_twilight_outlined),
  dim('Сумерки', Icons.nights_stay_outlined),
  dark('Тёмная', Icons.dark_mode_outlined);

  final String label;
  final IconData icon;
  const CtTheme(this.label, this.icon);

  bool get isDark => this == dim || this == dark;
  bool get isSoft => this == soft || this == dim;
  CtTheme get next => CtTheme.values[(index + 1) % CtTheme.values.length];

  static CtTheme of(bool darkNow, bool soft) =>
      darkNow ? (soft ? dim : dark) : (soft ? CtTheme.soft : light);
}


/// Все всплывающие подсказки (SnackBar): тёмная плашка со скруглёнными углами, белый текст —
/// одинаково читается в светлой, мягкой и тёмной темах.
const ctSnackBarTheme = SnackBarThemeData(
  behavior: SnackBarBehavior.floating,
  backgroundColor: Color(0xF0202124),
  contentTextStyle: TextStyle(color: Colors.white, fontSize: 15),
  actionTextColor: Color(0xFF8AB4F8),
  elevation: 6,
  insetPadding: EdgeInsets.fromLTRB(24, 0, 24, 24),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
);
