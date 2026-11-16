import 'package:flutter/material.dart';

/// «Далее: …» за несколько секунд до конца ролика (как в YouTube/SmartTube).
/// (название следующего ролика, секунд до перехода) или null — плашки нет.
final ctUpNext = ValueNotifier<(String, int)?>(null);

/// Ролик, для которого автопереход отменили кнопкой «Назад».
String? ctUpNextCancelledFor;

/// Текущее качество видео (для панели плеера ТВ), например «2160p · vp9».
final ctNowQuality = ValueNotifier<String?>(null);

class CtUpNextCard extends StatelessWidget {
  const CtUpNextCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<(String, int)?>(
      valueListenable: ctUpNext,
      builder: (context, v, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: v == null
            ? const SizedBox.shrink()
            : Container(
                key: const ValueKey('up-next'),
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Далее через ${v.$2} с',
                        style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(v.$1,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text('OK — смотреть сейчас · «Назад» — отменить',
                        style: TextStyle(color: Colors.white60, fontSize: 13)),
                  ],
                ),
              ),
      ),
    );
  }
}
