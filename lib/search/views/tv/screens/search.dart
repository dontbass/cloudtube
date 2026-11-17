import 'package:auto_route/auto_route.dart';
import 'package:clipious/videos/models/video.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clipious/playlists/models/playlist.dart';
import 'package:clipious/playlists/views/components/playlist_in_list.dart';
import 'package:clipious/search/models/search_type.dart';
import 'package:clipious/utils/models/image_object.dart';
import 'package:clipious/utils/models/paginated_list.dart';
import 'package:clipious/utils/views/components/placeholders.dart';
import 'package:clipious/utils/views/components/thumbnail.dart';
import 'package:clipious/utils/views/tv/components/tv_button.dart';
import 'package:clipious/utils/views/tv/components/tv_horizontal_item_list.dart';
import 'package:clipious/utils/views/tv/components/tv_overscan.dart';
import 'package:clipious/utils/views/tv/components/tv_text_field.dart';

import '../../../../app/views/tv/screens/tv_home.dart' show ctTvScrollToRow, ctTvResetRow;
import '../../../../channels/models/channel.dart';
import '../../../../cloudtube/tv_channels.dart';
import '../../../../cloudtube/tv_nav.dart';
import '../../../../globals.dart';
import '../../../../settings/states/settings.dart';
import '../../../states/search.dart';
import '../../screens/search.dart' show searchPageSize;

/// Поиск на ТВ: поле сверху, слева подсказки/история, справа ряды
/// Видео / Каналы / Плейлисты. «Назад» из результатов — к полю ввода.
@RoutePage()
class TvSearchScreen extends StatelessWidget {
  const TvSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SearchCubit(context.read<SettingsCubit>()),
      child: const Scaffold(body: CtTvLeftEdge(child: TvOverscan(child: _TvSearchBody()))),
    );
  }
}

class _TvSearchBody extends StatefulWidget {
  const _TvSearchBody();

  @override
  State<_TvSearchBody> createState() => _TvSearchBodyState();
}

class _TvSearchBodyState extends State<_TvSearchBody> {
  final _controller = TextEditingController();
  final _field = FocusNode();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => context.read<SearchCubit>().onTextChanged(_controller.text));
  }

  @override
  void dispose() {
    _controller.dispose();
    _field.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _submit(String t) {
    _controller.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    context.read<SearchCubit>().submit(t);
  }

  KeyEventResult _back(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent && (e.logicalKey == LogicalKeyboardKey.goBack || e.logicalKey == LogicalKeyboardKey.escape)) {
      _field.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return BlocBuilder<SearchCubit, SearchState>(builder: (context, s) {
      final typing = s.text.trim().isNotEmpty && s.text.trim() != s.query;
      final hints = typing ? s.suggestions : s.history;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TvTextField(
          leading: Icon(Icons.search_rounded, color: colors.onSurfaceVariant),
          controller: _controller,
          autofocus: true,
          autocorrect: true,
          focusNode: _field,
          onSubmitted: _submit,
          textInputAction: TextInputAction.search,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: FocusScope(
            onKeyEvent: _back,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 280,
                child: ListView(children: [
                  if (hints.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                      child: Text(typing ? 'Подсказки' : 'Вы искали',
                          style: text.titleSmall?.copyWith(color: colors.onSurfaceVariant)),
                    ),
                  for (final h in hints)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: TvButton(
                        borderRadius: 14,
                        unfocusedColor: Colors.transparent,
                        onPressed: (_) => _submit(h),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                          child: Row(children: [
                            Icon(typing ? Icons.search_rounded : Icons.history_rounded, size: 22),
                            const SizedBox(width: 10),
                            Flexible(child: Text(h, maxLines: 2, overflow: TextOverflow.ellipsis)),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: s.query.isEmpty
                    ? Center(
                        child: Text('Наберите запрос и нажмите «Поиск» на клавиатуре',
                            style: text.titleMedium?.copyWith(color: colors.onSurfaceVariant)))
                    : _TvResults(key: ValueKey('${s.query}|${s.filters.key}'), query: s.query, scroll: _scroll),
              ),
            ]),
          ),
        ),
      ]);
    });
  }
}

class _TvResults extends StatelessWidget {
  final String query;
  final ScrollController scroll;

  const _TvResults({super.key, required this.query, required this.scroll});

  @override
  Widget build(BuildContext context) {
    return CtTvSmoothTraversal(
      child: ListView(controller: scroll, children: [
        _TvRow<Video>(
          title: 'Видео',
          load: (p) => service.search(query, page: p, type: SearchType.video).then((r) => r.videos),
          build: (list, onFocus) => TvHorizontalVideoList(
              autoFocusedIndex: -1, paginatedVideoList: list, onItemFocus: (v, i, f) => onFocus(f)),
        ),
        _TvRow<Channel>(
          title: 'Каналы',
          load: (p) => service.search(query, page: p, type: SearchType.channel).then((r) => r.channels),
          build: (list, onFocus) => TvHorizontalItemList<Channel>(
            getPlaceholder: () => const TvChannelPlaceholder(),
            paginatedList: list,
            buildItem: (context, i, c) => _TvChannelTile(channel: c, onFocus: onFocus),
          ),
        ),
        _TvRow<Playlist>(
          title: 'Плейлисты',
          load: (p) => service.search(query, page: p, type: SearchType.playlist).then((r) => r.playlists),
          build: (list, onFocus) => TvHorizontalItemList<Playlist>(
            getPlaceholder: () => const TvPlaylistPlaceHolder(),
            paginatedList: list,
            buildItem: (context, i, item) => Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: onFocus,
              child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: PlaylistInList(playlist: item, canDeleteVideos: false, isTv: true)),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ]),
    );
  }
}

/// Ряд результатов: заголовок появляется, когда что-то нашлось; при фокусе ряд встаёт вверх.
class _TvRow<T> extends StatefulWidget {
  final String title;
  final Future<List<T>> Function(int page) load;
  final Widget Function(PaginatedList<T> list, void Function(bool focus) onFocus) build;

  const _TvRow({required this.title, required this.load, required this.build});

  @override
  State<_TvRow<T>> createState() => _TvRowState<T>();
}

class _TvRowState<T> extends State<_TvRow<T>> {
  final _key = GlobalKey();
  bool? _has;
  late final _list = PageBasedPaginatedList<T>(
    maxResults: searchPageSize,
    getItemsFunc: (page, _) async {
      final r = await widget.load(page);
      if (page == 1 && mounted) setState(() => _has = r.isNotEmpty);
      return r;
    },
  );

  void _onFocus(bool f) {
    if (f) ctTvScrollToRow(_key);
  }

  @override
  Widget build(BuildContext context) {
    if (_has == false) return const SizedBox.shrink();
    return Column(key: _key, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4, left: 4),
        child: Text(widget.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      ),
      widget.build(_list, _onFocus),
    ]);
  }
}

class _TvChannelTile extends StatelessWidget {
  final Channel channel;
  final void Function(bool focus) onFocus;

  const _TvChannelTile({required this.channel, required this.onFocus});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TvButton(
        borderRadius: 20,
        unfocusedColor: Colors.transparent,
        onFocusChanged: onFocus,
        onPressed: (ctx) {
          ctTvResetRow();
          ctOpenTvChannel(ctx, channel.authorId);
        },
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Thumbnail(
                  width: 96,
                  height: 96,
                  thumbnails: ImageObject.getThumbnailUrlsByPreferredOrder(channel.authorThumbnails),
                  decoration: BoxDecoration(color: colors.secondaryContainer, shape: BoxShape.circle)),
              const SizedBox(height: 8),
              Text(channel.author,
                  maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
            ]),
          ),
        ),
      ),
    );
  }
}
