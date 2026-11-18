import '../../videos/models/sponsor_segment_types.dart';

/// Фрагмент SponsorBlock: [start, end) в миллисекундах.
class CtSponsorSeg {
  final int startMs;
  final int endMs;
  final SponsorSegmentType type;

  const CtSponsorSeg(this.startMs, this.endMs, this.type);

  @override
  String toString() => '$type ${startMs}ms–${endMs}ms';
}

/// Решение «перемотать»: куда и надо ли показать сообщение.
class CtSponsorSkip {
  final Duration to;
  final CtSponsorSeg seg;

  /// false — этот фрагмент уже объявляли (перемотка не успела сработать с прошлого раза).
  final bool announce;

  const CtSponsorSkip(this.to, this.seg, this.announce);
}

/// Правила пропуска SponsorBlock — общие для плеера Android/ТВ и Windows (mpv).
/// Плеер сообщает позицию — пропускатель говорит, нужно ли перемотать и куда.
class CtSponsorSkipper {
  /// Не пропускаем в последние 5 с ролика: иначе фрагмент-концовка перематывает «в никуда» по кругу.
  static const tailGuard = Duration(seconds: 5);

  /// Хвост фрагмента, где уже не перематываем (позиция после перемотки чуть не доходит до конца).
  static const endSlack = Duration(milliseconds: 400);

  /// Перематываем чуть дальше конца фрагмента — чтобы не попасть обратно в него.
  static const pastEnd = Duration(milliseconds: 250);

  List<CtSponsorSeg> _segs = const [];
  int? _lastStart;
  DateTime _lastAt = DateTime(2000);

  List<CtSponsorSeg> get segments => _segs;

  void setSegments(List<CtSponsorSeg> segs) {
    _segs = [...segs]..sort((a, b) => a.startMs.compareTo(b.startMs));
    _lastStart = null;
  }

  void clear() => setSegments(const []);

  CtSponsorSkip? check(Duration position, Duration total, {DateTime? now}) {
    if (_segs.isEmpty) return null;
    if (total > Duration.zero && position > total - tailGuard) return null;
    final p = position.inMilliseconds;
    for (final s in _segs) {
      if (s.endMs <= s.startMs) continue; // точка («главное»), не отрезок
      if (p >= s.startMs && p < s.endMs - endSlack.inMilliseconds) {
        var to = Duration(milliseconds: s.endMs) + pastEnd;
        // фрагмент до самого конца — встаём на последнюю секунду, ролик завершится сам
        if (total > Duration.zero && to >= total) to = total - const Duration(seconds: 1);
        final t = now ?? DateTime.now();
        final announce = _lastStart != s.startMs || t.difference(_lastAt) > const Duration(seconds: 15);
        _lastStart = s.startMs;
        _lastAt = t;
        return CtSponsorSkip(to, s, announce);
      }
    }
    return null;
  }

  /// Разбор ответа api/skipSegments. Неизвестные категории и действия кроме «skip»
  /// пропускаем по одной — раньше одна незнакомая категория роняла весь список.
  static List<CtSponsorSeg> parse(List<dynamic> json) {
    final out = <CtSponsorSeg>[];
    for (final e in json) {
      if (e is! Map) continue;
      final action = e['actionType'];
      if (action != null && action != 'skip') continue;
      final cat = SponsorSegmentType.values.where((t) => t.segmentName == e['category']).firstOrNull;
      final seg = e['segment'];
      if (cat == null || seg is! List || seg.length < 2) continue;
      final a = seg[0], b = seg[1];
      if (a is! num || b is! num) continue;
      out.add(CtSponsorSeg((a * 1000).round(), (b * 1000).round(), cat));
    }
    return out;
  }
}
