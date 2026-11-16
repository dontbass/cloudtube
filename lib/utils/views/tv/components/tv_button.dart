import 'package:clipious/cloudtube/theme.dart';
import 'package:flutter/material.dart';
import 'package:clipious/utils.dart';

class TvButton extends StatelessWidget {
  final Widget? child;
  final Function(BuildContext context)? onPressed;
  final Color? focusedColor;
  final Color? unfocusedColor;
  final double? borderRadius;
  final bool? autofocus;
  final Function(bool focus)? onFocusChanged;
  final Widget Function(BuildContext context, bool hasFocus)? builder;

  const TvButton(
      {super.key,
      this.child,
      this.onPressed,
      this.focusedColor,
      this.unfocusedColor,
      this.borderRadius,
      this.autofocus,
      this.onFocusChanged,
      this.builder});

  @override
  Widget build(BuildContext context) {
    Brightness brightness = Theme.of(context).brightness;
    ColorScheme colors = Theme.of(context).colorScheme;
    return Focus(
      autofocus: autofocus ?? false,
      onFocusChange: onFocusChanged,
      onKeyEvent: (node, event) => onPressed != null
          ? onTvSelect(event, context, onPressed!)
          : KeyEventResult.ignored,
      child: Builder(
        builder: (ctx) {
          bool hasFocus = Focus.of(ctx).hasFocus;

          final light = brightness != Brightness.dark;
          // светлая и мягкая темы: раньше фон в фокусе был тёмным (primary), а текст тоже тёмным —
          // пункт почти не читался. Теперь светлая подсветка акцентом и текст цветом акцента.
          final fg = hasFocus && focusedColor == null
              ? (light ? ctAccent(colors) : colors.onPrimaryContainer)
              : null;
          Widget content = builder != null ? builder!(ctx, hasFocus) : (child ?? const SizedBox.shrink());
          if (fg != null) {
            content = IconTheme.merge(
                data: IconThemeData(color: fg),
                child: DefaultTextStyle.merge(style: TextStyle(color: fg), child: content));
          }
          return Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              // короткая анимация — подсветка успевает за быстрым переключением
              duration: const Duration(milliseconds: 110),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: hasFocus
                    ? focusedColor ??
                        (light ? ctAccent(colors).withValues(alpha: 0.14) : colors.primaryContainer)
                    : unfocusedColor ?? colors.secondaryContainer,
                border: ctFocusBorder(colors, hasFocus),
                borderRadius: BorderRadius.circular(borderRadius ?? 2000),
              ),
              child: content,
            ),
          );
        },
      ),
    );
  }
}
