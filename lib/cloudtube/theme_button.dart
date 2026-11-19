import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../settings/states/settings.dart';
import 'theme.dart';
import 'prefs.dart';

/// Кнопка в шапке: одно нажатие — следующая тема по кругу
/// Светлая → Пергамент → Стекло светлое → Сумерки → Тёмная → Стекло тёмное → Светлая.
class CtThemeButton extends StatelessWidget {
  const CtThemeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<CtVariant>(
      valueListenable: ctThemeVariant,
      builder: (context, variant, _) {
        final cur = CtTheme.of(dark, variant);
        final next = cur.next;
        return IconButton(
          tooltip: 'Тема: ${cur.label} → ${next.label}',
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (c, a) => RotationTransition(turns: a, child: FadeTransition(opacity: a, child: c)),
            child: Icon(cur.icon, key: ValueKey(cur)),
          ),
          onPressed: () async {
            await CtPrefs.setVariant(next.variant);
            if (!context.mounted) return;
            await context
                .read<SettingsCubit>()
                .setThemeMode(next.isDark ? ThemeMode.dark : ThemeMode.light);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                  content: Text('Тема: ${next.label}'),
                  duration: const Duration(milliseconds: 900)));
          },
        );
      },
    );
  }
}
