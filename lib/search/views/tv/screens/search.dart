import 'package:auto_route/auto_route.dart';
import 'package:cloudtube/videos/models/video.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloudtube/playlists/models/playlist.dart';
import 'package:cloudtube/playlists/views/components/playlist_in_list.dart';
import 'package:cloudtube/search/models/search_type.dart';
import 'package:cloudtube/utils/models/image_object.dart';
import 'package:cloudtube/utils/models/paginated_list.dart';
import 'package:cloudtube/utils/views/components/placeholders.dart';
import 'package:cloudtube/utils/views/components/thumbnail.dart';
import 'package:cloudtube/utils/views/tv/components/tv_button.dart';
import 'package:cloudtube/utils/views/tv/components/tv_horizontal_item_list.dart';
import 'package:cloudtube/utils/views/tv/components/tv_overscan.dart';

import '../../../../channels/models/channel.dart';
import '../../../../cloudtube/theme.dart';
import '../../../../router.dart';
import '../../../../utils.dart';
import '../../../../cloudtube/tv_channels.dart';
import '../../../../cloudtube/tv_nav.dart';
import '../../../../globals.dart';
import '../../../../settings/states/settings.dart';
import '../../../states/search.dart';
import '../../screens/search.dart' show searchPageSize;

/// Поиск на ТВ: строка запроса сверху, слева своя клавиатура и подсказки по ходу набора,
/// справа ряды Видео / Каналы / Плейлисты. «Назад» из результатов — к клавиатуре.
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

/// Раскладки экранной клавиатуры: по алфавиту, как в YouTube на ТВ — с пульта так быстрее, чем ЙЦУКЕН.
enum _Layout {
  ru('RU', 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя'),
  en('EN', 'abcdefghijklmnopqrstuvwxyz'),
  digits('123', "1234567890-'.,!?&:+#@\"()");

  final String label;
  final String keys;
  const _Layout(this.label, this.keys);
}

class _TvSearchBodyState extends State<_TvSearchBody> {
  // Раньше набор шёл на отдельном экране системной клавиатуры: подсказки появлялись только после
  // «Поиск» — уже бесполезные. Теперь своя клавиатура прямо на экране поиска, подсказки — по ходу.
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _keyNodes = <String, FocusNode>{};
  var _layout = _Layout.ru;
  var _resultsFocused = false;
  String _lastKey = 'а';

  // 9 столбцов: русский алфавит — 4 ряда; вместе с двумя рядами действий клавиатура
  // помещается по высоте, а подсказки стоят справа от неё (раньше уезжали за нижний край)
  static const _cols = 9;
  static const _key = 34.0;
  static const _gap = 4.0;
  static const _panel = _cols * (_key + _gap);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => context.read<SearchCubit>().onTextChanged(_controller.text));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    for (final n in _keyNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  FocusNode _node(String id) => _keyNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'key $id'));

  static double _w(int n) => _key * n + _gap * (n - 1);

  void _setText(String t) => _controller.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));

  void _type(String ch) => _setText(_controller.text + ch);

  void _backspace() {
    final t = _controller.text.characters;
    if (t.isNotEmpty) _setText(t.skipLast(1).toString());
  }

  void _submit(String t) {
    if (t.trim().isEmpty) return;
    _setText(t.trim());
    context.read<SearchCubit>().submit(t);
  }

  /// Системная клавиатура (в том числе голосовой ввод с пульта) — прежний экран ввода.
  void _systemKeyboard() {
    AutoRouter.of(context).push(TvTextFieldRoute(
        controller: _controller, autocorrect: true, textInputAction: TextInputAction.search, onSubmitted: _submit));
  }

  /// Вернуться на клавиатуру: сначала показать её (в результатах она свёрнута), потом поставить фокус
  /// на последнюю нажатую клавишу.
  void _focusKeyboard() {
    if (_resultsFocused) setState(() => _resultsFocused = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_keyNodes[_lastKey] ?? _node('search')).requestFocus();
    });
  }

  /// Физическая клавиатура / цифры на пульте — печатают сразу, пока фокус на экранной клавиатуре.
  KeyEventResult _hardwareKeys(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    final ch = e.character;
    if (ch != null && ch.length == 1 && RegExp(r"[\p{L}\p{N} \-'.,!?&:+#@]", unicode: true).hasMatch(ch)) {
      _type(ch.toLowerCase());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _backFromResults(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent && (e.logicalKey == LogicalKeyboardKey.goBack || e.logicalKey == LogicalKeyboardKey.escape)) {
      _focusKeyboard();
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
      final hints = (typing ? s.suggestions : (s.text.trim().isEmpty ? s.history : const <String>[])).take(8).toList();
      final keyboard = _resultsFocused && s.query.isNotEmpty
          // в результатах клавиатура прячется в узкую полоску — рядам достаётся вся ширина
          ? SizedBox(
              width: 56,
              child: Align(
                alignment: Alignment.topCenter,
                child: _Key(
                  node: _node('rail'),
                  width: 48,
                  onFocus: (f) {
                    if (f) _focusKeyboard();
                  },
                  onPressed: _focusKeyboard,
                  child: const Icon(Icons.keyboard_rounded),
                ),
              ),
            )
          : SizedBox(
              width: _panel,
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _hardwareKeys,
                child: ListView(padding: EdgeInsets.zero, children: [
                  Wrap(spacing: _gap, runSpacing: _gap, children: [
                    for (final ch in _layout.keys.characters)
                      _Key(
                        node: _node(ch),
                        autofocus: ch == _Layout.ru.keys[0] && _layout == _Layout.ru && s.query.isEmpty,
                        onFocus: (f) {
                          if (f) _lastKey = ch;
                        },
                        onPressed: () => _type(ch),
                        child: Text(ch, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      ),
                  ]),
                  const SizedBox(height: _gap * 2),
                  Wrap(spacing: _gap, runSpacing: _gap, children: [
                    _Key(
                        node: _node('space'),
                        width: _w(4),
                        onFocus: (f) {
                          if (f) _lastKey = 'space';
                        },
                        onPressed: () => _type(' '),
                        child: const Icon(Icons.space_bar_rounded)),
                    _Key(
                        node: _node('bs'),
                        width: _w(2),
                        onFocus: (f) {
                          if (f) _lastKey = 'bs';
                        },
                        onPressed: _backspace,
                        child: const Icon(Icons.backspace_outlined)),
                    _Key(
                        node: _node('clear'),
                        width: _w(3),
                        onFocus: (f) {
                          if (f) _lastKey = 'clear';
                        },
                        onPressed: () => _setText(''),
                        child: const Text('Стереть', style: TextStyle(fontSize: 13))),
                    // одна клавиша раскладки: RU → EN → 123 по кругу
                    _Key(
                      node: _node('layout'),
                      width: _w(2),
                      onFocus: (f) {
                        if (f) _lastKey = 'layout';
                      },
                      onPressed: () => setState(() => _layout = _Layout.values[(_layout.index + 1) % _Layout.values.length]),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.language_rounded, size: 16),
                        const SizedBox(width: 4),
                        Text(_layout.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    _Key(
                        node: _node('system'),
                        onFocus: (f) {
                          if (f) _lastKey = 'system';
                        },
                        onPressed: _systemKeyboard,
                        child: const Icon(Icons.mic_none_rounded)),
                    _Key(
                        node: _node('search'),
                        width: _w(6),
                        accent: true,
                        onFocus: (f) {
                          if (f) _lastKey = 'search';
                        },
                        onPressed: () => _submit(_controller.text),
                        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.search_rounded, size: 20),
                          SizedBox(width: 6),
                          Text('Найти', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        ])),
                  ]),
                ]),
              ),
            );
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // строка запроса: только показывает набранное (печатают на клавиатуре ниже)
        Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: colors.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.search_rounded, color: colors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: s.text.isEmpty
                  ? Text('Поиск', style: text.titleMedium?.copyWith(color: colors.onSurfaceVariant))
                  : Text.rich(
                      TextSpan(children: [
                        TextSpan(text: s.text),
                        TextSpan(text: '▏', style: TextStyle(color: ctAccent(colors))),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(left: 8), child: keyboard),
            const SizedBox(width: 20),
            Expanded(
              // пока печатают — подсказки (крупно, справа от клавиатуры), после «Найти» — результаты
              child: s.query.isEmpty || typing
                  ? (hints.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                                s.text.trim().isEmpty
                                    ? 'Наберите запрос — подсказки появятся здесь. 🎤 — голосовой ввод'
                                    : 'Нажмите «Найти»',
                                textAlign: TextAlign.center,
                                style: text.titleMedium?.copyWith(color: colors.onSurfaceVariant)),
                          ))
                      : ListView(padding: EdgeInsets.zero, children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                            child: Text(typing ? 'Подсказки' : 'Вы искали',
                                style: text.titleSmall?.copyWith(color: colors.onSurfaceVariant)),
                          ),
                          for (final h in hints)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: TvButton(
                                borderRadius: 12,
                                unfocusedColor: Colors.transparent,
                                onPressed: (_) => _submit(h),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(typing ? Icons.search_rounded : Icons.history_rounded, size: 22),
                                    const SizedBox(width: 12),
                                    Flexible(
                                        child: Text(h,
                                            maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium)),
                                  ]),
                                ),
                              ),
                            ),
                        ]))
                  : Focus(
                      canRequestFocus: false,
                      skipTraversal: true,
                      onKeyEvent: _backFromResults,
                      onFocusChange: (f) {
                        if (f != _resultsFocused) setState(() => _resultsFocused = f);
                      },
                      child: _TvResults(key: ValueKey('${s.query}|${s.filters.key}'), query: s.query, scroll: _scroll),
                    ),
            ),
          ]),
        ),
      ]);
    });
  }
}

/// Клавиша экранной клавиатуры.
class _Key extends StatelessWidget {
  final FocusNode node;
  final Widget child;
  final VoidCallback onPressed;
  final void Function(bool focus)? onFocus;
  final double width;
  final bool autofocus;
  final bool accent;

  const _Key(
      {required this.node,
      required this.child,
      required this.onPressed,
      this.onFocus,
      this.width = _TvSearchBodyState._key,
      this.autofocus = false,
      this.accent = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Focus(
      focusNode: node,
      autofocus: autofocus,
      onFocusChange: onFocus,
      onKeyEvent: (n, e) => onTvSelect(e, context, (_) => onPressed()),
      child: Builder(builder: (ctx) {
        final f = Focus.of(ctx).hasFocus;
        final fg = f ? colors.onPrimary : (accent ? ctAccent(colors) : colors.onSurface);
        return GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: width,
            height: _TvSearchBodyState._key,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: f
                  ? ctAccent(colors)
                  : (accent ? ctAccent(colors).withValues(alpha: 0.14) : colors.surfaceContainerHigh),
              border: ctFocusBorder(colors, f),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconTheme.merge(
                data: IconThemeData(color: fg, size: 22),
                child: DefaultTextStyle.merge(style: TextStyle(color: fg), child: child)),
          ),
        );
      }),
    );
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
  bool? _has;
  late final _list = PageBasedPaginatedList<T>(
    maxResults: searchPageSize,
    getItemsFunc: (page, _) async {
      final r = await widget.load(page);
      if (page == 1 && mounted) setState(() => _has = r.isNotEmpty);
      return r;
    },
  );

  // прокрутку к ряду делает CtTvRow; отдельный обработчик фокуса плиток больше не нужен
  void _onFocus(bool f) {}

  @override
  Widget build(BuildContext context) {
    if (_has == false) return const SizedBox.shrink();
    return CtTvRow(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4, left: 4),
        child: Text(widget.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      ),
      widget.build(_list, _onFocus),
    ]));
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
