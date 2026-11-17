import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../settings/states/settings.dart';
import '../../states/player.dart';

/// Полоска под видео в развёрнутом плеере: «Видео / Звук», повтор и перемешивание очереди.
/// (Имя осталось от Clipious — в мини-плеере этих кнопок больше нет.)
class MiniPlayerControls extends StatelessWidget {
  final String videoId;

  const MiniPlayerControls({super.key, required this.videoId});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final player = context.read<PlayerCubit>();
    final settings = context.read<SettingsCubit>();
    final repeat = context.select((SettingsCubit s) => s.state.playerRepeatMode);
    final shuffle = context.select((SettingsCubit s) => s.state.playerShuffleMode);
    final isAudio = context.select((PlayerCubit p) => p.state.isAudio);
    final hasQueue = context.select((PlayerCubit p) => p.state.hasQueue);
    final online = context.select((PlayerCubit p) =>
        p.state.currentlyPlaying != null && !(p.state.currentlyPlaying?.liveNow ?? false));

    final (repeatIcon, repeatTip) = switch (repeat) {
      PlayerRepeat.repeatOne => (Icons.repeat_one_rounded, 'Повтор: это видео'),
      PlayerRepeat.repeatAll => (Icons.repeat_rounded, 'Повтор: вся очередь'),
      _ => (Icons.repeat_rounded, 'Без повтора'),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
      child: Row(children: [
        if (online)
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.ondemand_video_rounded, size: 18), label: Text('Видео')),
              ButtonSegment(value: true, icon: Icon(Icons.headphones_rounded, size: 18), label: Text('Звук')),
            ],
            selected: {isAudio},
            onSelectionChanged: (v) => player.switchAudio(v.first),
          ),
        const Spacer(),
        IconButton(
          tooltip: repeatTip,
          onPressed: settings.setNextRepeatMode,
          color: repeat == PlayerRepeat.noRepeat ? null : colors.primary,
          icon: Icon(repeatIcon),
        ),
        if (hasQueue)
          IconButton(
            tooltip: shuffle ? 'Перемешивание включено' : 'Перемешать очередь',
            onPressed: () {
              settings.toggleShuffle();
              player.generatePlayQueue();
            },
            color: shuffle ? colors.primary : null,
            icon: const Icon(Icons.shuffle_rounded),
          ),
      ]),
    );
  }
}
