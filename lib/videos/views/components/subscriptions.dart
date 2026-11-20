import 'package:cloudtube/cloudtube/theme.dart';
import 'package:cloudtube/videos/models/video.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:cloudtube/main.dart';
import 'package:cloudtube/utils/views/tv/components/tv_horizontal_item_list.dart';

import '../../../cloudtube/sub_channels.dart';
import '../../../cloudtube/compact.dart';
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
      color: ctBg(colorScheme),
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
  final _order = CtStableOrder();
  List<(String, String)> _subs = const [];
  String? _selected;
  bool _stripHidden = false;
  late PaginatedVideoList _list = CtFeedTap(SubscriptionVideoList(), _feed, onReload: _loadSubs);

  // список каналов обновляется вместе с лентой (первая загрузка, «потянуть вниз», возврат к «Все»)
  void _loadSubs() {
    ctSubscribedChannels().then((v) {
      if (mounted) {
        setState(() {
          _subs = v;
          _order.reset();
        });
      }
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
      _list = id == null ? CtFeedTap(SubscriptionVideoList(), _feed, onReload: _loadSubs) : ctChannelLatest(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Video>>(
      valueListenable: _feed,
      builder: (context, feed, _) {
        final channels = _order.apply(ctRankSubChannels(_subs, feed), hasFeed: feed.isNotEmpty);
        final sel = _selected == null ? null : channels.where((c) => c.id == _selected).firstOrNull;
        final compact = ctIsCompact(context);
        final list = VideoList(
          key: ValueKey(_selected ?? '*all'),
          animateDownload: true,
          paginatedVideoList: _list,
        );
        return Column(children: [
          if (channels.isNotEmpty)
            // компактный вид: при прокрутке вниз ряд каналов уезжает, вверх — возвращается
            ClipRect(
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                heightFactor: compact && _stripHidden ? 0 : 1,
                child: CtSubStrip(channels: channels, selected: _selected, onSelect: _select, compact: compact),
              ),
            ),
          if (sel != null) CtSubChannelHeader(channel: sel),
          Expanded(
            child: compact
                ? NotificationListener<UserScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.axis != Axis.vertical) return false;
                      final hide = n.direction == ScrollDirection.reverse && n.metrics.pixels > 24;
                      final show = n.direction == ScrollDirection.forward || n.metrics.pixels <= 0;
                      if (hide && !_stripHidden) setState(() => _stripHidden = true);
                      if (show && _stripHidden) setState(() => _stripHidden = false);
                      return false;
                    },
                    child: list)
                : list,
          ),
        ]);
      },
    );
  }
}
