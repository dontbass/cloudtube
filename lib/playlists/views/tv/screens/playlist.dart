import 'package:auto_route/auto_route.dart';
import 'package:cloudtube/playlists/states/playlist.dart';
import 'package:cloudtube/router.dart';
import 'package:cloudtube/utils/views/components/placeholders.dart';
import 'package:cloudtube/utils/views/tv/components/tv_overscan.dart';
import 'package:cloudtube/videos/models/video.dart';
import 'package:cloudtube/videos/views/tv/components/video_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloudtube/l10n/generated/app_localizations.dart';

import '../../../../cloudtube/tv_channels.dart';
import '../../../../cloudtube/tv_nav.dart';
import '../../../../cloudtube/ui_state.dart';
import '../../../../videos/views/components/video_thumbnail.dart';
import '../../../models/playlist.dart';

/// Плейлист на ТВ: слева обложка, название и кнопки «Смотреть» / «Перемешать»,
/// справа сетка роликов (выбор ролика — плейлист с этого места).
/// Без карусели и размытия — легко для слабых приставок.
@RoutePage()
class TvPlaylistScreen extends StatelessWidget {
  final Playlist playlist;
  final bool canDeleteVideos;

  const TvPlaylistScreen({super.key, required this.playlist, required this.canDeleteVideos});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PlaylistCubit(playlist, userPlaylist: canDeleteVideos),
      child: Scaffold(
        body: CtTvLeftEdge(
          child: TvOverscan(
            child: BlocBuilder<PlaylistCubit, PlaylistState>(builder: (context, s) {
              final videos = s.visible;
              if (videos.isEmpty && !s.loading) {
                return s.error != null
                    ? CtErrorView(
                        message: 'Не удалось загрузить плейлист',
                        autofocus: true,
                        onRetry: context.read<PlaylistCubit>().load)
                    : const CtEmptyView(icon: Icons.playlist_remove_rounded, text: 'В плейлисте нет видео');
              }
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 400, child: _TvPlaylistSide(state: s)),
                const SizedBox(width: 28),
                Expanded(child: _TvPlaylistGrid(state: s)),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

void _tvPlay(BuildContext context, {Video? start, bool shuffle = false}) {
  final q = context.read<PlaylistCubit>().queue(start: start, shuffle: shuffle);
  if (q.isNotEmpty) AutoRouter.of(context).push(TvPlayerRoute(videos: q));
}

class _TvPlaylistSide extends StatelessWidget {
  final PlaylistState state;

  const _TvPlaylistSide({required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final locals = AppLocalizations.of(context)!;
    final pl = state.playlist;
    final first = state.visible.where((v) => !v.filtered).firstOrNull;
    final count = pl.videoCount > 0 ? pl.videoCount : state.visible.length;
    final ready = state.visible.isNotEmpty;

    return ListView(padding: const EdgeInsets.only(top: 8), children: [
      AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: first != null
              ? VideoThumbnailView(videoId: first.videoId, thumbnails: first.thumbnails, decoration: const BoxDecoration())
              : Container(color: colors.secondaryContainer),
        ),
      ),
      if (state.loading)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: LinearProgressIndicator(
              value: state.progress > 0 && state.progress < 1 ? state.progress : null,
              borderRadius: BorderRadius.circular(4)),
        ),
      const SizedBox(height: 16),
      Text(pl.title,
          maxLines: 3, overflow: TextOverflow.ellipsis, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text([if (pl.author.isNotEmpty) pl.author, locals.nVideos(count)].join('  ·  '),
          style: text.titleMedium?.copyWith(color: colors.onSurfaceVariant)),
      const SizedBox(height: 22),
      if (ready) ...[
        CtTvChip(
            autofocus: true,
            icon: const Icon(Icons.play_arrow_rounded, size: 28),
            label: 'Смотреть все',
            onPressed: (ctx) => _tvPlay(ctx)),
        const SizedBox(height: 12),
        CtTvChip(
            icon: const Icon(Icons.shuffle_rounded, size: 26),
            label: 'Перемешать',
            onPressed: (ctx) => _tvPlay(ctx, shuffle: true)),
      ],
    ]);
  }
}

class _TvPlaylistGrid extends StatelessWidget {
  final PlaylistState state;

  const _TvPlaylistGrid({required this.state});

  @override
  Widget build(BuildContext context) {
    final videos = state.visible;
    return LayoutBuilder(builder: (context, c) {
      const cols = 4, gap = 14.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      final textH = MediaQuery.textScalerOf(context).scale(ctTvCardTextH) + 6;
      final extra = state.loading ? 8 : 0;
      return CtTvSmoothTraversal(
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 24),
          clipBehavior: Clip.none,
          cacheExtent: w * 1.5,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            mainAxisExtent: w * 9 / 16 + textH,
          ),
          itemCount: videos.length + extra,
          itemBuilder: (context, i) {
            if (i >= videos.length) return const TvVideoItemPlaceHolder();
            final v = videos[i];
            return TvVideoItem(
              key: ValueKey(v.videoId),
              video: v,
              autoFocus: false,
              compact: true,
              onSelect: (ctx, video) => _tvPlay(ctx, start: video),
            );
          },
        ),
      );
    });
  }
}
