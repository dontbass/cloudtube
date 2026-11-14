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

PaginatedList<Video> ctSectionList(String id) {
  // «Главная»: на сервере с дополнениями /api/v1/popular — персональная лента;
  // на обычном Invidious «популярное» часто выключено — тогда тренды.
  if (id.isEmpty) {
    return SingleEndpointList<Video>(() async {
      try {
        final l = await service.getPopular();
        if (l.isNotEmpty) return l;
      } catch (_) {}
      return service.getTrending();
    });
  }
  return PageBasedPaginatedList<Video>(
      maxResults: 24,
      getItemsFunc: (page, maxResults) =>
          CtServer.hasAddons().then((addons) => addons
              ? service.search('ct:$id', page: page).then((r) => r.videos)
              : CtServer.fallbackSection(id, page)));
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
