import 'package:auto_route/annotations.dart';
import 'package:clipious/cloudtube/comments.dart';
import 'package:flutter/material.dart';

import '../../models/video.dart';

/// Вкладка комментариев на странице ролика — комментарии CloudTube.
@RoutePage()
class CommentsTab extends StatelessWidget {
  final Video? video;
  const CommentsTab({super.key, this.video});

  @override
  Widget build(BuildContext context) {
    return video == null
        ? const SizedBox.shrink()
        : CtCommentsPanel(key: ValueKey('comms-${video!.videoId}'), videoId: video!.videoId);
  }
}
