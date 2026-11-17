import 'package:flutter/material.dart';

import 'theme.dart';

/// Карточка-пункт в стиле CloudTube: круглая иконка акцентного цвета, название, подпись.
/// Используется в «Настройках» и «Профиле» — один стиль на всё приложение.
class CtCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;

  const CtCard(
      {super.key, required this.icon, required this.title, this.subtitle, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accent = danger ? colors.error : ctAccent(colors);
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          // крупная цель для пальца — удобно и на экране в машине
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600, color: danger ? colors.error : null)),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              if (!danger) Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Сетка карточек: на телефоне одна колонка, на планшете и магнитоле — две.
class CtCardGrid extends StatelessWidget {
  final List<Widget> children;

  const CtCardGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 680 ? 2 : 1;
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final i in children) SizedBox(width: w, child: i)]);
    });
  }
}

/// Заголовок группы карточек.
class CtCardSection extends StatelessWidget {
  final String title;

  const CtCardSection(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700, color: ctAccent(colors), letterSpacing: .3)),
    );
  }
}
