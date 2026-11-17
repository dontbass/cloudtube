import 'package:auto_route/auto_route.dart';
import 'package:clipious/globals.dart';
import 'package:clipious/player/states/player.dart';
import 'package:clipious/player/views/components/video_queue.dart';
import 'package:clipious/router.dart';
import 'package:clipious/subscription_management/view/components/subscribe_button.dart';
import 'package:clipious/utils/views/components/text_linkified.dart';
import 'package:clipious/videos/models/video.dart';
import 'package:clipious/videos/views/components/add_to_playlist_dialog.dart';
import 'package:clipious/videos/views/components/video_in_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

import 'avatars.dart';
import 'comments.dart';

/// Страница просмотра как в YouTube: под плеером одна лента —
/// название (нажатие раскрывает описание), канал + «Подписаться», кнопки,
/// карточка комментариев (нажатие открывает шторку), дальше рекомендации во всю ширину.
class CtWatchBody extends StatefulWidget {
  final Video video;

  /// false — рекомендации показываются отдельной колонкой (широкий экран ПК)
  final bool showRecs;

  const CtWatchBody({super.key, required this.video, this.showRecs = true});

  @override
  State<CtWatchBody> createState() => _CtWatchBodyState();
}

class _CtWatchBodyState extends State<CtWatchBody> {
  bool _desc = false;
  CtCommentsPage? _comments;

  @override
  void initState() {
    super.initState();
    CtComments.load(widget.video.videoId).then((p) {
      if (mounted) setState(() => _comments = p);
    }).catchError((_) {});
  }

  Video get v => widget.video;

  void _openChannel() {
    final id = v.authorId;
    if (id == null || id.isEmpty) return;
    context.read<PlayerCubit>().showMiniPlayer();
    AutoRouter.of(context).push(ChannelRoute(channelId: id));
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final playlists = await service.getUserPlaylists();
      if (!mounted) return;
      AddToPlaylistDialog.showAddToPlaylistDialog(context, videoId: v.videoId, playlists: playlists,
          onAdd: (pid) async {
        try {
          await service.addVideoToPlaylist(pid, v.videoId);
          messenger.showSnackBar(const SnackBar(content: Text('Сохранено в плейлист')));
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text('Не удалось сохранить: $e')));
        }
      });
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Войдите в аккаунт («Профиль»), чтобы сохранять')));
    }
  }

  void _queue() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (c, sc) => SingleChildScrollView(controller: sc, child: const VideoQueue()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final player = context.read<PlayerCubit>();
    final views = v.viewCount ?? 0;
    final meta = [
      if (views > 0) '${ctShortNumber(views)} просмотров',
      if ((v.publishedText ?? '').isNotEmpty) v.publishedText!,
    ].join('  ');
    final recs = v.recommendedVideos.where((e) => !e.filterHide).toList();
    final first = _comments?.items.isNotEmpty == true ? _comments!.items.first : null;
    final count = _comments?.count ?? _comments?.items.length;

    Widget chip(Widget child, VoidCallback? onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: child),
            ),
          ),
        );

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // название + просмотры, нажатие раскрывает описание
        InkWell(
          onTap: () => setState(() => _desc = !_desc),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.title ?? '',
                  maxLines: _desc ? null : 2,
                  overflow: _desc ? null : TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.3)),
              const SizedBox(height: 6),
              Text.rich(TextSpan(children: [
                TextSpan(text: meta),
                TextSpan(
                    text: _desc ? '  свернуть' : '  ...ещё',
                    style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600)),
              ]), style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
            ]),
          ),
        ),
        // канал и подписка
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(children: [
            CtChannelAvatar(channelId: v.authorId ?? '', author: v.author ?? '', size: 36, onTap: _openChannel),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: _openChannel,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: v.author ?? '',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.onSurface)),
                    if ((v.subCountText ?? '').isNotEmpty)
                      TextSpan(
                          text: '  ${v.subCountText}',
                          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SubscribeButton(channelId: v.authorId ?? '', subCount: ''),
          ]),
        ),
        // кнопки
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              chip(
                  Row(children: [
                    const Icon(Icons.thumb_up_outlined, size: 18),
                    const SizedBox(width: 6),
                    Text((v.likeCount ?? 0) > 0 ? ctShortNumber(v.likeCount!) : ''),
                    const SizedBox(width: 10),
                    Container(width: 1, height: 18, color: colors.outline),
                    const SizedBox(width: 10),
                    const Icon(Icons.thumb_down_outlined, size: 18),
                    if ((v.dislikeCount ?? 0) > 0) ...[
                      const SizedBox(width: 6),
                      Text(ctShortNumber(v.dislikeCount!)),
                    ],
                  ]),
                  null),
              chip(const Row(children: [Icon(Icons.shortcut, size: 18), SizedBox(width: 6), Text('Поделиться')]),
                  () => SharePlus.instance.share(ShareParams(text: 'https://youtu.be/${v.videoId}'))),
              chip(const Row(children: [Icon(Icons.bookmark_border, size: 18), SizedBox(width: 6), Text('Сохранить')]),
                  _save),
              chip(const Row(children: [Icon(Icons.playlist_play, size: 18), SizedBox(width: 6), Text('Очередь')]),
                  _queue),
            ],
          ),
        ),
        // описание (раскрытое)
        if (_desc)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: colors.surfaceContainer, borderRadius: BorderRadius.circular(12)),
            child: TextLinkified(text: v.description ?? '', video: v, player: player),
          ),
        // карточка комментариев
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Material(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => ctShowComments(context, v.videoId),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('Комментарии', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    if ((count ?? 0) > 0)
                      Text(ctShortNumber(count!), style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
                    const Spacer(),
                    Icon(Icons.unfold_more, size: 20, color: colors.onSurfaceVariant),
                  ]),
                  const SizedBox(height: 8),
                  if (_comments == null)
                    Text('Загрузка…', style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant))
                  else if (first == null)
                    Text('Комментариев нет или они отключены',
                        style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant))
                  else
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: colors.secondaryContainer,
                        child: Text(first.author.replaceFirst('@', '').characters.firstOrNull?.toUpperCase() ?? '',
                            style: TextStyle(fontSize: 11, color: colors.onSurface)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(first.text,
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                      ),
                    ]),
                ]),
              ),
            ),
          ),
        ),
        // рекомендации — во всю ширину
        if (widget.showRecs) ...recs.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: VideoListItem(video: e),
            )),
        const SizedBox(height: 24),
      ],
    );
  }
}
