import 'package:auto_route/annotations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:clipious/app/views/tv/screens/tv_home.dart';
import 'package:clipious/channels/states/channel.dart';
import 'package:clipious/globals.dart';
import 'package:clipious/subscription_management/view/tv/tv_subscribe_button.dart';
import 'package:clipious/utils/models/image_object.dart';
import 'package:clipious/utils/models/paginated_list.dart';
import 'package:clipious/utils/views/components/placeholders.dart';
import 'package:clipious/utils/views/components/thumbnail.dart';
import 'package:clipious/utils/views/tv/components/tv_expandable_text.dart';
import 'package:clipious/utils/views/tv/components/tv_horizontal_item_list.dart';
import 'package:clipious/utils/views/tv/components/tv_overscan.dart';
import 'package:clipious/videos/models/video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clipious/l10n/generated/app_localizations.dart';

import '../../../../cloudtube/tv_nav.dart';
import '../../../../cloudtube/ui_state.dart';
import '../../../../playlists/models/playlist.dart';
import '../../../../playlists/views/components/playlist_in_list.dart';
import '../../../models/channel.dart';
import '../../../models/channel_videos.dart';
import '../../screens/channel.dart' show ctSubscribers;

/// Страница канала на ТВ: шапка (аватар, название, подписка, описание) и ряды
/// Видео / Моменты / Стримы / Плейлисты. Выбранный ряд встаёт вверх, как на главной.
/// Без размытия на весь экран — оно дорого для слабых ТВ-приставок.
@RoutePage()
class TvChannelScreen extends StatelessWidget {
  final String channelId;

  const TvChannelScreen({super.key, required this.channelId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CtTvLeftEdge(
        child: BlocProvider(
          create: (_) => ChannelCubit(channelId),
          child: BlocBuilder<ChannelCubit, ChannelState>(builder: (context, s) {
            final channel = s.channel;
            if (channel != null) return _TvChannelBody(channel: channel);
            if (s.loading) return const Center(child: CircularProgressIndicator());
            return CtErrorView(
                message: 'Не удалось открыть канал', autofocus: true, onRetry: context.read<ChannelCubit>().load);
          }),
        ),
      ),
    );
  }
}

class _TvChannelBody extends StatefulWidget {
  final Channel channel;

  const _TvChannelBody({required this.channel});

  @override
  State<_TvChannelBody> createState() => _TvChannelBodyState();
}

class _TvChannelBodyState extends State<_TvChannelBody> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toTop(bool focus) {
    if (!focus || !_scroll.hasClients) return;
    ctTvResetRow();
    _scroll.animateTo(0, duration: const Duration(milliseconds: 180), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final locals = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ch = widget.channel;
    final id = ch.authorId;
    final banner = ImageObject.getBestThumbnail(ch.authorBanners)?.url;

    return Stack(children: [
      if (banner != null)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 260,
          child: ShaderMask(
            // баннер плавно растворяется в фон
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.transparent],
            ).createShader(r),
            blendMode: BlendMode.dstIn,
            child: Opacity(
              opacity: 0.45,
              child: CachedNetworkImage(imageUrl: banner, fit: BoxFit.cover, fadeInDuration: Duration.zero),
            ),
          ),
        ),
      TvOverscan(
        child: CtTvSmoothTraversal(
          child: ListView(controller: _scroll, children: [
            const SizedBox(height: 70),
            Row(children: [
              Thumbnail(
                thumbnails: ImageObject.getThumbnailUrlsByPreferredOrder(ch.authorThumbnails),
                width: 88,
                height: 88,
                decoration: BoxDecoration(color: colors.secondaryContainer, shape: BoxShape.circle),
              ),
              const SizedBox(width: 20),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(ch.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
                  if (ch.subCount > 0)
                    Text(ctSubscribers(ch.subCount),
                        style: text.titleMedium?.copyWith(color: colors.onSurfaceVariant)),
                ]),
              ),
            ]),
            Align(
              alignment: Alignment.centerLeft,
              child: TvSubscribeButton(autoFocus: true, channelId: id, subCount: '', onFocusChanged: _toTop),
            ),
            if (ch.description.trim().isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: TvExpandableText(text: ch.description.trim(), maxLines: 2),
              ),
            _TvVideoRow(title: locals.videos, load: (c) => service.getChannelVideos(id, c)),
            _TvVideoRow(title: locals.shorts, load: (c) => service.getChannelShorts(id, c)),
            _TvVideoRow(title: locals.streams, load: (c) => service.getChannelStreams(id, c)),
            _TvPlaylistRow(title: locals.playlists, channelId: id),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    ]);
  }
}

/// Заголовок ряда показывается, только когда в ряду что-то нашлось.
class _RowTitle extends StatelessWidget {
  final String title;
  final bool visible;

  const _RowTitle({required this.title, required this.visible});

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 4),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

class _TvVideoRow extends StatefulWidget {
  final String title;
  final Future<VideosWithContinuation> Function(String? continuation) load;

  const _TvVideoRow({required this.title, required this.load});

  @override
  State<_TvVideoRow> createState() => _TvVideoRowState();
}

class _TvVideoRowState extends State<_TvVideoRow> {
  final _key = GlobalKey();
  bool _has = false;
  late final _list = ContinuationList<Video>((c) async {
    final page = await widget.load(c);
    if (!_has && page.videos.isNotEmpty && mounted) setState(() => _has = true);
    return page;
  });

  @override
  Widget build(BuildContext context) {
    return Column(key: _key, crossAxisAlignment: CrossAxisAlignment.start, children: [
      _RowTitle(title: widget.title, visible: _has),
      TvHorizontalVideoList(
        autoFocusedIndex: -1,
        paginatedVideoList: _list,
        onItemFocus: (v, i, focus) {
          if (focus) ctTvScrollToRow(_key);
        },
      ),
    ]);
  }
}

class _TvPlaylistRow extends StatefulWidget {
  final String title;
  final String channelId;

  const _TvPlaylistRow({required this.title, required this.channelId});

  @override
  State<_TvPlaylistRow> createState() => _TvPlaylistRowState();
}

class _TvPlaylistRowState extends State<_TvPlaylistRow> {
  final _key = GlobalKey();
  bool _has = false;
  late final _list = ContinuationList<Playlist>((c) async {
    final page = await service.getChannelPlaylists(widget.channelId, continuation: c);
    if (!_has && page.playlists.isNotEmpty && mounted) setState(() => _has = true);
    return page;
  });

  @override
  Widget build(BuildContext context) {
    return Column(key: _key, crossAxisAlignment: CrossAxisAlignment.start, children: [
      _RowTitle(title: widget.title, visible: _has),
      TvHorizontalItemList<Playlist>(
        getPlaceholder: () => const TvPlaylistPlaceHolder(),
        paginatedList: _list,
        buildItem: (context, index, item) => Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (f) {
            if (f) ctTvScrollToRow(_key);
          },
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: PlaylistInList(playlist: item, canDeleteVideos: false, isTv: true),
          ),
        ),
      ),
    ]);
  }
}
