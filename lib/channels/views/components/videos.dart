import 'package:cloudtube/cloudtube/theme.dart';
import 'dart:async';

import 'package:cloudtube/videos/models/video.dart';
import 'package:flutter/material.dart';
import 'package:cloudtube/channels/models/channel_videos.dart';
import 'package:cloudtube/globals.dart';
import 'package:cloudtube/videos/views/components/video_list.dart';

import '../../../utils/models/paginated_list.dart';
import '../../models/channel.dart';

class ChannelVideosView extends StatelessWidget {
  final Channel channel;
  final Future<VideosWithContinuation> Function(
      String channelId, String? continuation) getVideos;

  const ChannelVideosView(
      {super.key, required this.channel, required this.getVideos});

  @override
  Widget build(BuildContext context) {
    var colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: innerHorizontalPadding),
      child: Container(
        color: ctBg(colorScheme),
        child: VideoList(
          paginatedVideoList: ContinuationList<Video>(
              (continuation) => getVideos(channel.authorId, continuation)),
          // tags: 'channel-video-list-${(key as ValueKey<String>).value}'
        ),
      ),
    );
  }
}
