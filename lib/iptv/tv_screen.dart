import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:river_player/river_player.dart';

import '../cloudtube/media_caps.dart';
import '../cloudtube/prefs.dart';
import '../cloudtube/theme.dart';
import '../router.dart';
import '../utils/views/tv/components/tv_button.dart';
import '../utils/views/tv/components/tv_overscan.dart';
import 'epg.dart';
import 'link.dart';
import 'programme.dart';
import 'm3u.dart';
import 'player.dart';
import 'store.dart';

/// Раздел «ТВ-каналы» на телевизоре: группы | каналы | превью с информацией.
class IptvTvScreen extends StatefulWidget {
  const IptvTvScreen({super.key});

  @override
  State<IptvTvScreen> createState() => _IptvTvScreenState();
}

const _kFav = '__fav', _kRecent = '__recent', _kAll = '__all';

class _IptvTvScreenState extends State<IptvTvScreen> {
  final _store = IptvStore.I;
  IptvParsed? _data;
  String? _error;
  bool _loading = true;
  String _group = _kAll;
  String _query = '';
  int _focused = 0;
  bool _firstFocusDone = false;

  // превью справа: запускается, когда фокус задержался на канале
  BetterPlayerController? _preview;
  Timer? _previewTimer;
  IptvChannel? _previewCh;
  bool _previewReady = false;

  final _search = TextEditingController();
  String _digits = '';
  Timer? _digitTimer;
  final _listCtl = ScrollController();

  @override
  void initState() {
    super.initState();
    IptvEpg.I.now.addListener(_epgChanged);
    unawaited(CtMediaCaps.load());
    _load();
  }

  void _epgChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    IptvEpg.I.now.removeListener(_epgChanged);
    _previewTimer?.cancel();
    _digitTimer?.cancel();
    _preview?.dispose(forceDispose: true);
    _search.dispose();
    _listCtl.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _store.load();
      final p = _store.current;
      if (p == null) {
        setState(() {
          _data = null;
          _loading = false;
        });
        return;
      }
      final d = await _store.channels(p, force: force);
      if (!mounted) return;
      // телепрограмма: с диска сразу, пересборка в фоне раз в 12 ч
      unawaited(IptvEpg.I.ensure(p, d));
      setState(() {
        _data = d;
        _loading = false;
        if (_group != _kAll && _group != _kFav && _group != _kRecent && !d.groups.contains(_group)) _group = _kAll;
      });
      // последний канал при входе — если включено в настройках
      final last = _store.lastChannelKey;
      if (_store.settings.value.resumeLast && last != null && !force) {
        final all = d.channels;
        final i = all.indexWhere((c) => c.key == last);
        if (i >= 0) WidgetsBinding.instance.addPostFrameCallback((_) => _open(all, i));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  List<IptvChannel> get _channels {
    final d = _data;
    if (d == null) return const [];
    List<IptvChannel> list;
    switch (_group) {
      case _kAll:
        list = d.channels;
      case _kFav:
        final byKey = {for (final c in d.channels) c.key: c};
        list = _store.favorites.value.map((k) => byKey[k]).whereType<IptvChannel>().toList();
      case _kRecent:
        final byKey = {for (final c in d.channels) c.key: c};
        list = _store.recent.value.map((k) => byKey[k]).whereType<IptvChannel>().toList();
      default:
        list = d.channels.where((c) => c.group == _group).toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) list = d.channels.where((c) => c.name.toLowerCase().contains(q)).toList();
    return list;
  }

  void _focusChannel(IptvChannel c, int i) {
    _focused = i;
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 900), () => _startPreview(c));
    setState(() {});
  }

  Future<void> _startPreview(IptvChannel c) async {
    if (!mounted || _previewCh?.key == c.key) return;
    _previewCh = c;
    _previewReady = false;
    var ctl = _preview;
    if (ctl == null) {
      ctl = _preview = iptvController(preview: true);
      ctl.addEventsListener((e) {
        if (e.betterPlayerEventType == BetterPlayerEventType.initialized && mounted) {
          setState(() => _previewReady = true);
        }
      });
    }
    setState(() {});
    try {
      final src = await iptvSource(c, iptvPickStream(c, _store.settings.value));
      if (!mounted || _previewCh?.key != c.key) return;
      await ctl.setupDataSource(src);
    } catch (_) {}
  }

  void _stopPreview() {
    _previewTimer?.cancel();
    _preview?.pause();
    _previewCh = null;
  }

  Future<void> _open(List<IptvChannel> list, int i, {String? quality}) async {
    _stopPreview();
    // освободить декодер: на приставках одновременно два плеера HD часто не тянут
    _preview?.dispose(forceDispose: true);
    _preview = null;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            IptvPlayerScreen(channels: list, index: i, all: _data?.channels ?? list, initialQuality: quality)));
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const IptvAddScreen()));
    if (ok == true) _load();
  }

  Future<void> _playlistMenu() async {
    final pls = _store.playlists.value;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Плейлисты'),
        children: [
          for (final p in pls)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'sel:${p.id}'),
              child: Text('${p.id == _store.current?.id ? '✓ ' : ''}${p.name}', style: const TextStyle(fontSize: 17)),
            ),
          const Divider(),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'add'), child: const Text('＋ Добавить плейлист')),
          if (_store.current?.url.isNotEmpty == true)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'refresh'), child: const Text('↻ Обновить текущий')),
          if (_store.current != null)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'epg'), child: const Text('☰ Источник телепрограммы')),
          if (_store.current != null)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'epg-refresh'), child: const Text('↻ Обновить телепрограмму')),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'settings'), child: const Text('⚙ Настройки IPTV')),
          if (_store.current != null)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'del'), child: const Text('✕ Удалить текущий')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice.startsWith('sel:')) {
      await _store.selectPlaylist(choice.substring(4));
      _group = _kAll;
      _load();
    } else if (choice == 'add') {
      _add();
    } else if (choice == 'refresh') {
      _load(force: true);
    } else if (choice == 'epg-refresh') {
      final p = _store.current, d = _data;
      if (p != null && d != null) unawaited(IptvEpg.I.ensure(p, d, force: true));
    } else if (choice == 'epg') {
      final p = _store.current!;
      final ctl = TextEditingController(text: p.epgUrl);
      AutoRouter.of(context).push(TvTextFieldRoute(
          controller: ctl,
          autocorrect: false,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) async {
            await _store.update(p.copyWith(epgUrl: v.trim()));
            final d = _data;
            if (d != null && _store.current != null) unawaited(IptvEpg.I.ensure(_store.current!, d, force: true));
          }));
    } else if (choice == 'settings') {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IptvSettingsScreen()));
      _load();
    } else if (choice == 'del') {
      final p = _store.current!;
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Удалить «${p.name}»?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(autofocus: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
          ],
        ),
      );
      if (yes == true) {
        await _store.remove(p.id);
        _load();
      }
    }
  }

  void _openSearch() {
    AutoRouter.of(context).push(TvTextFieldRoute(
        controller: _search,
        autocorrect: false,
        textInputAction: TextInputAction.search,
        onSubmitted: (v) => setState(() => _query = v)));
  }

  /// Цифры в списке — переход к каналу по номеру.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = e.character;
    final d = ch == null || ch.length != 1 ? null : int.tryParse(ch);
    if (d == null) {
      if (e.logicalKey == LogicalKeyboardKey.contextMenu) {
        final list = _channels;
        if (_focused < list.length) _channelMenu(list[_focused]);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    _digitTimer?.cancel();
    setState(() => _digits += '$d');
    _digitTimer = Timer(const Duration(milliseconds: 1300), () {
      final n = int.tryParse(_digits);
      setState(() => _digits = '');
      if (n == null) return;
      final all = _data?.channels ?? const <IptvChannel>[];
      final i = all.indexWhere((c) => c.number == n);
      if (i >= 0) _open(all, i);
    });
    return KeyEventResult.handled;
  }

  Future<void> _channelMenu(IptvChannel c) async {
    final fav = _store.favorites.value.contains(c.key);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(c.name),
        children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'fav'),
              child: Text(fav ? '★ Убрать из избранного' : '☆ В избранное', style: const TextStyle(fontSize: 17))),
          for (final s in c.streams)
            if (c.streams.length > 1)
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, 'q:${s.quality}'),
                  child: Text('▶ Смотреть в ${s.quality.isEmpty ? 'обычном' : s.quality}')),
        ],
      ),
    );
    if (r == 'fav') {
      await _store.toggleFavorite(c.key);
      setState(() {});
    } else if (r != null && r.startsWith('q:')) {
      final list = _channels;
      final i = list.indexWhere((x) => x.key == c.key);
      if (i >= 0) _open(list, i, quality: r.substring(2));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pl = _store.current;
    return Scaffold(
      body: TvOverscan(
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.live_tv, color: ctAccent(colors), size: 28),
              const SizedBox(width: 10),
              Flexible(
                child: Text(pl == null ? 'ТВ-каналы' : 'ТВ-каналы · ${pl.name}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleLarge),
              ),
              if (_query.isNotEmpty) ...[
                const SizedBox(width: 12),
                InputChip(label: Text('Поиск: $_query'), onDeleted: () => setState(() => _query = '')),
              ],
              const Spacer(),
              ValueListenableBuilder<String?>(
                valueListenable: IptvEpg.I.busy,
                builder: (_, b, __) => b == null
                    ? const SizedBox()
                    : Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 8),
                          Text(b, style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                        ]),
                      ),
              ),
              if (_digits.isNotEmpty)
                Text('№ $_digits', style: text.headlineSmall?.copyWith(color: ctAccent(colors))),
              const SizedBox(width: 12),
              if (pl != null) ...[
                _TopButton(icon: Icons.search, label: 'Поиск', onPressed: _openSearch),
                const SizedBox(width: 8),
              ],
              _TopButton(icon: Icons.playlist_play, label: 'Плейлисты', onPressed: pl == null ? _add : _playlistMenu),
            ]),
            const SizedBox(height: 12),
            Expanded(child: _body(colors, text)),
          ]),
        ),
      ),
    );
  }

  Widget _body(ColorScheme colors, TextTheme text) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_store.current == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.live_tv, size: 64, color: colors.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('Добавьте плейлист IPTV', style: text.headlineSmall),
          const SizedBox(height: 6),
          Text('Ссылку на плейлист (M3U) можно отправить с телефона по QR-коду или ввести с пульта',
              style: text.titleMedium?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 18),
          FilledButton.icon(
              autofocus: true, onPressed: _add, icon: const Icon(Icons.qr_code_2), label: const Text('Добавить плейлист')),
        ]),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: text.titleMedium),
          const SizedBox(height: 12),
          FilledButton(autofocus: true, onPressed: () => _load(force: true), child: const Text('Повторить')),
          TextButton(onPressed: _playlistMenu, child: const Text('Плейлисты')),
        ]),
      );
    }
    final d = _data!;
    final list = _channels;
    final groups = [
      (_kFav, '★ Избранное', _store.favorites.value.length),
      (_kRecent, 'Недавние', _store.recent.value.length),
      (_kAll, 'Все', d.channels.length),
      for (final g in d.groups) (g, g, d.channels.where((c) => c.group == g).length),
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // группы
      SizedBox(
        width: 190,
        child: ListView(children: [
          for (final (id, label, n) in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: TvButton(
                borderRadius: 12,
                unfocusedColor: id == _group ? colors.secondaryContainer : Colors.transparent,
                onPressed: (_) => setState(() {
                  _group = id;
                  _query = '';
                  _focused = 0;
                  if (_listCtl.hasClients) _listCtl.jumpTo(0);
                }),
                onFocusChanged: (f) {
                  if (f && id != _group) {
                    setState(() {
                      _group = id;
                      _query = '';
                      _focused = 0;
                      if (_listCtl.hasClients) _listCtl.jumpTo(0);
                    });
                  }
                },
                child: SizedBox(
                  width: 180,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Row(children: [
                      Expanded(
                          child: Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 15, fontWeight: id == _group ? FontWeight.w700 : FontWeight.w500))),
                      Text('$n', style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(width: 10),
      // каналы
      SizedBox(
        width: 360,
        child: list.isEmpty
            ? Center(
                child: Text(
                    _group == _kFav ? 'В избранном пусто — МЕНЮ на канале → «В избранное»' : 'Нет каналов',
                    textAlign: TextAlign.center,
                    style: text.titleMedium?.copyWith(color: colors.onSurfaceVariant)))
            : ListView.builder(
                controller: _listCtl,
                itemExtent: 58,
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final c = list[i];
                  final fav = _store.favorites.value.contains(c.key);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: TvButton(
                      key: ValueKey('${_group}_${c.key}'),
                      // фокус на первый канал — только при первом открытии раздела
                      autofocus: i == 0 && !_firstFocusDone,
                      borderRadius: 12,
                      unfocusedColor: Colors.transparent,
                      onFocusChanged: (f) {
                        if (f) {
                          _firstFocusDone = true;
                          _focusChannel(c, i);
                        }
                      },
                      onPressed: (_) => _open(list, i),
                      child: SizedBox(
                        width: 350,
                        height: 54,
                        child: Row(children: [
                          SizedBox(
                              width: 44,
                              child: Text('${c.number}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant))),
                          const SizedBox(width: 10),
                          IptvLogo(channel: c, size: 32),
                          const SizedBox(width: 10),
                          Expanded(child: _nameAndNow(c, colors)),
                          if (fav) const Icon(Icons.star, size: 16, color: Colors.amber),
                          if (c.hasArchive)
                            Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(Icons.history, size: 16, color: colors.onSurfaceVariant)),
                          const SizedBox(width: 8),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
      const SizedBox(width: 16),
      // превью и информация
      Expanded(child: _previewPanel(list, colors, text)),
    ]);
  }

  List<Widget> _previewEpg(IptvChannel c, ColorScheme colors, TextTheme text) {
    final cur = IptvEpg.I.current(c.key);
    if (cur == null) return const [];
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return [
      const SizedBox(height: 10),
      Text('${epgHm(cur.startTime)}–${epgHm(cur.stopTime)}  ${cur.title}',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
            value: cur.progress(nowSec), minHeight: 4, color: CtColors.red, backgroundColor: colors.outlineVariant),
      ),
      if (cur.desc.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(cur.desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
      ],
      const SizedBox(height: 6),
      for (final p in IptvEpg.I.upcoming(c.key, count: 3))
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(children: [
            SizedBox(width: 48, child: Text(epgHm(p.startTime), style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant))),
            Expanded(child: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium)),
          ]),
        ),
    ];
  }

  Widget _previewPanel(List<IptvChannel> list, ColorScheme colors, TextTheme text) {
    if (list.isEmpty || _focused >= list.length) return const SizedBox();
    final c = list[_focused];
    final s = iptvPickStream(c, _store.settings.value);
    return SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: Colors.black),
            if (_preview != null && _previewCh?.key == c.key) BetterPlayer(controller: _preview!),
            if (!(_previewReady && _previewCh?.key == c.key)) Center(child: IptvLogo(channel: c, size: 60)),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: CtColors.red, borderRadius: BorderRadius.circular(4)),
                child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Text('${c.number}. ${c.name}', maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleLarge),
      const SizedBox(height: 4),
      Text(
          [
            if (c.group.isNotEmpty) c.group,
            if (c.streams.length > 1) 'варианты: ${c.streams.map((e) => e.quality.isEmpty ? 'обычный' : e.quality).join(' · ')}',
            if (s.quality.isNotEmpty) 'сейчас: ${s.quality}',
            if (c.hasArchive) 'архив ${c.catchupDays} дн.',
          ].join('  ·  '),
          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
      ..._previewEpg(c, colors, text),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _TopButton(
            icon: Icons.view_list_outlined,
            label: c.hasArchive ? 'Программа и архив' : 'Программа',
            onPressed: () {
              _stopPreview();
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => IptvProgrammeScreen(
                      channel: c, channels: list, index: list.indexOf(c), all: _data?.channels ?? list)));
            }),
        _TopButton(
            icon: _store.favorites.value.contains(c.key) ? Icons.star : Icons.star_border,
            label: _store.favorites.value.contains(c.key) ? 'В избранном' : 'В избранное',
            onPressed: () async {
              await _store.toggleFavorite(c.key);
              if (mounted) setState(() {});
            }),
        if (c.streams.length > 1)
          _TopButton(icon: Icons.hd_outlined, label: 'Качество', onPressed: () => _channelMenu(c)),
      ]),
      const SizedBox(height: 10),
      Text('ОК — смотреть · МЕНЮ — избранное и качество · цифры — канал по номеру',
          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
    ]));
  }
}

/// Название канала, под ним — текущая передача и полоска прогресса.
Widget _nameAndNow(IptvChannel c, ColorScheme colors) {
  final cur = IptvEpg.I.current(c.key);
  final name = Text(c.name,
      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600));
  if (cur == null) return Align(alignment: Alignment.centerLeft, child: name);
  final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
    name,
    Text(cur.title,
        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
    const SizedBox(height: 3),
    ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
          value: cur.progress(nowSec), minHeight: 2.5, color: CtColors.red, backgroundColor: colors.outlineVariant),
    ),
  ]);
}

class _TopButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _TopButton({required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TvButton(
      borderRadius: 20,
      onPressed: (_) => onPressed(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 20), const SizedBox(width: 6), Text(label)]),
      ),
    );
  }
}

/// Настройки IPTV.
class IptvSettingsScreen extends StatefulWidget {
  const IptvSettingsScreen({super.key});

  @override
  State<IptvSettingsScreen> createState() => _IptvSettingsScreenState();
}

class _IptvSettingsScreenState extends State<IptvSettingsScreen> {
  IptvSettings get s => IptvStore.I.settings.value;

  Future<void> _set(IptvSettings v) async {
    await IptvStore.I.setSettings(v);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget sw(String title, String sub, bool value, ValueChanged<bool> on, {bool autofocus = false}) => SwitchListTile(
        autofocus: autofocus, title: Text(title), subtitle: Text(sub), value: value, onChanged: on);
    return Scaffold(
      body: TvOverscan(
        child: ListView(children: [
          Text('Настройки IPTV', style: text.headlineSmall),
          const SizedBox(height: 12),
          ListTile(
            autofocus: true,
            title: Text('Качество по умолчанию: ${switch (s.quality) { 1 => 'совместимое', 2 => 'максимальное', _ => 'авто' }}'),
            subtitle: Text(switch (s.quality) {
              1 => 'HD со звуком AAC — играет на любой приставке',
              2 => 'FHD/4K всегда: звук MP2 декодируют не все устройства',
              _ => 'По декодерам приставки: ${CtMediaCaps.I.mp2 ? 'MP2 есть — FHD' : 'MP2 нет — HD'}'
                  '${CtMediaCaps.I.avc4k ? ', 4K H.264 тянет — 4K' : ''}',
            }),
            onTap: () => _set(s.copyWith(quality: (s.quality + 1) % 3)),
          ),
          sw('Объединять варианты канала', 'HD / FHD / 4K одного канала — одной строкой, качество выбирается в меню',
              s.merge, (v) => _set(s.copyWith(merge: v))),
          sw('Показывать 4K', 'На слабых приставках 4K в H.264 может идти рывками', s.show4k,
              (v) => _set(s.copyWith(show4k: v))),
          sw('Открывать последний канал', 'При входе в «ТВ-каналы» сразу включать канал, который смотрели',
              s.resumeLast, (v) => _set(s.copyWith(resumeLast: v))),
          sw('Частота экрана под видео', 'На время просмотра 50 Гц для эфира (25/50 кадров) — без рывков; после — как было',
              CtPrefs.afr.value, (v) async {
            await CtPrefs.afr.set(v);
            if (mounted) setState(() {});
          }),
          ListTile(
            title: const Text('Обновлять плейлист'),
            subtitle: Text('Если старше ${s.refreshHours} ч — при входе в раздел'),
            onTap: () => _set(s.copyWith(refreshHours: switch (s.refreshHours) { 6 => 12, 12 => 24, 24 => 72, _ => 6 })),
          ),
        ]),
      ),
    );
  }
}
