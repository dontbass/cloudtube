import 'dart:async';
import 'direct.dart';
import 'package:clipious/globals.dart';
import 'package:clipious/utils/models/paginated_list.dart';
import 'package:clipious/videos/models/video.dart';
import 'package:clipious/videos/views/components/video_list.dart';
import 'package:flutter/material.dart';

import 'server_caps.dart';
import 'theme.dart';

/// Вкладки как в приложении YouTube: Главная · Shorts · Музыка · Сейчас в эфире …
/// «Главная» — наша лента /api/v1/popular, остальное — разделы сервиса ленты (поиск q=ct:<раздел>).
class CtSection {
  final String id;
  final String label;

  const CtSection(this.id, this.label);
}

const ctSections = <CtSection>[
  CtSection('', 'Главная'),
  CtSection('music', 'Музыка'),
  CtSection('live', 'Сейчас в эфире'),
  CtSection('news', 'Новости'),
  CtSection('sport', 'Спорт'),
  CtSection('gaming', 'Видеоигры'),
  CtSection('podcasts', 'Подкасты'),
  CtSection('movies', 'Фильмы'),
];

/// [fill] — догружать первую страницу до ~24 роликов (для сетки; рядам ТВ не нужно — быстрее старт).
/// [delay] — отложить первую загрузку (ряды разделов ТВ не мешают главной ленте).
/// Первая страница «Главной» загружена (или не удалась).
final ctHomeReady = Completer<void>();

PaginatedList<Video> ctSectionList(String id, {bool fill = true, Duration delay = Duration.zero}) {
  // «Главная»: на сервере с дополнениями /api/v1/popular — персональная лента;
  // на обычном Invidious «популярное» часто выключено — тогда тренды.
  if (id.isEmpty && ctDirectActive) {
    // без сервера: «Главная» — бесконечная подборка поиском
    return CtPagedList<Video>((page) async {
      try {
        return await service.search('ct:home', page: page).then((r) => r.videos);
      } finally {
        if (page == 1 && !ctHomeReady.isCompleted) ctHomeReady.complete();
      }
    }, fill: fill);
  }
  if (id.isEmpty) {
    return SingleEndpointList<Video>(() async {
      try {
        final l = await service.getPopular();
        if (l.isNotEmpty) return l;
      } catch (_) {
      } finally {
        if (!ctHomeReady.isCompleted) ctHomeReady.complete();
      }
      return service.getTrending();
    });
  }
  return CtPagedList<Video>((page) async {
    if (page == 1 && delay > Duration.zero) {
      // ряды разделов ТВ ждут «Главную» (не больше 4 с) — она появляется первой и быстро,
      // без борьбы за сеть с шестью рядами сразу
      await ctHomeReady.future.timeout(const Duration(seconds: 4), onTimeout: () {});
      await Future.delayed(delay);
    }
    final addons = await CtServer.hasAddons();
    return addons || ctDirectActive
        ? service.search('ct:$id', page: page).then((r) => r.videos)
        : CtServer.fallbackSection(id, page);
  }, fill: fill);
}

class CtHomeFeed extends StatefulWidget {
  final int initialIndex;

  const CtHomeFeed({super.key, this.initialIndex = 0});

  @override
  State<CtHomeFeed> createState() => _CtHomeFeedState();
}

class _CtHomeFeedState extends State<CtHomeFeed> {
  late int index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final section = ctSections[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: ctSections.length,
            itemBuilder: (context, i) {
              final on = i == index;
              return InkWell(
                onTap: () => setState(() => index = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: on ? CtColors.red : Colors.transparent, width: 3),
                    ),
                  ),
                  child: Text(
                    ctSections[i].label,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: on ? colors.onSurface : colors.onSurfaceVariant),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: VideoList<Video>(
            key: ValueKey('ct-section-${section.id}'),
            animateDownload: true,
            paginatedVideoList: ctSectionList(section.id),
          ),
        ),
      ],
    );
  }
}


/// Постраничный список: следующая страница грузится, пока сервер отдаёт хоть что-то
/// (у Clipious список обрывался, если страница короче 24 — у YouTube их по ~20).
class CtPagedList<T> extends PaginatedList<T> {
  final Future<List<T>> Function(int page) fetch;
  int page = 1;
  bool hasMore = true;
  final bool fill;

  CtPagedList(this.fetch, {this.fill = true});

  @override
  bool getHasMore() => hasMore;

  @override
  Future<List<T>> getItems() async {
    final list = await fetch(page);
    hasMore = list.isNotEmpty && page < 30;
    // первая порция должна заполнить экран (иначе прокрутки нет и следующая страница не грузится)
    var extra = 0;
    while (fill && page == 1 + extra && list.length < 24 && hasMore && extra < 3) {
      extra++;
      try {
        final more = await fetch(page + extra);
        if (more.isEmpty) break;
        list.addAll(more);
      } catch (_) {
        break;
      }
    }
    page += extra;
    return list;
  }

  @override
  Future<List<T>> getMoreItems() async {
    page++;
    try {
      return await getItems();
    } catch (e) {
      page--;
      rethrow;
    }
  }

  @override
  bool hasRefresh() => true;

  @override
  Future<List<T>> refresh() async {
    page = 1;
    hasMore = true;
    return getItems();
  }
}
