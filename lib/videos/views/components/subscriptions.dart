import 'package:cloudtube/videos/models/video.dart';
import 'package:flutter/material.dart';
import 'package:cloudtube/main.dart';
import 'package:cloudtube/utils/views/tv/components/tv_horizontal_item_list.dart';

import '../../../cloudtube/sub_channels.dart';
import '../../../cloudtube/tv_channels.dart';
import '../../../utils/models/paginated_list.dart';
import 'video_list.dart';

class Subscriptions extends StatelessWidget {
  final void Function(Video video, int index, bool focus)? onItemFocus;

  const Subscriptions({super.key, this.onItemFocus});

  @override
  Widget build(BuildContext context) {
    var colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surface,
      child: isTv
          ? TvHorizontalVideoList(
              paginatedVideoList: SubscriptionVideoList(),
              onItemFocus: onItemFocus,
            )
          : const _SubscriptionsWithChannels(),
    );
  }
}

/// Телефон и ПК: сверху плитки каналов («Все» + подписки), ниже — общая лента
/// или последние ролики выбранного канала.
class _SubscriptionsWithChannels extends StatefulWidget {
  const _SubscriptionsWithChannels();

  @override
  State<_SubscriptionsWithChannels> createState() => _SubscriptionsWithChannelsState();
}

class _SubscriptionsWithChannelsState extends State<_SubscriptionsWithChannels> {
  final _feed = ValueNotifier<List<Video>>(const []);
  List<(String, String)> _subs = const [];
  String? _selected;
  late PaginatedVideoList _list = CtFeedTap(SubscriptionVideoList(), _feed);

  @override
  void initState() {
    super.initState();
    ctSubscribedChannels().then((v) {
      if (mounted) setState(() => _subs = v);
    });
  }

  @override
  void dispose() {
    _feed.dispose();
    super.dispose();
  }

  void _select(String? id) {
    if (id == _selected) return;
    setState(() {
      _selected = id;
      // «Все» — заново с первой страницы; канал — его последние ролики
      _list = id == null ? CtFeedTap(SubscriptionVideoList(), _feed) : ctChannelLatest(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Video>>(
      valueListenable: _feed,
      builder: (context, feed, _) {
        final channels = ctRankSubChannels(_subs, feed);
        final sel = _selected == null ? null : channels.where((c) => c.id == _selected).firstOrNull;
        return Column(children: [
          if (channels.isNotEmpty) CtSubStrip(channels: channels, selected: _selected, onSelect: _select),
          if (sel != null) CtSubChannelHeader(channel: sel),
          Expanded(
            child: VideoList(
              key: ValueKey(_selected ?? '*all'),
              animateDownload: true,
              paginatedVideoList: _list,
            ),
          ),
        ]);
      },
    );
  }
}
