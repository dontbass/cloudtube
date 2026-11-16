import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clipious/player/states/interfaces/media_player.dart';
import 'package:clipious/player/states/player.dart';
import 'package:clipious/player/views/components/video_queue.dart';

import '../../../downloads/models/downloaded_video.dart';
import '../../../settings/states/settings.dart';
import '../../../videos/models/video.dart';
import 'mini_player_controls.dart';
import '../../../cloudtube/watch.dart';

class ExpandedPlayer extends StatelessWidget {
  const ExpandedPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    var player = context.read<PlayerCubit>();
    var controller = player.state;

    // пока грузятся данные — сразу показываем то, что известно из ленты (название, канал)
    Video? video = controller.currentlyPlaying ??
        (controller.offlineCurrentlyPlaying == null && controller.videos.isNotEmpty ? controller.videos.first : null);
    DownloadedVideo? offlineVid = controller.offlineCurrentlyPlaying;
    context.watch<SettingsCubit>();

    bool isFullScreen =
        controller.fullScreenState == FullScreenState.fullScreen;

    return !isFullScreen &&
            !controller.isMini &&
            (video != null || offlineVid != null)
        ? Column(children: [
            MiniPlayerControls(
              videoId: video?.videoId ?? offlineVid?.videoId ?? '',
            ),
            // CloudTube: одна лента как в YouTube вместо вкладок
            Expanded(
              child: video != null
                  ? CtWatchBody(key: ValueKey('ct-watch-${video.videoId}'), video: video)
                  : const VideoQueue(),
            ),
          ])
        : const SizedBox.shrink();
  }
}
