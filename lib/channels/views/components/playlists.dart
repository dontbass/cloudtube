import 'package:flutter/material.dart';
import 'package:cloudtube/globals.dart';
import 'package:cloudtube/playlists/views/components/playlist_list.dart';
import 'package:cloudtube/utils/models/paginated_list.dart';

import '../../../playlists/models/playlist.dart';

class ChannelPlayListsView extends StatelessWidget {
  final String channelId;
  final bool canDeleteVideos;

  const ChannelPlayListsView({
    super.key,
    required this.channelId,
    required this.canDeleteVideos,
  });

  @override
  Widget build(BuildContext context) {
    return PlaylistList(
      canDeleteVideos: canDeleteVideos,
      paginatedList: ContinuationList<Playlist>((continuation) =>
          service.getChannelPlaylists(channelId, continuation: continuation)),
    );
  }
}
