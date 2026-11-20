import 'package:auto_route/annotations.dart';
import 'package:cloudtube/videos/models/video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloudtube/utils/models/paginated_list.dart';
import 'package:cloudtube/utils/views/components/placeholders.dart';
import 'package:cloudtube/utils/views/tv/components/tv_overscan.dart';
import 'package:cloudtube/videos/views/tv/components/video_item.dart';

import '../../../../cloudtube/tv_nav.dart';
import '../../../../cloudtube/tv_channels.dart';
import '../../../../cloudtube/sub_channels.dart';
import '../../../../utils/states/item_list.dart';

@RoutePage()
class TvGridScreen extends StatefulWidget {
  final PaginatedList<Video> paginatedVideoList;
  final String? tags;
  final String title;

  /// Экран «Подписки»: сверху плитки каналов, ОК на плитке — ролики канала в сетке.
  final bool showChannels;

  const TvGridScreen(
      {super.key,
      required this.paginatedVideoList,
      this.tags,
      required this.title,
      this.showChannels = false});

  @override
  State<TvGridScreen> createState() => _TvGridScreenState();
}

class _TvGridScreenState extends State<TvGridScreen> {
  final _feed = ValueNotifier<List<Video>>(const []);
  final _order = CtStableOrder();
  List<(String, String)> _subs = const [];
  String? _selected;
  late PaginatedList<Video> _list = widget.showChannels && widget.paginatedVideoList is PaginatedVideoList
      ? CtFeedTap(widget.paginatedVideoList as PaginatedVideoList, _feed, onReload: _loadSubs)
      : widget.paginatedVideoList;

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
      _list = id == null ? CtFeedTap(SubscriptionVideoList(), _feed, onReload: _loadSubs) : ctChannelLatest(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    var textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: CtTvLeftEdge(
          child: TvOverscan(
        child: ValueListenableBuilder<List<Video>>(
            valueListenable: _feed,
            builder: (context, feed, _) {
              final channels = widget.showChannels
                  ? _order.apply(ctRankSubChannels(_subs, feed), hasFeed: feed.isNotEmpty)
                  : const <CtSubChannel>[];
              final sel = _selected == null ? null : channels.where((c) => c.id == _selected).firstOrNull;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(sel == null ? widget.title : '${widget.title} · ${sel.name}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.titleLarge),
                    ),
                    if (sel != null) ...[
                      const SizedBox(width: 16),
                      ctTvOpenChannelChip(sel.id),
                    ],
                  ]),
                  // плитки — вне сетки: при смене канала сетка пересоздаётся, а фокус остаётся на плитке
                  if (channels.isNotEmpty) CtTvSubStrip(channels: channels, selected: _selected, onSelect: _select),
                  Expanded(
                    child: BlocProvider(
                      key: ValueKey(_selected ?? '*all'),
                      create: (BuildContext context) => ItemListCubit(ItemListState(itemList: _list)),
                      child: const _TvGrid(),
                    ),
                  ),
                ],
              );
            }),
      )),
    );
  }
}

class _TvGrid extends StatelessWidget {
  const _TvGrid();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ItemListCubit<Video>, ItemListState<Video>>(
        // сетка на ТВ не прокручивается, пока не заполнена, — догружаем сами
        listenWhen: (a, b) => a.loading && !b.loading,
        listener: (context, state) {
          if (state.error == ItemListErrors.none &&
              state.items.isNotEmpty &&
              state.items.length < 40 &&
              state.itemList.getHasMore()) {
            context.read<ItemListCubit<Video>>().getMoreItems();
          }
        },
        builder: (context, state) {
          var cubit = context.read<ItemListCubit<Video>>();
          // плотная сетка: 5 роликов в ряд, небольшие промежутки
          return LayoutBuilder(builder: (context, c) {
            const cols = 5, gap = 14.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            final textH = MediaQuery.textScalerOf(context).scale(ctTvCardTextH) + 6;
            final items = [
              ...state.items.where((element) => !element.filterHide).map((e) =>
                  TvVideoItem(key: ValueKey(e.videoId), video: e, autoFocus: false, compact: true)),
              if (state.loading) ...repeatWidget(() => const TvVideoItemPlaceHolder(), count: 10)
            ];
            return GridView.builder(
              controller: cubit.scrollController,
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
              clipBehavior: Clip.none,
              cacheExtent: w * 1.5,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: gap,
                mainAxisSpacing: gap,
                mainAxisExtent: w * 9 / 16 + textH,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) => items[i],
            );
          });
        });
  }
}
