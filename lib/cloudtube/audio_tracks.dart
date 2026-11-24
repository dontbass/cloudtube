import 'prefs.dart';

/// Звуковые дорожки ролика (оригинал и дубляжи, в том числе автоматические).
///
/// У части роликов YouTube отдаёт несколько дорожек: оригинальную и «автодубляж» (чаще всего
/// английский) — и иногда помечает дубляж дорожкой по умолчанию. Плеер раньше брал первую
/// попавшуюся (или ту, что YouTube назвал основной), и вместо оригинала звучал дубляж.
/// Теперь по умолчанию — оригинал; в меню плеера «Звук» можно выбрать другую, выбор языка
/// запоминается для следующих роликов.
class CtAudioTrack {
  /// id дорожки YouTube («en-US.4»), у HLS — YT-EXT-AUDIO-CONTENT-ID (или NAME).
  final String id;
  final String name;
  final String lang;
  final bool original;
  final bool autoDub;
  final bool isDefault;

  const CtAudioTrack(this.id, this.name, this.lang,
      {this.original = false, this.autoDub = false, this.isDefault = false});

  /// Подпись для меню: «Испанский — оригинал», «Английский (автодубляж)».
  String get label {
    final n = name.isNotEmpty ? name : (lang.isNotEmpty ? lang : id);
    final low = n.toLowerCase();
    if (original && !low.contains('оригинал') && !low.contains('original')) return '$n — оригинал';
    if (autoDub && !low.contains('авто') && !low.contains('auto')) return '$n (автодубляж)';
    return n;
  }

  /// Основной язык дорожки: «en-US» → «en».
  String get baseLang => lang.split(RegExp('[-_]')).first.toLowerCase();

  static bool _isOriginal(String xtags, String name) =>
      xtags.contains('acont=original') || RegExp('original|оригинал', caseSensitive: false).hasMatch(name);

  static bool _isAutoDub(String xtags, String name) =>
      xtags.contains('dubbed-auto') || RegExp(r'auto[- ]?dub|автодубл|автоматическ', caseSensitive: false).hasMatch(name);

  static String _xtagLang(String xtags) => RegExp(r'lang=([A-Za-z_-]+)').firstMatch(xtags)?.group(1) ?? '';
}

class CtAudio {
  static final _tracks = <String, List<CtAudioTrack>>{};
  static final _chosen = <String, String>{};

  /// Дорожки ролика (пусто или одна — выбирать нечего).
  static List<CtAudioTrack> tracks(String videoId) => _tracks[videoId] ?? const [];

  /// Ролики, у которых дорожки известны только из HLS: свой DASH (клиент VISIONOS) отдал одну
  /// дорожку, а в HLS-мастере (клиент iOS) их несколько — например, есть автодубляж.
  static final _hlsOnly = <String>{};

  static void _remember(String videoId, List<CtAudioTrack> t, {required bool hls}) {
    if (t.length < 2) {
      // DASH с одной дорожкой не затирает список, найденный в HLS, — иначе пропадал автодубляж
      if (!hls && _hlsOnly.contains(videoId)) return;
      _tracks[videoId] = const [];
      _hlsOnly.remove(videoId);
    } else {
      _tracks[videoId] = t;
      if (hls) {
        _hlsOnly.add(videoId);
      } else {
        _hlsOnly.remove(videoId);
      }
    }
    if (_tracks.length > 40) {
      final old = _tracks.keys.first;
      _tracks.remove(old);
      _hlsOnly.remove(old);
    }
  }

  /// Выбранная дорожка есть только в HLS — свой DASH её не сыграет, играть HLS.
  static bool needsHls(String videoId) {
    if (!_hlsOnly.contains(videoId)) return false;
    final p = pick(videoId, tracks(videoId));
    return p != null && !p.original;
  }

  /// В прошлый раз выбрали не оригинал (язык дубляжа) — для нового ролика стоит заранее
  /// посмотреть дорожки в HLS.
  static bool get prefersDub {
    final pref = CtPrefs.audioLang.value;
    return pref.isNotEmpty && pref != 'original';
  }

  /// Выбрать дорожку в меню: для этого ролика — она, для следующих — её язык
  /// (или «оригинал», если выбрали оригинал).
  static Future<void> choose(String videoId, CtAudioTrack t) async {
    _chosen[videoId] = t.id;
    await CtPrefs.audioLang.set(t.original ? 'original' : t.baseLang);
  }

  /// Какая дорожка будет играть: выбранная для ролика → предпочитаемый язык → оригинал →
  /// та, что YouTube назвал основной, но не автодубляж → первая.
  static CtAudioTrack? pick(String videoId, List<CtAudioTrack> t) {
    if (t.isEmpty) return null;
    final chosen = _chosen[videoId];
    if (chosen != null) {
      final c = t.where((x) => x.id == chosen).firstOrNull;
      if (c != null) return c;
    }
    final pref = CtPrefs.audioLang.value;
    if (pref.isNotEmpty && pref != 'original') {
      final byLang = t.where((x) => x.baseLang == pref).toList()
        ..sort((a, b) => (a.autoDub ? 1 : 0).compareTo(b.autoDub ? 1 : 0)); // настоящий дубляж — раньше авто
      if (byLang.isNotEmpty) {
        // язык совпал с оригиналом — оригинал
        return byLang.where((x) => x.original).firstOrNull ?? byLang.first;
      }
    }
    return t.where((x) => x.original).firstOrNull ??
        t.where((x) => x.isDefault && !x.autoDub).firstOrNull ??
        t.where((x) => !x.autoDub).firstOrNull ??
        t.first;
  }

  static String? pickedId(String videoId) => pick(videoId, tracks(videoId))?.id;

  // ---------- адаптивные форматы (свой DASH) ----------

  /// id дорожки адаптивного формата (сырой формат YouTube) или null — у ролика одна дорожка.
  static String? formatTrackId(Map f) {
    final at = f['audioTrack'];
    return at is Map && at['id'] is String ? at['id'] as String : null;
  }

  static String _xtags(Map f) {
    final u = f['url'];
    if (u is! String) return '';
    try {
      return Uri.decodeComponent(Uri.parse(u).queryParameters['xtags'] ?? '');
    } catch (_) {
      return '';
    }
  }

  /// Дорожки по сырым адаптивным форматам; запоминает их для меню.
  static List<CtAudioTrack> fromFormats(String videoId, List formats) {
    final out = <String, CtAudioTrack>{};
    for (final f in formats.whereType<Map>()) {
      if (!'${f['mimeType']}'.startsWith('audio/')) continue;
      final id = formatTrackId(f);
      if (id == null || out.containsKey(id)) continue;
      final at = f['audioTrack'] is Map ? f['audioTrack'] as Map : const {};
      final xt = _xtags(f);
      final name = '${at['displayName'] ?? ''}';
      final lang = CtAudioTrack._xtagLang(xt).isNotEmpty ? CtAudioTrack._xtagLang(xt) : id.split('.').first;
      out[id] = CtAudioTrack(id, name, lang,
          original: CtAudioTrack._isOriginal(xt, name),
          autoDub: CtAudioTrack._isAutoDub(xt, name),
          isDefault: at['audioIsDefault'] == true || at['isDefault'] == true);
    }
    final list = out.values.toList();
    _remember(videoId, list, hls: false);
    return list;
  }

  /// Сколько звуковых дорожек в сырых адаптивных форматах (без запоминания).
  static int formatTrackCount(List formats) => {
        for (final f in formats.whereType<Map>())
          if ('${f['mimeType']}'.startsWith('audio/')) formatTrackId(f) ?? ''
      }.length;

  /// Оставить звуковые форматы только выбранной дорожки (если дорожек несколько).
  static List<Map> filterFormats(String videoId, List<Map> audios) {
    final t = fromFormats(videoId, audios);
    if (t.length < 2) return audios;
    final p = pick(videoId, t);
    if (p == null) return audios;
    final kept = audios.where((f) => formatTrackId(f) == p.id).toList();
    return kept.isEmpty ? audios : kept;
  }

  // ---------- HLS ----------

  static String _attr(String line, String name) =>
      RegExp('$name="([^"]*)"').firstMatch(line)?.group(1) ??
      RegExp('$name=([^,]*)').firstMatch(line)?.group(1) ??
      '';

  static bool _isAudioMedia(String l) => l.startsWith('#EXT-X-MEDIA') && l.contains('TYPE=AUDIO');

  static String _hlsId(String l) {
    final id = _attr(l, 'YT-EXT-AUDIO-CONTENT-ID');
    return id.isNotEmpty ? id : _attr(l, 'NAME');
  }

  /// Дорожки из мастер-плейлиста HLS; запоминает их для меню.
  static List<CtAudioTrack> fromHls(String videoId, String master) {
    final out = <String, CtAudioTrack>{};
    for (final l in master.split('\n')) {
      if (!_isAudioMedia(l)) continue;
      final id = _hlsId(l);
      if (id.isEmpty || out.containsKey(id)) continue;
      final xt = _attr(l, 'YT-EXT-XTAGS');
      final name = _attr(l, 'NAME');
      out[id] = CtAudioTrack(id, name, _attr(l, 'LANGUAGE'),
          original: CtAudioTrack._isOriginal(xt, name),
          autoDub: CtAudioTrack._isAutoDub(xt, name),
          isDefault: _attr(l, 'DEFAULT') == 'YES');
    }
    final list = out.values.toList();
    _remember(videoId, list, hls: true);
    return list;
  }

  /// Мастер-плейлист только с выбранной звуковой дорожкой (варианты, которые ссылались на
  /// группы без неё, убираются). Одна дорожка — плейлист без изменений.
  static String filterHls(String videoId, String master) {
    final t = fromHls(videoId, master);
    if (t.length < 2) return master;
    final p = pick(videoId, t);
    if (p == null) return master;
    final lines = master.split('\n');
    final groups = <String>{};
    for (final l in lines) {
      if (_isAudioMedia(l) && _hlsId(l) == p.id) groups.add(_attr(l, 'GROUP-ID'));
    }
    if (groups.isEmpty) return master;
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (_isAudioMedia(l)) {
        if (_hlsId(l) != p.id) continue;
        out.add(l
            .replaceAll(RegExp(r'DEFAULT=(YES|NO)'), 'DEFAULT=YES')
            .replaceAll(RegExp(r'AUTOSELECT=(YES|NO)'), 'AUTOSELECT=YES'));
        continue;
      }
      if (l.startsWith('#EXT-X-STREAM-INF')) {
        final g = _attr(l, 'AUDIO');
        if (g.isNotEmpty && !groups.contains(g)) {
          i++; // и адрес варианта
          continue;
        }
      }
      out.add(l);
    }
    return out.join('\n');
  }
}
