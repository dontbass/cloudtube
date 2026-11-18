import 'package:cached_network_image/cached_network_image.dart';
import 'package:clipious/videos/models/video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clipious/utils/states/item_list.dart';
import 'package:clipious/utils/views/components/placeholders.dart';
import 'package:clipious/videos/views/tv/components/video_item.dart';

import '../../../../utils.dart';
import '../../../../cloudtube/tv_mouse.dart';
import '../../../models/paginated_list.dart';

class TvHorizontalItemList<T> extends StatelessWidget {
  final PaginatedList<T> paginatedList;
  final Widget Function() getPlaceholder;
  final String? tags;
  final Widget Function(BuildContext context, int index, T item) buildItem;

  const TvHorizontalItemList(
      {super.key,
      this.tags,
      required this.paginatedList,
      required this.buildItem,
      required this.getPlaceholder});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          ItemListCubit<T>(ItemListState<T>(itemList: paginatedList)),
      child: BlocBuilder<ItemListCubit<T>, ItemListState<T>>(
        builder: (context, state) {
          var cubit = context.read<ItemListCubit<T>>();
          // filter items if possible
          List<T> items = state.items;
          if (items.isNotEmpty && items[0] is Video) {
            items = filteredVideos(state.items.cast()).cast();
          }

          return Stack(
            children: [
              if (state.loading)
                const LinearProgressIndicator(
                  minHeight: 3,
                ),
              !state.loading && items.isEmpty
                  ? const SizedBox.shrink()
                  // CloudTube: как в SmartTube — ~4 крупные карточки на всю ширину (раньше ~3 крупных), высота по ширине карточки
                  : LayoutBuilder(builder: (context, c) {
                      const perRow = 4.4, gap = 14.0;
                      final w = (c.maxWidth - gap * 4) / perRow;
                      // системный масштаб шрифта ТВ учитываем, иначе низ карточки и рамка фокуса обрезаются
                      final textH = MediaQuery.textScalerOf(context).scale(ctTvCardTextH);
                      return SizedBox(
                      height: w * 9 / 16 + textH + 22,
                      child: CtRowArrows(
                        controller: cubit.scrollController,
                        child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        // одну-две карточки за краем готовим заранее (больше — на старте приставка
                        // грузит десятки лишних картинок и ряды появляются медленнее)
                        cacheExtent: w * 1.5,
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        controller: cubit.scrollController,
                        itemCount: items.length + (state.loading ? 10 : 0),
                        itemBuilder: (context, index) {
                          final Widget child;
                          if (index >= items.length) {
                            child = getPlaceholder();
                          } else {
                            // предзагрузка по направлению движения: при фокусе на плитке —
                            // картинки следующих плиток и следующая страница заранее
                            child = Focus(
                              canRequestFocus: false,
                              skipTraversal: true,
                              onFocusChange: (f) {
                                if (f) _preload(context, cubit, items, index);
                              },
                              child: RepaintBoundary(child: buildItem(context, index, items[index])),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.only(right: gap),
                            child: SizedBox(width: w, child: child),
                          );
                        },
                      )),
                    );
                    }),
            ],
          );
        },
      ),
    );
  }
}

/// Сколько плиток вперёд готовим, и за сколько до конца просим следующую страницу.
const _ctPreloadAhead = 4, _ctLoadMoreBefore = 6;

void _preload<T>(BuildContext context, ItemListCubit<T> cubit, List<T> items, int index) {
  if (index >= items.length - _ctLoadMoreBefore) cubit.getMoreItems();
  for (var i = index + 1; i <= index + _ctPreloadAhead && i < items.length; i++) {
    final it = items[i];
    if (it is! Video) continue;
    final url = it.thumbnails.isEmpty ? null : it.thumbnails.first;
    // относительные адреса (свой сервер) скачиваем при показе — им нужны заголовки сервера
    if (url == null || !url.startsWith('http')) continue;
    // тот же ключ и размер, что у плитки (memCacheWidth 480) — картинка возьмётся из памяти
    precacheImage(ResizeImage(CachedNetworkImageProvider(url, cacheKey: url), width: 480), context,
        onError: (_, __) {});
  }
}

class TvHorizontalVideoList extends StatelessWidget {
  final PaginatedList<Video> paginatedVideoList;
  final Function(BuildContext context, Video video)? onSelect;
  final String? tags;
  final int autoFocusedIndex;
  final void Function(Video video, int index, bool focus)? onItemFocus;

  const TvHorizontalVideoList(
      {super.key,
      this.tags,
      required this.paginatedVideoList,
      this.onSelect,
      this.autoFocusedIndex = 0,
      this.onItemFocus});

  @override
  Widget build(BuildContext context) {
    return TvHorizontalItemList<Video>(
      getPlaceholder: () => const TvVideoItemPlaceHolder(),
      paginatedList: paginatedVideoList,
      buildItem: (context, index, e) => TvVideoItem(
        key: ValueKey('video-item-${e.videoId}'),
        video: e,
        compact: true,
        autoFocus: index == autoFocusedIndex,
        onSelect: onSelect,
        onFocusChange: onItemFocus != null
            ? (focus) => onItemFocus!(e, index, focus)
            : null,
      ),
    );
  }
}
