import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../globals.dart';
import '../router.dart';
import '../utils/models/paginated_list.dart';
import '../utils/views/tv/components/tv_button.dart';
import '../videos/models/video.dart';
import 'avatars.dart';
import 'theme.dart';
import 'tv_channels.dart';
import 'tv_nav.dart';

/// «Подписки»: плитки каналов над лентой (телефон, ПК, ТВ).
/// Плитка «Все» — общая лента; плитка канала — последние ролики этого канала там же.

/// Канал в полосе: сколько новых роликов (за 3 дня, ещё не смотрели) и когда был последний.
class CtSubChannel {
  final String id;
  final String name;
  final int fresh;
  final int latest;

  const CtSubChannel(this.id, this.name, this.fresh, this.latest);
}

const _freshWindow = Duration(days: 3);

/// Порядок как в YouTube: сначала каналы со свежими роликами (по времени последнего),
/// остальные — по алфавиту. Счётчики берутся из уже загруженной ленты, без лишних запросов.
List<CtSubChannel> ctRankSubChannels(List<(String, String)> subs, List<Video> feed) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final since = now - _freshWindow.inSeconds;
  final fresh = <String, int>{};
  final latest = <String, int>{};
  final names = <String, String>{};
  for (final v in feed) {
    final id = v.authorId;
    final p = v.published;
    if (id == null || id.isEmpty) continue;
    // это лента подписок: автор ролика — подписка, даже если списка каналов не пришло
    if ((v.author ?? '').isNotEmpty) names.putIfAbsent(id, () => v.author!);
    if (p == null || p <= 0) continue;
    if (p > (latest[id] ?? 0)) latest[id] = p;
    if (p >= since && db.getVideoProgress(v.videoId) <= 0) fresh[id] = (fresh[id] ?? 0) + 1;
  }
  final known = {for (final (id, _) in subs) id};
  final out = [
    for (final (id, name) in subs) CtSubChannel(id, name, fresh[id] ?? 0, latest[id] ?? 0),
    for (final e in names.entries)
      if (!known.contains(e.key)) CtSubChannel(e.key, e.value, fresh[e.key] ?? 0, latest[e.key] ?? 0),
  ];
  out.sort((a, b) {
    final f = (b.fresh > 0 ? 1 : 0).compareTo(a.fresh > 0 ? 1 : 0);
    if (f != 0) return f;
    if (a.fresh > 0) return b.latest.compareTo(a.latest);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return out;
}

/// Обёртка ленты: отдаёт ролики как есть и складывает загруженное в [feed] — для счётчиков на плитках.
class CtFeedTap extends PaginatedVideoList {
  final PaginatedVideoList inner;
  final ValueNotifier<List<Video>> feed;

  /// Лента загружена с начала (первый раз или «потянуть вниз») — повод обновить и список каналов.
  final VoidCallback? onReload;

  CtFeedTap(this.inner, this.feed, {this.onReload});

  @override
  Future<List<Video>> getItems() async {
    onReload?.call();
    return feed.value = await inner.getItems();
  }

  @override
  Future<List<Video>> refresh() async {
    onReload?.call();
    return feed.value = await inner.refresh();
  }

  @override
  Future<List<Video>> getMoreItems() async {
    final more = await inner.getMoreItems();
    feed.value = [...feed.value, ...more];
    return more;
  }

  @override
  bool hasRefresh() => inner.hasRefresh();

  @override
  bool getHasMore() => inner.getHasMore();
}

/// Последние ролики одного канала.
PaginatedVideoList ctChannelLatest(String channelId) => _ChannelLatest(channelId);

class _ChannelLatest extends PaginatedVideoList {
  final ContinuationList<Video> _list;
  _ChannelLatest(String id) : _list = ContinuationList<Video>((c) => service.getChannelVideos(id, c));

  @override
  Future<List<Video>> getItems() => _list.getItems();
  @override
  Future<List<Video>> getMoreItems() => _list.getMoreItems();
  @override
  Future<List<Video>> refresh() => _list.refresh();
  @override
  bool hasRefresh() => true;
  @override
  bool getHasMore() => _list.getHasMore();
}

/// Счётчик новых роликов в углу плитки.
class _FreshBadge extends StatelessWidget {
  final int count;
  final double size;
  const _FreshBadge(this.count, {this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: size),
      height: size,
      padding: EdgeInsets.symmetric(horizontal: size * 0.28),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CtColors.red,
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
      ),
      child: Text(count > 9 ? '9+' : '$count',
          style: TextStyle(color: Colors.white, fontSize: size * 0.58, fontWeight: FontWeight.w700, height: 1)),
    );
  }
}

/// Полоса плиток на телефоне и ПК.
class CtSubStrip extends StatelessWidget {
  final List<CtSubChannel> channels;
  final String? selected;
  final ValueChanged<String?> onSelect;

  /// Компактный вид (невысокий экран): «таблетки» высотой 52 — аватар слева, название справа.
  final bool compact;

  const CtSubStrip(
      {super.key, required this.channels, required this.selected, required this.onSelect, this.compact = false});

  static const _w = 84.0, _h = 108.0;

  /// Контрастный цвет текста на выбранной (светлой/тёмной) плитке — не colors.surface:
  /// в «Стекле» он давал бледную подпись «Все».
  static Color _onSelected(ColorScheme c) =>
      c.onSurface.computeLuminance() > 0.5 ? const Color(0xFF111111) : Colors.white;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (compact) return _ctCompactStrip(this, context, colors);
    Widget tile({required bool on, required VoidCallback onTap, required Widget top, required String label, int fresh = 0}) {
      return Semantics(
        button: true,
        selected: on,
        label: label,
        child: Material(
          color: on ? colors.onSurface : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: _w,
              height: _h,
              child: Stack(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
                  child: Column(children: [
                    top,
                    const SizedBox(height: 8),
                    Text(label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.2,
                            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                            color: on ? _onSelected(colors) : colors.onSurface)),
                  ]),
                ),
                if (fresh > 0) Positioned(top: 6, right: 6, child: _FreshBadge(fresh)),
              ]),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: _h + 16,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        itemCount: channels.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == 0) {
            final on = selected == null;
            return tile(
                on: on,
                onTap: () => onSelect(null),
                top: SizedBox(
                    height: 48,
                    child: Icon(Icons.grid_view_rounded, size: 28, color: on ? _onSelected(colors) : colors.onSurface)),
                label: 'Все');
          }
          final c = channels[i - 1];
          return tile(
              on: selected == c.id,
              onTap: () => onSelect(selected == c.id ? null : c.id),
              top: CtChannelAvatar(channelId: c.id, author: c.name, size: 48),
              label: c.name,
              fresh: c.fresh);
        },
      ),
    );
  }
}

Widget _ctCompactStrip(CtSubStrip w, BuildContext context, ColorScheme colors) {
  final channels = w.channels, selected = w.selected, onSelect = w.onSelect;
  {
    Widget pill({required bool on, required VoidCallback onTap, required Widget lead, required String label,
        int fresh = 0, double? width}) {
      final fg = on ? CtSubStrip._onSelected(colors) : colors.onSurface;
      return Semantics(
        button: true,
        selected: on,
        label: label,
        child: Material(
          color: on ? colors.onSurface : colors.surfaceContainerHigh,
          shape: StadiumBorder(side: on ? BorderSide.none : BorderSide(color: colors.outlineVariant, width: 0.6)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 52,
              width: width,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Stack(clipBehavior: Clip.none, children: [
                    lead,
                    if (fresh > 0) Positioned(top: -4, right: -6, child: _FreshBadge(fresh)),
                  ]),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            height: 1.2,
                            color: fg,
                            fontWeight: on ? FontWeight.w600 : FontWeight.w500)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: channels.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == 0) {
            final on = selected == null;
            return pill(
                on: on,
                onTap: () => onSelect(null),
                lead: Icon(Icons.grid_view_rounded, size: 22, color: on ? CtSubStrip._onSelected(colors) : colors.onSurface),
                label: 'Все');
          }
          final c = channels[i - 1];
          return pill(
              on: selected == c.id,
              onTap: () => onSelect(selected == c.id ? null : c.id),
              lead: CtChannelAvatar(channelId: c.id, author: c.name, size: 36),
              label: c.name,
              fresh: c.fresh,
              width: 152);
        },
      ),
    );
  }
}

/// Строка над роликами выбранного канала: имя, сколько новых, «На канал».
class CtSubChannelHeader extends StatelessWidget {
  final CtSubChannel channel;
  const CtSubChannelHeader({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
            Text(channel.fresh > 0 ? '${channel.fresh} новых · последние ролики' : 'Последние ролики',
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          ]),
        ),
        FilledButton.tonal(
          onPressed: () => AutoRouter.of(context).push(ChannelRoute(channelId: channel.id)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Text('На канал'),
            SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 18),
          ]),
        ),
      ]),
    );
  }
}

/// Ряд плиток на ТВ — тот же вид, крупнее: «Все» + каналы; ОК — ролики канала в сетке ниже.
class CtTvSubStrip extends StatelessWidget {
  final List<CtSubChannel> channels;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const CtTvSubStrip({super.key, required this.channels, required this.selected, required this.onSelect});

  static const _w = 128.0, _h = 150.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget tile(
        {required bool on, required VoidCallback onTap, required Widget top, required String label, int fresh = 0}) {
      return TvButton(
        borderRadius: 20,
        unfocusedColor: on ? colors.onSurface.withValues(alpha: 0.22) : colors.surfaceContainerHigh,
        onPressed: (_) => onTap(),
        child: SizedBox(
          width: _w,
          height: _h,
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
              child: Column(children: [
                top,
                const SizedBox(height: 10),
                Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.2, fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
              ]),
            ),
            if (on)
              Positioned(
                  left: 0,
                  right: 0,
                  bottom: 6,
                  child: Center(
                      child: Container(
                          width: 26,
                          height: 3,
                          decoration:
                              BoxDecoration(color: ctAccent(colors), borderRadius: BorderRadius.circular(2))))),
            if (fresh > 0) Positioned(top: 8, right: 8, child: _FreshBadge(fresh, size: 22)),
          ]),
        ),
      );
    }

    return SizedBox(
      height: _h + 16,
      child: CtTvSmoothTraversal(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          itemCount: channels.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            if (i == 0) {
              return tile(
                  on: selected == null,
                  onTap: () => onSelect(null),
                  top: const SizedBox(height: 72, child: Icon(Icons.grid_view_rounded, size: 40)),
                  label: 'Все');
            }
            final c = channels[i - 1];
            return tile(
                on: selected == c.id,
                onTap: () => onSelect(c.id),
                top: CtChannelAvatar(channelId: c.id, author: c.name, size: 72, slow: true),
                label: c.name,
                fresh: c.fresh);
          },
        ),
      ),
    );
  }
}

/// «На канал» для ТВ-заголовка.
Widget ctTvOpenChannelChip(String channelId) => Builder(
    builder: (context) => CtTvChip(
        icon: const Icon(Icons.chevron_right_rounded),
        label: 'На канал',
        onPressed: (ctx) => ctOpenTvChannel(ctx, channelId)));
