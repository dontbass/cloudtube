import 'package:flutter/material.dart';

import '../cloudtube/theme.dart';
import '../utils/views/tv/components/tv_button.dart';
import '../utils/views/tv/components/tv_overscan.dart';
import 'epg.dart';
import 'm3u.dart';
import 'player.dart';
import 'store.dart';

const _days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const _months = ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];

/// Программа канала по дням; прошедшие передачи в пределах архива — смотреть с начала,
/// текущая — прямой эфир.
class IptvProgrammeScreen extends StatefulWidget {
  final IptvChannel channel;
  final List<IptvChannel> channels;
  final int index;
  final List<IptvChannel> all;

  const IptvProgrammeScreen(
      {super.key, required this.channel, required this.channels, required this.index, required this.all});

  @override
  State<IptvProgrammeScreen> createState() => _IptvProgrammeScreenState();
}

class _IptvProgrammeScreenState extends State<IptvProgrammeScreen> {
  List<EpgProg>? _progs;
  DateTime? _day;

  @override
  void initState() {
    super.initState();
    final p = IptvStore.I.current;
    if (p == null) {
      _progs = const [];
    } else {
      IptvEpg.I.full(p, widget.channel).then((l) {
        if (!mounted) return;
        setState(() {
          _progs = l;
          final n = DateTime.now();
          _day = DateTime(n.year, n.month, n.day);
        });
      });
    }
  }

  static DateTime _d(DateTime t) => DateTime(t.year, t.month, t.day);

  String _dayLabel(DateTime d) {
    final today = _d(DateTime.now());
    final diff = d.difference(today).inDays;
    if (diff == 0) return 'Сегодня';
    if (diff == -1) return 'Вчера';
    if (diff == 1) return 'Завтра';
    return '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
  }

  void _play(EpgProg p) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final live = p.isNow(now);
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => IptvPlayerScreen(
            channels: widget.channels, index: widget.index, all: widget.all, archive: live ? null : p)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final c = widget.channel;
    final progs = _progs;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final days = progs == null ? <DateTime>[] : (progs.map((p) => _d(p.startTime)).toSet().toList()..sort());
    final day = _day;
    final list = progs == null || day == null ? <EpgProg>[] : progs.where((p) => _d(p.startTime) == day).toList();
    final archiveFrom = now - c.catchupDays * 86400;
    final curIndex = list.indexWhere((p) => p.isNow(now));
    return Scaffold(
      body: TvOverscan(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IptvLogo(channel: c, size: 36),
            const SizedBox(width: 12),
            Flexible(child: Text('${c.name} · программа', maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleLarge)),
            const SizedBox(width: 12),
            if (c.hasArchive)
              Text('архив ${c.catchupDays} дн.', style: text.titleSmall?.copyWith(color: colors.onSurfaceVariant)),
          ]),
          const SizedBox(height: 10),
          if (progs == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (progs.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                    'Телепрограммы для этого канала нет.\nЕсли провайдер даёт свою — укажите её ссылку в плейлисте (Плейлисты → Настройки).',
                    textAlign: TextAlign.center,
                    style: text.titleMedium?.copyWith(color: colors.onSurfaceVariant)),
              ),
            )
          else ...[
            SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final d in days)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TvButton(
                      borderRadius: 20,
                      unfocusedColor: d == day ? colors.secondaryContainer : Colors.transparent,
                      onFocusChanged: (f) {
                        if (f && d != day) setState(() => _day = d);
                      },
                      onPressed: (_) => setState(() => _day = d),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(_dayLabel(d), style: TextStyle(fontWeight: d == day ? FontWeight.w700 : FontWeight.w500)),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                key: ValueKey(day),
                controller: ScrollController(initialScrollOffset: curIndex > 3 ? (curIndex - 3) * 56.0 : 0),
                itemExtent: 56,
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final p = list[i];
                  final live = p.isNow(now);
                  final past = p.stop <= now;
                  final inArchive = past && c.hasArchive && p.start >= archiveFrom;
                  final playable = live || inArchive;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: TvButton(
                      autofocus: live || (curIndex < 0 && i == 0),
                      borderRadius: 12,
                      unfocusedColor: live ? ctAccent(colors).withValues(alpha: 0.14) : Colors.transparent,
                      onPressed: playable ? (_) => _play(p) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        child: Row(children: [
                          SizedBox(
                            width: 56,
                            child: Text(epgHm(p.startTime),
                                style: TextStyle(fontSize: 16, color: past ? colors.onSurfaceVariant : colors.onSurface)),
                          ),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text(p.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 16, fontWeight: live ? FontWeight.w700 : FontWeight.w500)),
                              if (p.desc.isNotEmpty)
                                Text(p.desc,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                            ]),
                          ),
                          const SizedBox(width: 10),
                          if (live)
                            Text('● в эфире', style: TextStyle(color: CtColors.red, fontWeight: FontWeight.w700))
                          else if (inArchive)
                            Text('↺ архив', style: TextStyle(color: colors.onSurfaceVariant, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
