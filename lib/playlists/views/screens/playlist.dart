import 'package:auto_route/auto_route.dart';
import 'package:cloudtube/videos/models/video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloudtube/l10n/generated/app_localizations.dart';
import 'package:cloudtube/notifications/views/components/bell_icon.dart';
import 'package:cloudtube/player/states/player.dart';
import 'package:cloudtube/settings/models/errors/invidious_service_error.dart';
import 'package:cloudtube/utils.dart';
import 'package:cloudtube/videos/views/components/compact_video.dart';

import '../../../cloudtube/theme.dart';
import '../../../globals.dart';
import '../../../cloudtube/ui_state.dart';
import '../../../utils/views/components/placeholders.dart';
import '../../../videos/views/components/add_to_queue_button.dart';
import '../../../videos/views/components/video_thumbnail.dart';
import '../../models/playlist.dart';
import '../../states/playlist.dart';

/// Страница плейлиста (телефон/планшет): обложка, «Смотреть все», «Перемешать»,
/// список роликов. Нажатие на ролик — плейлист играет с него.
@RoutePage()
class PlaylistViewScreen extends StatelessWidget {
  final Playlist playlist;
  final bool canDeleteVideos;

  const PlaylistViewScreen({super.key, required this.playlist, required this.canDeleteVideos});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PlaylistCubit(playlist, userPlaylist: canDeleteVideos),
      child: BlocBuilder<PlaylistCubit, PlaylistState>(builder: (context, s) {
        return Scaffold(
          appBar: AppBar(
            title: Text(s.playlist.title),
            actions: [
              if (canDeleteVideos)
                IconButton(
                    tooltip: 'Удалить плейлист',
                    onPressed: () => _deletePlaylist(context),
                    icon: const Icon(Icons.delete_outline_rounded))
              else
                BellIcon(itemId: playlist.playlistId, type: BellIconType.playlist),
            ],
          ),
          body: SafeArea(bottom: false, child: _PlaylistBody(state: s, canDelete: canDeleteVideos)),
        );
      }),
    );
  }

  void _deletePlaylist(BuildContext context) {
    final cubit = context.read<PlaylistCubit>();
    final locals = AppLocalizations.of(context)!;
    okCancelDialog(context, locals.deletePlayListQ, locals.irreversibleAction, () async {
      await cubit.deletePlaylist();
      if (context.mounted) Navigator.of(context).pop();
    });
  }
}

class _PlaylistBody extends StatelessWidget {
  final PlaylistState state;
  final bool canDelete;

  const _PlaylistBody({required this.state, required this.canDelete});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PlaylistCubit>();
    final videos = state.visible;
    if (videos.isEmpty && !state.loading) {
      return state.error != null
          ? CtErrorView(message: 'Не удалось загрузить плейлист', onRetry: cubit.load)
          : const CtEmptyView(icon: Icons.playlist_remove_rounded, text: 'В плейлисте нет видео');
    }
    final header = _PlaylistHeader(state: state);
    final list = SliverList.builder(
      itemCount: videos.length + (state.loading ? 4 : 0),
      itemBuilder: (context, i) {
        if (i >= videos.length) return const CompactVideoPlaceHolder();
        final v = videos[i];
        final tile = CompactVideo(key: ValueKey(v.videoId), video: v, onTap: () => _play(context, start: v));
        if (!canDelete) return tile;
        return Dismissible(
          key: ValueKey('del-${v.videoId}-${v.indexId}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: Theme.of(context).colorScheme.error,
            child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
          ),
          confirmDismiss: (_) => _remove(context, v),
          child: tile,
        );
      },
    );

    return LayoutBuilder(builder: (context, c) {
      // планшет/магнитола: шапка слева, список справа
      if (c.maxWidth >= 900) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 380, child: SingleChildScrollView(child: header)),
          Expanded(child: CustomScrollView(slivers: [SliverPadding(padding: const EdgeInsets.only(right: 12), sliver: list)])),
        ]);
      }
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tabletMaxVideoWidth),
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(child: header),
            SliverPadding(padding: const EdgeInsets.symmetric(horizontal: innerHorizontalPadding), sliver: list),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ]),
        ),
      );
    });
  }

  /// Удаление свайпом: true — строку убираем, false — возвращаем на место.
  Future<bool> _remove(BuildContext context, Video v) async {
    try {
      await context.read<PlaylistCubit>().removeVideo(v);
      return true;
    } catch (err) {
      if (context.mounted) {
        final locals = AppLocalizations.of(context)!;
        showAlertDialog(
            context, locals.error, [Text(err is InvidiousServiceError ? err.message : 'Не удалось убрать видео')]);
      }
      return false;
    }
  }
}

void _play(BuildContext context, {Video? start, bool shuffle = false, bool audio = false}) {
  final q = context.read<PlaylistCubit>().queue(start: start, shuffle: shuffle);
  if (q.isEmpty) return;
  context.read<PlayerCubit>().playVideo(q, audio: audio);
}

/// Обложка (первый ролик), название, автор, число видео и кнопки.
class _PlaylistHeader extends StatelessWidget {
  final PlaylistState state;

  const _PlaylistHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final locals = AppLocalizations.of(context)!;
    final pl = state.playlist;
    final videos = state.visible;
    final first = videos.where((v) => !v.filtered).firstOrNull;
    final count = pl.videoCount > 0 ? pl.videoCount : videos.length;
    final ready = videos.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(fit: StackFit.expand, children: [
              first != null
                  ? VideoThumbnailView(
                      videoId: first.videoId, thumbnails: first.thumbnails, decoration: const BoxDecoration())
                  : Container(color: colors.secondaryContainer),
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.playlist_play_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 4),
                    Text(locals.nVideos(count), style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        if (state.loading)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(
                value: state.progress > 0 && state.progress < 1 ? state.progress : null,
                borderRadius: BorderRadius.circular(4)),
          ),
        const SizedBox(height: 12),
        Text(pl.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        if (pl.author.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(pl.author, style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
          ),
        if ((pl.description ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(pl.description!.trim(),
                maxLines: 3, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
                style: FilledButton.styleFrom(shape: const StadiumBorder(), minimumSize: const Size(0, 44)),
                onPressed: ready ? () => _play(context) : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Смотреть все')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(shape: const StadiumBorder(), minimumSize: const Size(0, 44)),
                onPressed: ready ? () => _play(context, shuffle: true) : null,
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('Перемешать')),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          TextButton.icon(
              onPressed: ready ? () => _play(context, audio: true) : null,
              icon: Icon(Icons.headphones_rounded, color: ready ? ctAccent(colors) : null),
              label: const Text('Только звук')),
          const Spacer(),
          if (ready) AddToQueueButton(videos: videos),
        ]),
      ]),
    );
  }
}
