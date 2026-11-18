import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../app/views/tv/screens/tv_home.dart' show ctOpenTvMenu, ctTvContentArea, ctTvMenuScope, ctTvLastContent;

/// Управление мышью (Bluetooth-мышь, аэромышь) на ТВ. Интерфейс ТВ построен на фокусе пульта,
/// поэтому мышь переводится в те же действия: наведение = фокус, клик = OK.
/// Один слой на всё приложение — отдельные экраны и кнопки менять не нужно.

/// Сейчас управляют мышью (true) или пультом (false).
final ctMouseActive = ValueNotifier<bool>(false);

/// Элемент сам обработал нажатие мыши (полоса перемотки, стрелки ряда) — общий «клик = OK» пропустить.
bool ctMouseSkipClick = false;

class CtTvMouse extends StatefulWidget {
  final Widget child;

  const CtTvMouse({super.key, required this.child});

  @override
  State<CtTvMouse> createState() => _CtTvMouseState();
}

class _CtTvMouseState extends State<CtTvMouse> {
  Offset? _down;
  DateTime _downAt = DateTime(2000);
  Offset? _rightDown;
  DateTime _lastHover = DateTime(2000);

  /// Фокусируемый элемент под курсором — только реально видимый (через hit-test:
  /// экраны под текущим и плитки под открытым меню не считаются).
  FocusNode? _nodeAt(Offset p, int viewId) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, p, viewId);
    final hit = <Object>{for (final e in result.path) e.target};
    FocusNode? best;
    double bestArea = double.infinity;
    for (final n in FocusManager.instance.rootScope.descendants) {
      if (n is FocusScopeNode || !n.canRequestFocus) continue;
      final ctx = n.context;
      if (ctx == null) continue;
      final ro = ctx.findRenderObject();
      if (ro == null || !ro.attached || !hit.contains(ro)) continue;
      final r = n.rect;
      final area = r.width * r.height;
      if (area < bestArea) {
        best = n;
        bestArea = area;
      }
    }
    return best;
  }

  bool _isText(FocusNode n) {
    final ctx = n.context;
    return ctx != null && (ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  bool _homeVisible(Size screen, int viewId) {
    final ro = ctTvContentArea.context?.findRenderObject();
    if (ro == null || !ro.attached) return false;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, screen.center(Offset.zero), viewId);
    return result.path.any((e) => identical(e.target, ro));
  }

  void _hover(PointerHoverEvent e) {
    if (e.kind != PointerDeviceKind.mouse) return;
    ctMouseActive.value = true;
    final now = DateTime.now();
    if (now.difference(_lastHover) < const Duration(milliseconds: 60)) return;
    _lastHover = now;
    final screen = MediaQuery.sizeOf(context);
    // курсор у левого края главного экрана — выезжает меню
    if (e.position.dx <= 4 && !ctTvMenuScope.hasFocus && _homeVisible(screen, e.viewId)) {
      ctTvLastContent = FocusManager.instance.primaryFocus;
      ctOpenTvMenu();
      return;
    }
    final n = _nodeAt(e.position, e.viewId);
    if (n == null || n.hasPrimaryFocus || _isText(n)) return;
    // фокус без прокрутки: плитки не должны уезжать из-под курсора
    n.requestFocus();
  }

  void _up(PointerUpEvent e) {
    final down = _down;
    _down = null;
    if (e.kind != PointerDeviceKind.mouse || down == null) return;
    if (ctMouseSkipClick) {
      ctMouseSkipClick = false;
      return;
    }
    if ((e.position - down).distance > 14) return; // это было перетаскивание списка
    final n = _nodeAt(e.position, e.viewId);
    if (n == null) return;
    // долгое нажатие левой кнопкой = кнопка «Меню» пульта (меню ролика: канал, подписка)
    if (DateTime.now().difference(_downAt) >= const Duration(milliseconds: 550) && !_isText(n)) {
      n.requestFocus();
      _send(n, LogicalKeyboardKey.contextMenu, PhysicalKeyboardKey.contextMenu, e.timeStamp);
      return;
    }
    if (_isText(n)) {
      n.requestFocus();
      return;
    }
    final screen = MediaQuery.sizeOf(context);
    // элемент во весь экран — это сам плеер: клик по видео = пауза/продолжить
    final whole = n.rect.width * n.rect.height > screen.width * screen.height * 0.7;
    if (!whole) n.requestFocus();
    final key = whole ? LogicalKeyboardKey.mediaPlayPause : LogicalKeyboardKey.select;
    _send(n, key, whole ? PhysicalKeyboardKey.mediaPlayPause : PhysicalKeyboardKey.select, e.timeStamp);
  }

  /// Как настоящее нажатие кнопки пульта: от элемента вверх по дереву, пока кто-то не обработает.
  void _send(FocusNode n, LogicalKeyboardKey key, PhysicalKeyboardKey phys, Duration ts) {
    final ev = KeyUpEvent(physicalKey: phys, logicalKey: key, timeStamp: ts);
    for (final t in [n, ...n.ancestors]) {
      if (t.onKeyEvent?.call(t, ev) == KeyEventResult.handled) break;
    }
  }

  /// Правая кнопка мыши = «Назад» пульта (как принято на Android TV):
  /// выйти из ролика, из канала, вернуться на главную, закрыть меню.
  void _back(PointerUpEvent e) {
    final down = _rightDown;
    _rightDown = null;
    if (down == null || (e.position - down).distance > 14) return;
    WidgetsBinding.instance.handlePopRoute();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      // мышью можно и тянуть списки, как пальцем
      behavior: const _CtDragScroll(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: _hover,
        onPointerDown: (e) {
          if (e.kind != PointerDeviceKind.mouse) return;
          ctMouseActive.value = true;
          _down = e.buttons == kPrimaryButton ? e.position : null;
          _downAt = DateTime.now();
          _rightDown = e.buttons == kSecondaryMouseButton ? e.position : null;
        },
        onPointerUp: (e) {
          if (e.kind != PointerDeviceKind.mouse) return;
          if (_rightDown != null) {
            _back(e);
          } else {
            _up(e);
          }
        },
        onPointerCancel: (_) {
          _down = null;
          _rightDown = null;
        },
        child: widget.child,
      ),
    );
  }
}

class _CtDragScroll extends MaterialScrollBehavior {
  const _CtDragScroll();

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}

/// Стрелки «‹ ›» по краям горизонтального ряда — видны только при управлении мышью.
class CtRowArrows extends StatelessWidget {
  final ScrollController controller;
  final Widget child;

  const CtRowArrows({super.key, required this.controller, required this.child});

  void _go(int dir) {
    if (!controller.hasClients) return;
    final p = controller.position;
    final to = (p.pixels + dir * p.viewportDimension * 0.8).clamp(p.minScrollExtent, p.maxScrollExtent);
    controller.animateTo(to, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  Widget _arrow(int dir) => Positioned(
        left: dir < 0 ? 0 : null,
        right: dir > 0 ? 0 : null,
        top: 0,
        bottom: 0,
        child: Center(
          child: Listener(
            onPointerDown: (_) {
              ctMouseSkipClick = true;
              _go(dir);
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: 44,
                height: 64,
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14)),
                child: Icon(dir < 0 ? Icons.chevron_left : Icons.chevron_right, color: Colors.white, size: 34),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ctMouseActive,
      child: child,
      builder: (context, mouse, child) =>
          Stack(clipBehavior: Clip.none, children: [child!, if (mouse) _arrow(-1), if (mouse) _arrow(1)]),
    );
  }
}
