import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:river_player/river_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../cloudtube/theme.dart';
import 'm3u.dart';
import 'store.dart';

final _log = Logger('IptvPlayer');

/// Вариант канала по настройкам: «совместимый» (HD со звуком AAC) или максимальный.
IptvStream iptvPickStream(IptvChannel c, IptvSettings s, {String? quality}) {
  if (quality != null) {
    final q = c.streams.where((x) => x.quality == quality).firstOrNull;
    if (q != null) return q;
  }
  final list = c.streams
      .where((x) => s.show4k || !RegExp('uhd|4k|8k', caseSensitive: false).hasMatch(x.quality))
      .toList();
  final pool = list.isEmpty ? c.streams : list;
  final sorted = [...pool]
    ..sort((a, b) => qualityRank(a.quality, preferMax: s.preferMax).compareTo(qualityRank(b.quality, preferMax: s.preferMax)));
  return sorted.first;
}

final _formatCache = <String, BetterPlayerVideoFormat>{};

/// Формат потока: по расширению, иначе — по первым байтам ответа (ссылки без «.m3u8»).
Future<BetterPlayerVideoFormat> iptvFormat(String url, Map<String, String> headers) async {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  if (path.endsWith('.m3u8') || path.endsWith('.m3u')) return BetterPlayerVideoFormat.hls;
  if (path.endsWith('.mpd')) return BetterPlayerVideoFormat.dash;
  if (path.endsWith('.ts') || path.endsWith('.mp4') || path.endsWith('.mkv')) return BetterPlayerVideoFormat.other;
  final cached = _formatCache[url];
  if (cached != null) return cached;
  var f = BetterPlayerVideoFormat.other;
  final client = http.Client();
  try {
    final req = http.Request('GET', Uri.parse(url))..headers.addAll({...headers, 'Range': 'bytes=0-511'});
    final res = await client.send(req).timeout(const Duration(seconds: 4));
    final ct = (res.headers['content-type'] ?? '').toLowerCase();
    final head = await res.stream.take(1).fold<List<int>>([], (a, b) => a..addAll(b)).timeout(const Duration(seconds: 4));
    final s = String.fromCharCodes(head.take(64));
    if (ct.contains('mpegurl') || s.startsWith('#EXTM3U')) {
      f = BetterPlayerVideoFormat.hls;
    } else if (ct.contains('dash') || s.contains('<MPD')) {
      f = BetterPlayerVideoFormat.dash;
    }
  } catch (e) {
    _log.fine('format sniff $url: $e');
  } finally {
    client.close();
  }
  _formatCache[url] = f;
  return f;
}

Map<String, String> iptvHeaders(IptvChannel c) {
  final pl = IptvStore.I.current;
  return {
    if (pl != null && pl.userAgent.isNotEmpty) 'User-Agent': pl.userAgent,
    ...c.headers,
  };
}

/// Источник для плеера (общий для превью и полноэкранного плеера).
Future<BetterPlayerDataSource> iptvSource(IptvChannel c, IptvStream s) async {
  final h = iptvHeaders(c);
  final f = await iptvFormat(s.url, h);
  return BetterPlayerDataSource(
    BetterPlayerDataSourceType.network,
    s.url,
    headers: h,
    videoFormat: f,
    liveStream: true,
    bufferingConfiguration: const BetterPlayerBufferingConfiguration(
      minBufferMs: 3000,
      maxBufferMs: 30000,
      bufferForPlaybackMs: 1000,
      bufferForPlaybackAfterRebufferMs: 2500,
    ),
  );
}

BetterPlayerController iptvController({bool preview = false}) => BetterPlayerController(
      BetterPlayerConfiguration(
        aspectRatio: 16 / 9,
        fit: BoxFit.contain,
        autoPlay: true,
        handleLifecycle: true,
        autoDispose: false,
        expandToFill: true,
        playerVisibilityChangedBehavior: (_) {},
        controlsConfiguration: const BetterPlayerControlsConfiguration(showControls: false),
        placeholder: const ColoredBox(color: Colors.black),
      ),
    );

/// Полноэкранный плеер IPTV: каналы ▲▼ / CH±, номер цифрами, «0» — предыдущий канал,
/// ОК — список каналов, ◀▶ / INFO — плашка канала, МЕНЮ — качество.
class IptvPlayerScreen extends StatefulWidget {
  final List<IptvChannel> channels;
  final int index;

  /// Все каналы плейлиста — для перехода по номеру.
  final List<IptvChannel> all;

  /// Вариант, выбранный в меню канала (иначе — по настройкам).
  final String? initialQuality;

  const IptvPlayerScreen(
      {super.key, required this.channels, required this.index, required this.all, this.initialQuality});

  @override
  State<IptvPlayerScreen> createState() => _IptvPlayerScreenState();
}

class _IptvPlayerScreenState extends State<IptvPlayerScreen> {
  late final BetterPlayerController _ctl = iptvController();
  late List<IptvChannel> _list = widget.channels;
  late int _i = widget.index;
  int? _prev;
  String? _quality;
  IptvStream? _stream;

  bool _osd = true;
  Timer? _osdTimer;
  String _digits = '';
  Timer? _digitTimer;
  bool _listOpen = false;
  String? _error;
  bool _loading = true;
  Timer? _watchdog;
  int _gen = 0;
  final _focus = FocusNode();

  IptvChannel get _ch => _list[_i];

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _ctl.addEventsListener(_onEvent);
    _quality = widget.initialQuality;
    _play(keepQuality: widget.initialQuality != null);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _osdTimer?.cancel();
    _digitTimer?.cancel();
    _watchdog?.cancel();
    _ctl.dispose(forceDispose: true);
    _focus.dispose();
    super.dispose();
  }

  void _onEvent(BetterPlayerEvent e) {
    if (!mounted) return;
    switch (e.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
      case BetterPlayerEventType.play:
        _watchdog?.cancel();
        if (_loading || _error != null) {
          setState(() {
            _loading = false;
            _error = null;
          });
        }
      case BetterPlayerEventType.exception:
        _fail('Канал не воспроизводится');
      default:
    }
  }

  void _fail(String msg) {
    _watchdog?.cancel();
    // есть другой вариант канала — пробуем его, прежде чем показать ошибку
    final others = _ch.streams.where((s) => s.url != _stream?.url).toList();
    if (others.isNotEmpty && _quality == null) {
      _log.info('${_ch.name}: ${_stream?.quality} не идёт, пробую ${others.first.quality}');
      _quality = others.first.quality;
      _play(keepQuality: true);
      return;
    }
    setState(() {
      _loading = false;
      _error = msg;
    });
  }

  Future<void> _play({bool keepQuality = false}) async {
    final gen = ++_gen;
    if (!keepQuality) _quality = null;
    final c = _ch;
    final s = iptvPickStream(c, IptvStore.I.settings.value, quality: _quality);
    setState(() {
      _stream = s;
      _loading = true;
      _error = null;
    });
    _showOsd();
    unawaited(IptvStore.I.markWatched(c.key));
    try {
      final src = await iptvSource(c, s);
      if (!mounted || gen != _gen) return;
      await _ctl.setupDataSource(src);
      // мёртвый канал: 12 с без картинки — сообщение вместо вечной крутилки
      _watchdog?.cancel();
      _watchdog = Timer(const Duration(seconds: 12), () {
        if (mounted && gen == _gen && _loading) _fail('Канал недоступен — нет данных от провайдера');
      });
    } catch (e) {
      if (mounted && gen == _gen) _fail('Канал не воспроизводится: $e');
    }
  }

  void _switchTo(int i) {
    if (i < 0 || i >= _list.length || i == _i) return;
    _prev = _i;
    _i = i;
    _play();
  }

  void _step(int d) {
    if (_list.isEmpty) return;
    _switchTo((_i + d) % _list.length); // по кругу: % в Dart неотрицателен
  }

  void _byNumber(int n) {
    final inList = _list.indexWhere((c) => c.number == n);
    if (inList >= 0) return _switchTo(inList);
    final c = widget.all.where((c) => c.number == n).firstOrNull;
    if (c == null) return;
    // канала нет в текущей группе — переключаемся на «Все»
    setState(() => _list = widget.all);
    _prev = null;
    _i = widget.all.indexOf(c);
    _play();
  }

  void _showOsd() {
    _osdTimer?.cancel();
    if (!_osd) setState(() => _osd = true);
    _osdTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _osd = false);
    });
  }

  void _digit(int d) {
    _digitTimer?.cancel();
    setState(() => _digits += '$d');
    _digitTimer = Timer(const Duration(milliseconds: 1500), () {
      final s = _digits;
      setState(() => _digits = '');
      if (s == '0') {
        // «0» — предыдущий канал
        final p = _prev;
        if (p != null) _switchTo(p);
      } else {
        _byNumber(int.parse(s));
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (_listOpen) return KeyEventResult.ignored;
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      if (e is KeyUpEvent && (e.logicalKey == LogicalKeyboardKey.select || e.logicalKey == LogicalKeyboardKey.enter)) {
        _openList();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelDown) {
      _step(-1);
    } else if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelUp) {
      _step(1);
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.info) {
      _showOsd();
    } else if (k == LogicalKeyboardKey.contextMenu || k == LogicalKeyboardKey.f1) {
      _pickQuality();
    } else if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter) {
      return KeyEventResult.handled; // откроется на отпускании
    } else {
      final ch = e.character;
      final d = ch == null ? null : int.tryParse(ch);
      if (d != null && ch!.length == 1) {
        _digit(d);
      } else {
        return KeyEventResult.ignored;
      }
    }
    return KeyEventResult.handled;
  }

  Future<void> _openList() async {
    setState(() => _listOpen = true);
    final i = await showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Каналы',
      barrierColor: Colors.black38,
      pageBuilder: (ctx, _, __) => _ChannelsOverlay(channels: _list, index: _i),
    );
    if (!mounted) return;
    setState(() => _listOpen = false);
    _focus.requestFocus();
    if (i != null) _switchTo(i);
  }

  Future<void> _pickQuality() async {
    if (_ch.streams.length < 2) return _showOsd();
    final q = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Качество'),
        children: [
          for (final s in _ch.streams)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s.quality),
              child: Text('${s.quality.isEmpty ? 'Обычное' : s.quality}${s.url == _stream?.url ? '  ✓' : ''}',
                  style: const TextStyle(fontSize: 18)),
            ),
        ],
      ),
    );
    _focus.requestFocus();
    if (q != null && q != _stream?.quality) {
      _quality = q;
      _play(keepQuality: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _ch;
    final text = Theme.of(context).textTheme;
    final fav = IptvStore.I.favorites.value.contains(c.key);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(fit: StackFit.expand, children: [
          BetterPlayer(controller: _ctl),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(16)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.portable_wifi_off, color: Colors.white70, size: 36),
                  const SizedBox(height: 8),
                  Text(_error!, style: text.titleMedium?.copyWith(color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('▲▼ — другой канал · ОК — список', style: text.bodyMedium?.copyWith(color: Colors.white70)),
                ]),
              ),
            ),
          if (_digits.isNotEmpty)
            Positioned(
              top: 30,
              right: 40,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                child: Text(_digits, style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w700)),
              ),
            ),
          AnimatedOpacity(
            opacity: _osd ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.fromLTRB(40, 0, 40, 26),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xDD15131C),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(children: [
                  IptvLogo(channel: c, size: 52),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        Text('${c.number}', style: text.titleMedium?.copyWith(color: Colors.white60)),
                        const SizedBox(width: 10),
                        Flexible(
                            child: Text(c.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700))),
                        if (fav) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.star, color: Colors.amber, size: 20)),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                          [
                            if (c.group.isNotEmpty) c.group,
                            if (c.hasArchive) 'архив ${c.catchupDays} дн.',
                          ].join(' · '),
                          style: text.bodyMedium?.copyWith(color: Colors.white70)),
                      const SizedBox(height: 4),
                      Text('▲▼ каналы · цифры — номер · 0 — предыдущий · ОК — список · МЕНЮ — качество',
                          style: text.bodySmall?.copyWith(color: Colors.white54)),
                    ]),
                  ),
                  if ((_stream?.quality ?? '').isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(8)),
                      child: Text(_stream!.quality, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Список каналов поверх видео (ОК в плеере).
class _ChannelsOverlay extends StatelessWidget {
  final List<IptvChannel> channels;
  final int index;
  const _ChannelsOverlay({required this.channels, required this.index});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: const Color(0xEE15131C),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
        child: SizedBox(
          width: 380,
          height: double.infinity,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
            itemCount: channels.length,
            controller: ScrollController(initialScrollOffset: (index * 56.0 - 200).clamp(0, double.infinity)),
            itemExtent: 56,
            itemBuilder: (ctx, i) {
              final c = channels[i];
              return InkWell(
                autofocus: i == index,
                borderRadius: BorderRadius.circular(12),
                focusColor: ctAccent(colors).withValues(alpha: 0.35),
                onTap: () => Navigator.of(ctx).pop(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(children: [
                    SizedBox(
                        width: 40,
                        child: Text('${c.number}', style: const TextStyle(color: Colors.white54, fontSize: 15))),
                    IptvLogo(channel: c, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white, fontSize: 16, fontWeight: i == index ? FontWeight.w700 : FontWeight.w400)),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Логотип канала: из плейлиста, иначе цветная плашка с буквами названия.
class IptvLogo extends StatelessWidget {
  final IptvChannel channel;
  final double size;
  const IptvLogo({super.key, required this.channel, this.size = 40});

  static const _palette = [
    Color(0xFF3D5A80), Color(0xFF9C2F2F), Color(0xFF2F6E4F), Color(0xFF6B4F9C),
    Color(0xFF7A6A3D), Color(0xFF3D6F80), Color(0xFF80503D), Color(0xFF2F7F7A),
  ];

  @override
  Widget build(BuildContext context) {
    final w = size * 4 / 3, h = size;
    final words = channel.name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final ini = words.isEmpty
        ? '?'
        : words.length == 1
            ? words.first.characters.take(2).toString()
            : '${words[0].characters.first}${words[1].characters.first}';
    final fallback = Container(
      width: w,
      height: h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: _palette[channel.name.hashCode.abs() % _palette.length], borderRadius: BorderRadius.circular(8)),
      child: Text(ini.toUpperCase(),
          style: TextStyle(color: Colors.white, fontSize: h * 0.36, fontWeight: FontWeight.w700)),
    );
    if (channel.logo.isEmpty) return fallback;
    return SizedBox(
      width: w,
      height: h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(channel.logo,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => fallback,
            frameBuilder: (ctx, child, frame, sync) => frame == null && !sync ? fallback : child),
      ),
    );
  }
}
