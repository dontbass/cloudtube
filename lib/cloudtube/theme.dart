import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

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
Color ctAccent(ColorScheme c) => c.brightness == Brightness.dark
    ? (c.surface == ctGlassDarkBase ? const Color(0xFFFF4D6D) : const Color(0xFF3EA6FF))
    : (c.surface == ctPaperSurface
        ? ctPaperTerracotta
        : (c.surface == ctGlassLightBase ? const Color(0xFFE0002D) : const Color(0xFF065FD4)));

/// Рамка выделения для Android TV: заметная рамка вокруг элемента в фокусе.
/// Прозрачная рамка той же толщины без фокуса — чтобы элемент не «прыгал».
BoxBorder ctFocusBorder(ColorScheme c, bool focused) =>
    Border.all(color: focused ? ctAccent(c) : Colors.transparent, width: 3);

/// Чекбоксы, переключатели и радиокнопки, заметные в любой теме.
CheckboxThemeData ctCheckboxTheme(ColorScheme c) => CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? ctAccent(c) : Colors.transparent),
      checkColor: WidgetStatePropertyAll(
          c.brightness == Brightness.dark ? Colors.black : (ctIsPaper(c) ? ctPaperSurface : Colors.white)),
      side: WidgetStateBorderSide.resolveWith((s) => BorderSide(
          color: s.contains(WidgetState.selected) ? ctAccent(c) : c.onSurfaceVariant, width: 2)),
    );

SwitchThemeData ctSwitchTheme(ColorScheme c) => SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? (ctIsPaper(c) ? ctPaperSurface : Colors.white)
          : (c.brightness == Brightness.dark ? const Color(0xFFBDBDBD) : const Color(0xFF8A8A8A))),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? ctAccent(c)
          : (c.brightness == Brightness.dark
              ? const Color(0xFF4A4A4A)
              : (ctIsPaper(c) ? const Color(0xFFDECFB4) : const Color(0xFFDADADA)))),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    );

RadioThemeData ctRadioTheme(ColorScheme c) => RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? ctAccent(c) : c.onSurfaceVariant),
    );

// ---------------- Промежуточные темы ----------------
/// «Пергамент»: старая бумага, бережёт глаза. Ни чистого белого, ни чистого чёрного:
/// фон — тёплый крем #F4EFE6, текст — тёплый уголь #2C251E; остальные поверхности —
/// тот же оттенок (38°) темнее на 4–6 % по светлоте; акценты приглушённые, землистые
/// (терракота #8C4A27). Сверху — едва заметное «зерно» бумаги ([CtPaperGrain]).
const ctPaperSurface = Color(0xFFF4EFE6);
const ctPaperText = Color(0xFF2C251E);
const ctPaperTerracotta = Color(0xFF8C4A27);
const ctPaperForest = Color(0xFF3D5A45);
const ctPaperInk = Color(0xFF2F4858);

final ColorScheme ctSoftScheme = ctLightScheme.copyWith(
  primary: ctPaperText,
  onPrimary: ctPaperSurface,
  primaryContainer: const Color(0xFFE8DDCA),
  onPrimaryContainer: ctPaperText,
  secondary: const Color(0xFF6B5E50),
  onSecondary: ctPaperSurface,
  secondaryContainer: const Color(0xFFE8DDCA),
  onSecondaryContainer: ctPaperText,
  tertiary: ctPaperTerracotta,
  onTertiary: ctPaperSurface,
  tertiaryContainer: const Color(0xFFEBD3C4),
  onTertiaryContainer: const Color(0xFF3B1B0A),
  error: const Color(0xFF9E3A2B),
  onError: ctPaperSurface,
  surface: ctPaperSurface,
  onSurface: ctPaperText,
  onSurfaceVariant: const Color(0xFF6B5E50),
  surfaceBright: const Color(0xFFF7F3EC),
  surfaceDim: const Color(0xFFE8DDCA),
  surfaceContainerLowest: const Color(0xFFF7F3EC),
  surfaceContainerLow: const Color(0xFFF1EADF),
  surfaceContainer: const Color(0xFFEEE6D8),
  surfaceContainerHigh: const Color(0xFFEBE1D1),
  surfaceContainerHighest: const Color(0xFFE4D8C3),
  outline: const Color(0xFFC9BBA4),
  outlineVariant: const Color(0xFFDECFB4),
  inverseSurface: ctPaperText,
  onInverseSurface: ctPaperSurface,
  inversePrimary: ctPaperSurface,
);

/// Включена ли «Пергамент» (по палитре).
bool ctIsPaper(ColorScheme c) => c.brightness == Brightness.light && c.surface == ctPaperSurface;

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

/// Вариант оформления при той же яркости: обычный / мягкий (пергамент, сумерки) / стекло.
enum CtVariant { normal, soft, glass }

final ValueNotifier<CtVariant> ctThemeVariant = ValueNotifier(CtVariant.normal);

/// Темы по кругу для кнопки в шапке и пункта в настройках ТВ.
enum CtTheme {
  light('Светлая', Icons.light_mode_outlined, false, CtVariant.normal),
  soft('Пергамент', Icons.history_edu_outlined, false, CtVariant.soft),
  glassLight('Стекло светлое', Icons.water_drop_outlined, false, CtVariant.glass),
  dim('Сумерки', Icons.nights_stay_outlined, true, CtVariant.soft),
  dark('Тёмная', Icons.dark_mode_outlined, true, CtVariant.normal),
  glassDark('Стекло тёмное', Icons.bubble_chart_outlined, true, CtVariant.glass);

  final String label;
  final IconData icon;
  final bool isDark;
  final CtVariant variant;
  const CtTheme(this.label, this.icon, this.isDark, this.variant);

  CtTheme get next => CtTheme.values[(index + 1) % CtTheme.values.length];

  static CtTheme of(bool darkNow, CtVariant v) =>
      CtTheme.values.firstWhere((t) => t.isDark == darkNow && t.variant == v);
}

// ================= «Стекло» (liquid glass) =================
// Три базовых цвета — красный CloudTube, фиолетовый, сине-голубой: из них цветные пятна фона
// (стеклу нужно, что «преломлять»), блики и акценты. Перекрасить тему — поменять эти три значения.
const ctGlassRed = CtColors.red;
const ctGlassViolet = Color(0xFF7B2FF7);
const ctGlassBlue = Color(0xFF1FA2FF);

/// Основа под пятнами (на ней же — непрозрачный фон там, где он нужен).
const ctGlassDarkBase = Color(0xFF0C0A12);
const ctGlassLightBase = Color(0xFFF3F0F6);

bool ctIsGlass(ColorScheme c) => c.surface == ctGlassDarkBase || c.surface == ctGlassLightBase;

/// Фон страниц/списков: в «Стекле» — прозрачный (видно пятна), иначе обычный.
Color ctBg(ColorScheme c) => ctIsGlass(c) ? Colors.transparent : c.surface;

// Поверхности — полупрозрачная «вставка» на стекле (без собственного размытия).
final ColorScheme ctGlassDarkScheme = ctDarkScheme.copyWith(
  surface: ctGlassDarkBase,
  surfaceDim: ctGlassDarkBase,
  surfaceBright: const Color(0x33FFFFFF),
  surfaceContainerLowest: const Color(0x0AFFFFFF),
  surfaceContainerLow: const Color(0x0FFFFFFF),
  surfaceContainer: const Color(0x14FFFFFF),
  surfaceContainerHigh: const Color(0x1CFFFFFF),
  surfaceContainerHighest: const Color(0x26FFFFFF),
  primaryContainer: const Color(0x1FFFFFFF),
  secondaryContainer: const Color(0x24FFFFFF),
  tertiaryContainer: const Color(0x40FF0033),
  outline: const Color(0x40FFFFFF),
  outlineVariant: const Color(0x24FFFFFF),
  onSurface: const Color(0xFFF5F3F8),
  onSurfaceVariant: const Color(0xFFC2BCCB),
);

final ColorScheme ctGlassLightScheme = ctLightScheme.copyWith(
  surface: ctGlassLightBase,
  surfaceDim: const Color(0xFFE6E1EC),
  surfaceBright: const Color(0xCCFFFFFF),
  surfaceContainerLowest: const Color(0x8CFFFFFF),
  surfaceContainerLow: const Color(0x99FFFFFF),
  surfaceContainer: const Color(0xA6FFFFFF),
  surfaceContainerHigh: const Color(0xB3FFFFFF),
  surfaceContainerHighest: const Color(0xC7FFFFFF),
  primaryContainer: const Color(0xB3FFFFFF),
  secondaryContainer: const Color(0xBFFFFFFF),
  tertiaryContainer: const Color(0x33FF0033),
  outline: const Color(0x33201A2B),
  outlineVariant: const Color(0x1F201A2B),
  onSurface: const Color(0xFF17131F),
  onSurfaceVariant: const Color(0xFF574F63),
);

/// Матовая панель поверх содержимого (меню, диалоги, шторки, верхняя панель):
/// почти непрозрачная, чтобы текст читался над любыми превью.
Color ctGlassPanel(ColorScheme c) =>
    c.brightness == Brightness.dark ? const Color(0xE61A1724) : const Color(0xEBFBFAFD);

/// Прозрачность «поверх» цвета: в «Стекле» поверхности уже полупрозрачные, и прямое
/// withValues(alpha: 0.97) превращало белую дымку 8 % в почти непрозрачный белый.
Color ctAlpha(Color c, double a) => c.withValues(alpha: c.a * a);

/// Светлый блик по верхнему краю стекла.
BorderSide ctGlassEdge(ColorScheme c) => BorderSide(
    color: c.brightness == Brightness.dark ? const Color(0x2EFFFFFF) : const Color(0xB3FFFFFF), width: 1);

/// Цветные пятна под интерфейсом «Стекла»: три размытых пятна из базовых цветов на основе.
/// Рисуется один раз (статично, без анимации) — не тратит батарею и не грузит ТВ-приставку.
class CtGlassBackdrop extends StatelessWidget {
  final Widget child;
  const CtGlassBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(fit: StackFit.passthrough, children: [
      Positioned.fill(
        child: RepaintBoundary(child: CustomPaint(painter: _AuraPainter(dark), isComplex: true)),
      ),
      child,
    ]);
  }
}

class _AuraPainter extends CustomPainter {
  final bool dark;
  const _AuraPainter(this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = dark ? ctGlassDarkBase : ctGlassLightBase);
    final big = size.longestSide;
    void blob(Offset c, double radius, Color color, double alpha) {
      canvas.drawRect(
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * 0.45),
              color.withValues(alpha: 0),
            ], stops: const [0, 0.45, 1])
                .createShader(Rect.fromCircle(center: c, radius: radius)));
    }

    // светлая тема: пятна бледнее (на белом стекле насыщенный цвет «кричит»)
    final k = dark ? 1.0 : 0.55;
    blob(Offset(size.width * 0.05, size.height * 0.08), big * 0.55, ctGlassRed, 0.42 * k);
    blob(Offset(size.width * 0.98, size.height * 0.35), big * 0.5, ctGlassViolet, 0.40 * k);
    blob(Offset(size.width * 0.25, size.height * 0.98), big * 0.6, ctGlassBlue, 0.32 * k);
  }

  @override
  bool shouldRepaint(_AuraPainter old) => old.dark != dark;
}

/// Переходы между экранами в «Стекле»: каждый экран несёт свои пятна (непрозрачен),
/// иначе во время перехода сквозь прозрачный фон новой страницы видна старая.
class CtGlassPageTransitions extends PageTransitionsBuilder {
  final PageTransitionsBuilder inner;
  const CtGlassPageTransitions(this.inner);

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      inner.buildTransitions(route, context, animation, secondaryAnimation, CtGlassBackdrop(child: child));
}

/// Добавки темы для «Стекла»: прозрачный фон экранов, матовые панели, блик по краю.
ThemeData ctGlassTheme(ThemeData t) {
  final c = t.colorScheme;
  if (!ctIsGlass(c)) return t;
  final panel = ctGlassPanel(c);
  final edge = ctGlassEdge(c);
  RoundedRectangleBorder shape(double r) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(r), side: edge);
  const base = PageTransitionsTheme();
  return t.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: panel,
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      for (final p in TargetPlatform.values)
        p: CtGlassPageTransitions(base.builders[p] ?? const ZoomPageTransitionsBuilder()),
    }),
    appBarTheme: t.appBarTheme.copyWith(
        backgroundColor: c.brightness == Brightness.dark ? const Color(0xCC1A1724) : const Color(0xD9FBFAFD)),
    navigationBarTheme: t.navigationBarTheme.copyWith(
        backgroundColor: c.brightness == Brightness.dark ? const Color(0x80140F1C) : const Color(0x99FFFFFF)),
    navigationRailTheme: t.navigationRailTheme.copyWith(backgroundColor: Colors.transparent),
    cardTheme: CardThemeData(color: c.surfaceContainer, elevation: 0, shape: shape(16)),
    dialogTheme: DialogThemeData(backgroundColor: panel, shape: shape(24)),
    bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: panel,
        modalBackgroundColor: panel,
        shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)), side: edge)),
    popupMenuTheme: PopupMenuThemeData(color: panel, shape: shape(16)),
    menuTheme: MenuThemeData(
        style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(panel),
            shape: WidgetStatePropertyAll(shape(16)))),
    chipTheme: t.chipTheme.copyWith(backgroundColor: c.surfaceContainerHigh, side: edge),
    dividerTheme: DividerThemeData(color: c.outlineVariant),
    timePickerTheme: t.timePickerTheme.copyWith(backgroundColor: panel, shape: shape(24)),
    datePickerTheme: t.datePickerTheme.copyWith(backgroundColor: panel, shape: shape(24)),
    snackBarTheme: t.snackBarTheme,
  );
}


/// Все всплывающие подсказки (SnackBar): тёмная плашка со скруглёнными углами, белый текст —
/// одинаково читается в светлой, пергаментной и тёмной темах.
const ctSnackBarTheme = SnackBarThemeData(
  behavior: SnackBarBehavior.floating,
  backgroundColor: Color(0xF0202124),
  contentTextStyle: TextStyle(color: Colors.white, fontSize: 15),
  actionTextColor: Color(0xFF8AB4F8),
  elevation: 6,
  insetPadding: EdgeInsets.fromLTRB(24, 0, 24, 24),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
);


/// «Зерно» бумаги для темы «Пергамент»: шум, нарисованный один раз в небольшую текстуру
/// и замощённый на весь экран; не ловит нажатия, непрозрачность ~3 % — текст не страдает.
class CtPaperGrain extends StatefulWidget {
  final Widget child;

  const CtPaperGrain({super.key, required this.child});

  @override
  State<CtPaperGrain> createState() => _CtPaperGrainState();
}

ui.Image? _ctGrain;
Future<ui.Image>? _ctGrainFut;

/// Шум «как fractalNoise»: две октавы — крупные пятна и мелкое зерно.
Future<ui.Image> _makeGrain() {
  const n = 160;
  final rnd = math.Random(7);
  final coarse = List.generate(41 * 41, (_) => rnd.nextDouble());
  double c(int x, int y) {
    // билинейно сглаженная крупная октава (шаг 4 пикселя), бесшовная по краям
    final fx = x / 4, fy = y / 4;
    final x0 = fx.floor() % 40, y0 = fy.floor() % 40;
    final x1 = (x0 + 1) % 40, y1 = (y0 + 1) % 40;
    final tx = fx - fx.floor(), ty = fy - fy.floor();
    double v(int a, int b) => coarse[b * 41 + a];
    final top = v(x0, y0) * (1 - tx) + v(x1, y0) * tx;
    final bot = v(x0, y1) * (1 - tx) + v(x1, y1) * tx;
    return top * (1 - ty) + bot * ty;
  }

  final px = Uint8List(n * n * 4);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final noise = 0.55 * c(x, y) + 0.45 * rnd.nextDouble();
      final i = (y * n + x) * 4;
      // тёплый уголь, прозрачность 0..~6 % (в среднем ~3 %)
      px[i] = 0x2C;
      px[i + 1] = 0x25;
      px[i + 2] = 0x1E;
      px[i + 3] = (noise * 15).round();
    }
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, n, n, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

class _CtPaperGrainState extends State<CtPaperGrain> {
  @override
  void initState() {
    super.initState();
    if (_ctGrain == null) {
      (_ctGrainFut ??= _makeGrain()).then((img) {
        _ctGrain = img;
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _ctGrain;
    return Stack(textDirection: TextDirection.ltr, children: [
      widget.child,
      if (img != null)
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(child: CustomPaint(painter: _GrainPainter(img))),
          ),
        ),
    ]);
  }
}

class _GrainPainter extends CustomPainter {
  final ui.Image img;

  _GrainPainter(this.img);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = ImageShader(img, TileMode.repeated, TileMode.repeated, Matrix4.identity().storage);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.img != img;
}
