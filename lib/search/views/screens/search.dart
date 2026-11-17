import 'package:auto_route/auto_route.dart';
import 'package:clipious/channels/models/channel.dart';
import 'package:clipious/globals.dart';
import 'package:clipious/playlists/models/playlist.dart';
import 'package:clipious/playlists/views/components/playlist_list.dart';
import 'package:clipious/router.dart';
import 'package:clipious/search/models/search_results.dart';
import 'package:clipious/search/models/search_type.dart';
import 'package:clipious/search/views/components/search_filters.dart';
import 'package:clipious/utils/models/image_object.dart';
import 'package:clipious/utils/models/paginated_list.dart';
import 'package:clipious/utils/views/components/thumbnail.dart';
import 'package:clipious/videos/models/video.dart';
import 'package:clipious/videos/views/components/video_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../channels/views/screens/channel.dart' show ctSubscribers;
import '../../../cloudtube/ui_state.dart';
import '../../../settings/states/settings.dart';
import '../../states/search.dart';

/// Invidious отдаёт по 20 результатов на страницу — по этому числу работают списки.
const searchPageSize = 20;

/// Поиск: поле-«пилюля» сверху, пока печатаешь — подсказки и история,
/// после поиска — вкладки Видео / Каналы / Плейлисты (свайпом).
@RoutePage()
class SearchScreen extends StatefulWidget {
  final String? query;
  final bool? searchNow;

  const SearchScreen({super.key, this.query, this.searchNow});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final _controller = TextEditingController(text: widget.query ?? '');
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setText(String t, {bool submit = false}) {
    _controller.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    final cubit = context.read<SearchCubit>();
    if (submit) {
      _focus.unfocus();
      cubit.submit(t);
    } else {
      cubit.onTextChanged(t);
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SearchCubit(context.read<SettingsCubit>(),
          query: widget.query, searchNow: widget.searchNow ?? false),
      child: BlocBuilder<SearchCubit, SearchState>(builder: (context, s) {
        final cubit = context.read<SearchCubit>();
        final colors = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: widget.query == null,
              textInputAction: TextInputAction.search,
              onChanged: cubit.onTextChanged,
              onSubmitted: (t) => _setText(t, submit: true),
              decoration: InputDecoration(
                hintText: 'Поиск на YouTube',
                filled: true,
                fillColor: colors.surfaceContainerHigh,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                suffixIcon: s.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Очистить',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => _setText('')),
              ),
            ),
            actions: [
              SearchFiltersButton(filters: s.filters, onChanged: cubit.setFilters),
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: s.showResults
                ? _Results(key: ValueKey('${s.query}|${s.filters.key}'), query: s.query, filters: s.filters)
                : _Suggestions(
                    state: s,
                    onPick: (t) => _setText(t, submit: true),
                    onFill: (t) => _setText('$t '),
                  ),
          ),
        );
      }),
    );
  }
}

/// Подсказки (пока печатаешь) или история (пустое поле).
class _Suggestions extends StatelessWidget {
  final SearchState state;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onFill;

  const _Suggestions({required this.state, required this.onPick, required this.onFill});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SearchCubit>();
    final colors = Theme.of(context).colorScheme;
    final typing = state.text.trim().isNotEmpty;
    final items = typing ? state.suggestions : state.history;

    if (!typing && items.isEmpty) {
      return const CtEmptyView(icon: Icons.search_rounded, text: 'Найдите видео, канал или плейлист');
    }
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      if (state.query.isNotEmpty && typing)
        ListTile(
          leading: Icon(Icons.arrow_back_rounded, color: colors.onSurfaceVariant),
          title: Text('Вернуться к «${state.query}»'),
          onTap: cubit.showResults,
        ),
      if (!typing)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
          child: Row(children: [
            Text('Вы искали', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton(onPressed: cubit.clearHistory, child: const Text('Очистить')),
          ]),
        ),
      for (final e in items)
        ListTile(
          leading: Icon(typing ? Icons.search_rounded : Icons.history_rounded, color: colors.onSurfaceVariant),
          title: Text(e, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => onPick(e),
          trailing: typing
              ? IconButton(
                  tooltip: 'Дописать',
                  icon: Icon(Icons.north_west_rounded, color: colors.onSurfaceVariant),
                  onPressed: () => onFill(e))
              : IconButton(
                  tooltip: 'Удалить из истории',
                  icon: Icon(Icons.close_rounded, color: colors.onSurfaceVariant),
                  onPressed: () => cubit.removeFromHistory(e)),
        ),
    ]);
  }
}

/// Результаты: вкладки Видео / Каналы / Плейлисты, каждая грузится при первом открытии.
class _Results extends StatelessWidget {
  final String query;
  final SearchFilters filters;

  const _Results({super.key, required this.query, required this.filters});

  Future<T> _search<T>(int page, SearchType type, T Function(SearchResults r) pick) => service
      .search(query, page: page, type: type, sortBy: filters.sortBy, date: filters.date, duration: filters.duration)
      .then(pick);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerHeight: 0.5,
          tabs: [Tab(text: 'Видео'), Tab(text: 'Каналы'), Tab(text: 'Плейлисты')],
        ),
        Expanded(
          child: TabBarView(children: [
            CtKeepAlive(
              child: VideoList(
                paginatedVideoList: PageBasedPaginatedList<Video>(
                  maxResults: searchPageSize,
                  getItemsFunc: (page, _) =>
                      _search<List<Video>>(page, SearchType.video, (r) => r.videos),
                ),
              ),
            ),
            CtKeepAlive(
              child: _ChannelResults(
                  load: (page) =>
                      _search<List<Channel>>(page, SearchType.channel, (r) => r.channels)),
            ),
            CtKeepAlive(
              child: PlaylistList(
                canDeleteVideos: false,
                paginatedList: PageBasedPaginatedList<Playlist>(
                  maxResults: searchPageSize,
                  getItemsFunc: (page, _) => _search<List<Playlist>>(
                      page, SearchType.playlist, (r) => r.playlists),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Каналы в результатах: аватар, название, подписчики; догрузка при прокрутке,
/// пустой результат и ошибка — понятными экранами.
class _ChannelResults extends StatefulWidget {
  final Future<List<Channel>> Function(int page) load;

  const _ChannelResults({required this.load});

  @override
  State<_ChannelResults> createState() => _ChannelResultsState();
}

class _ChannelResultsState extends State<_ChannelResults> {
  final _items = <Channel>[];
  final _seen = <String>{};
  int _page = 0;
  bool _loading = false, _more = true, _error = false;

  @override
  void initState() {
    super.initState();
    _next();
  }

  Future<void> _next() async {
    if (_loading || !_more) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final list = await widget.load(_page + 1);
      _page++;
      final add = list.where((c) => _seen.add(c.authorId)).toList();
      if (!mounted) return;
      setState(() {
        _items.addAll(add);
        _more = add.isNotEmpty;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      if (_error) return CtErrorView(message: 'Не удалось найти каналы', onRetry: _next);
      if (_loading) return const Center(child: CircularProgressIndicator());
      return const CtEmptyView(icon: Icons.person_search_rounded, text: 'Каналы не найдены');
    }
    final colors = Theme.of(context).colorScheme;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 400) _next();
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
        itemCount: _items.length + (_loading || _error ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                  child: _error
                      ? TextButton(onPressed: _next, child: const Text('Повторить'))
                      : const CircularProgressIndicator()),
            );
          }
          final c = _items[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: Thumbnail(
                width: 52,
                height: 52,
                thumbnails: ImageObject.getThumbnailUrlsByPreferredOrder(c.authorThumbnails),
                decoration: BoxDecoration(color: colors.secondaryContainer, shape: BoxShape.circle)),
            title: Text(c.author, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: c.subCount > 0
                ? Text(ctSubscribers(c.subCount), style: TextStyle(color: colors.onSurfaceVariant))
                : null,
            trailing: Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            onTap: () => AutoRouter.of(context).push(ChannelRoute(channelId: c.authorId)),
          );
        },
      ),
    );
  }
}
