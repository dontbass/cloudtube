import 'package:auto_route/annotations.dart';
import 'package:clipious/videos/models/video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clipious/utils/models/paginated_list.dart';
import 'package:clipious/utils/views/components/placeholders.dart';
import 'package:clipious/utils/views/tv/components/tv_overscan.dart';
import 'package:clipious/videos/views/tv/components/video_item.dart';

import '../../../../cloudtube/tv_nav.dart';
import '../../../../utils/states/item_list.dart';

@RoutePage()
class TvGridScreen extends StatelessWidget {
  final PaginatedList<Video> paginatedVideoList;
  final String? tags;
  final String title;

  const TvGridScreen(
      {super.key,
      required this.paginatedVideoList,
      this.tags,
      required this.title});

  @override
  Widget build(BuildContext context) {
    var textTheme = Theme.of(context).textTheme;
    return BlocProvider(
      create: (BuildContext context) =>
          ItemListCubit(ItemListState(itemList: paginatedVideoList)),
      child: Scaffold(
        body: CtTvLeftEdge(child: TvOverscan(
          child: BlocConsumer<ItemListCubit<Video>, ItemListState<Video>>(
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
            return Column(
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: textTheme.titleLarge,
                    ),
                    state.loading
                        ? const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                )),
                          )
                        : const SizedBox.shrink()
                  ],
                ),
                // плотная сетка: 6 роликов в ряд (раньше 3), меньше промежутки
                Expanded(child: LayoutBuilder(builder: (context, c) {
                  const cols = 5, gap = 14.0;
                  final w = (c.maxWidth - gap * (cols - 1)) / cols;
                  final textH = MediaQuery.textScalerOf(context).scale(ctTvCardTextH) + 6;
                  final items = [
                    ...state.items.where((element) => !element.filterHide).map((e) => TvVideoItem(
                        key: ValueKey(e.videoId), video: e, autoFocus: false, compact: true)),
                    if (state.loading) ...repeatWidget(() => const TvVideoItemPlaceHolder(), count: 10)
                  ];
                  return GridView.builder(
                    controller: cubit.scrollController,
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
                    clipBehavior: Clip.none,
                    cacheExtent: w * 3,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: gap,
                      mainAxisSpacing: gap,
                      mainAxisExtent: w * 9 / 16 + textH,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) => items[i],
                  );
                })),
              ],
            );
          }),
        )),
      ),
    );
  }
}
