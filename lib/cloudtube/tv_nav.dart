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
    if (sc != null && sc.axisDirection == AxisDirection.right && sc.position.pixels > 1) return false;
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
