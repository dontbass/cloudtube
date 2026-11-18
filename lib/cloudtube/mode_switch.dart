import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../app/states/app.dart';
import 'connect.dart';
import 'connect_screen.dart';
import 'direct.dart';
import 'theme.dart';

/// Переключить режим: напрямую ↔ свой сервер (тот, что был, со входом и паролем сайта).
/// Своего сервера ещё нет — открывает экран подключения.
Future<void> ctToggleMode(BuildContext context, {required bool toDirect}) async {
  final app = context.read<AppCubit>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (toDirect) {
    await ctConnectDirect(app);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(const SnackBar(content: Text('Режим: YouTube напрямую')));
    return;
  }
  final s = await ctConnectLastServer(app);
  if (s == null) {
    if (context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CtConnectScreen()));
    }
    return;
  }
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(content: Text('Режим: свой сервер (${s.url.replaceFirst(RegExp('^https?://'), '')})')));
}

/// Переключатель «YouTube напрямую | Свой сервер» — тумблер-«пилюля»: подсвеченная половина
/// плавно переезжает к выбранному режиму. Нажатие в любом месте — переключить.
class CtModeSwitch extends StatelessWidget {
  const CtModeSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final server = context.select((AppCubit a) => a.state.server);
    final direct = ctIsDirectUrl(server?.url);
    final colors = Theme.of(context).colorScheme;
    final accent = ctAccent(colors);
    const dur = Duration(milliseconds: 260);
    const curve = Curves.easeOutCubic;

    Widget side(bool isDirect, IconData icon, String label) {
      final on = isDirect == direct;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
            AnimatedSwitcher(
              duration: dur,
              child: Icon(icon,
                  key: ValueKey(on), size: 20, color: on ? Colors.white : colors.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: AnimatedDefaultTextStyle(
                duration: dur,
                curve: curve,
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    color: on ? Colors.white : colors.onSurfaceVariant),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // без лишнего отступа над строкой — текст по центру по высоте
                    textHeightBehavior: const TextHeightBehavior(
                        applyHeightToFirstAscent: false, applyHeightToLastDescent: false)),
              ),
            ),
          ]),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        // нажали на левую половину — «напрямую», на правую — «свой сервер»
        final box = context.findRenderObject() as RenderBox?;
        final toDirect = box == null ? !direct : d.localPosition.dx < box.size.width / 2;
        if (toDirect != direct) ctToggleMode(context, toDirect: toDirect);
      },
      child: Container(
        height: 50,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
        ),
        // StackFit.expand: и бегунок, и надписи — на всю высоту, надписи ровно по центру
        child: Stack(fit: StackFit.expand, children: [
          // подсвеченная половина-«бегунок»
          AnimatedAlign(
            duration: dur,
            curve: curve,
            alignment: direct ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: AnimatedContainer(
                duration: dur,
                curve: curve,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: direct
                        ? [accent, Color.lerp(accent, Colors.black, 0.18)!]
                        : [Color.lerp(accent, colors.primary, 0.55)!, Color.lerp(accent, colors.primary, 0.85)!],
                  ),
                  borderRadius: BorderRadius.circular(21),
                  boxShadow: [
                    BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
              ),
            ),
          ),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            side(true, Icons.smart_display_rounded, 'YouTube напрямую'),
            side(false, Icons.dns_rounded, 'Свой сервер'),
          ]),
        ]),
      ),
    );
  }
}
