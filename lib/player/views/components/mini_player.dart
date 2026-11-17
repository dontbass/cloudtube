import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clipious/player/states/player.dart';

import '../../../settings/states/settings.dart';

/// Мини-плеер как в YouTube: название и канал в две строки, «пауза» и «следующее»,
/// снизу тонкая полоса прогресса. Видео слева и крестик справа рисует сам плеер.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final isMini = context.select((PlayerCubit c) => c.state.isMini);
    if (!isMini) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final player = context.read<PlayerCubit>();

    final title = context.select((PlayerCubit c) =>
        c.state.currentlyPlaying?.title ?? c.state.offlineCurrentlyPlaying?.title ?? '');
    final author = context.select((PlayerCubit c) =>
        c.state.currentlyPlaying?.author ?? c.state.offlineCurrentlyPlaying?.author ?? '');
    final live = context.select((PlayerCubit c) => c.state.currentlyPlaying?.liveNow ?? false);
    final playing = context.select((PlayerCubit c) => c.state.isPlaying);
    final hasQueue = context.select((PlayerCubit c) => c.state.hasQueue);
    final position = context.select((PlayerCubit c) => c.state.position);
    final duration = context.select((PlayerCubit c) => c.duration);
    final noRepeat = context.select((SettingsCubit c) => c.state.playerRepeatMode == PlayerRepeat.noRepeat);

    final progress = duration.inMilliseconds > 0 ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    final ended = !playing && noRepeat && progress > 0.99;

    return SizedBox(
      height: targetHeight,
      child: Column(children: [
        Expanded(
          child: Row(children: [
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  if (author.isNotEmpty)
                    Text(author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                ],
              ),
            ),
            IconButton(
              tooltip: ended ? 'Сначала' : (playing ? 'Пауза' : 'Смотреть'),
              onPressed: ended
                  ? () {
                      player.seek(Duration.zero);
                      player.play();
                    }
                  : player.togglePlay,
              icon: Icon(ended ? Icons.replay_rounded : (playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  size: 30),
            ),
            if (hasQueue)
              IconButton(
                  tooltip: 'Следующее', onPressed: player.playNext, icon: const Icon(Icons.skip_next_rounded, size: 28)),
          ]),
        ),
        if (!live)
          LinearProgressIndicator(
            value: progress,
            minHeight: 2,
            backgroundColor: colors.onSurface.withValues(alpha: 0.12),
          ),
      ]),
    );
  }
}
