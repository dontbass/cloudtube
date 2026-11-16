import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/views/tv/screens/tv_home.dart' show ctOpenTvMenu, ctTvLastContent;

/// ТВ: стоим ли на самом левом элементе (слева в том же ряду фокусироваться не на что
/// и горизонтальная лента прокручена до начала).
bool ctTvAtLeftEdge(FocusNode area) {
  final cur = FocusManager.instance.primaryFocus;
  if (cur == null) return false;
  final ctx = cur.context;
  // в поле ввода стрелка двигает курсор
  if (ctx != null && (ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null)) {
    return false;
  }
  if (ctx != null) {
    final sc = Scrollable.maybeOf(ctx);
    // у ряда есть отступы (чтобы рамка фокуса не обрезалась): после возврата влево он встаёт
    // не на 0, а на несколько пикселей — раньше из-за этого меню больше не открывалось
    if (sc != null &&
        sc.axisDirection == AxisDirection.right &&
        sc.position.pixels > sc.position.minScrollExtent + 32) {
      return false;
    }
  }
  final r = cur.rect;
  for (final n in area.descendants) {
    if (identical(n, cur) || n is FocusScopeNode || !n.canRequestFocus || n.skipTraversal) continue;
    final q = n.rect;
    if (q.isEmpty) continue;
    // левее и в том же ряду (перекрываются по высоте хотя бы наполовину)
    final overlap = (q.bottom < r.bottom ? q.bottom : r.bottom) - (q.top > r.top ? q.top : r.top);
    if (q.right <= r.left + 2 && overlap > r.height * 0.4) return false;
  }
  return true;
}

/// Обёртка экрана ТВ: стрелка «влево» на самом левом элементе открывает боковое меню.
/// На вложенных экранах (сетка раздела, канал, поиск, плейлист) — возвращает на главный экран
/// и сразу открывает меню. Кнопка «Назад» для этого не нужна.
class CtTvLeftEdge extends StatelessWidget {
  final Widget child;
  final bool popRoute;

  const CtTvLeftEdge({super.key, required this.child, this.popRoute = true});

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.arrowLeft) return KeyEventResult.ignored;
        if (!ctTvAtLeftEdge(node)) return KeyEventResult.ignored; // обычный переход влево
        if (popRoute) {
          ctTvLastContent = null;
          Navigator.of(context).maybePop().then((_) {
            WidgetsBinding.instance.addPostFrameCallback((_) => ctOpenTvMenu());
          });
        } else {
          ctTvLastContent = FocusManager.instance.primaryFocus;
          ctOpenTvMenu();
        }
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}


/// Переход фокуса стрелками с плавной прокруткой. Во Flutter по умолчанию ряд/список при
/// переходе на плитку за краем экрана перескакивает без анимации — отсюда рывки.
/// Здесь — короткая плавная прокрутка; при зажатой стрелке новая подхватывает текущую.
void ctTvRequestFocus(FocusNode node,
    {ScrollPositionAlignmentPolicy? alignmentPolicy, double? alignment, Duration? duration, Curve? curve}) {
  node.requestFocus();
  final ctx = node.context;
  if (ctx == null) return;
  Scrollable.ensureVisible(ctx,
      alignment: alignment ?? 1.0,
      alignmentPolicy: alignmentPolicy ?? ScrollPositionAlignmentPolicy.explicit,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic);
}

/// Обёртка всего приложения на ТВ: плавные переходы стрелками на всех экранах.
class CtTvSmoothTraversal extends StatelessWidget {
  final Widget child;

  const CtTvSmoothTraversal({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      FocusTraversalGroup(policy: ReadingOrderTraversalPolicy(requestFocusCallback: ctTvRequestFocus), child: child);
}
