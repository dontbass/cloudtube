import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../globals.dart';
import 'direct.dart';
import 'trace.dart';
import 'yt_fast.dart';

/// Проверка скорости на устройстве: сколько занимает каждый шаг запуска видео.
/// Нужна, чтобы найти, где именно задержка у конкретного пользователя (сеть, VPN, внешние сервисы).
class CtSpeedTestScreen extends StatefulWidget {
  const CtSpeedTestScreen({super.key});

  @override
  State<CtSpeedTestScreen> createState() => _CtSpeedTestScreenState();
}

class _Step {
  final String name;
  int? ms;
  String note = '';
  bool ok = true;

  _Step(this.name);
}

class _CtSpeedTestScreenState extends State<CtSpeedTestScreen> {
  final steps = <_Step>[];
  bool running = false;
  final _vid = TextEditingController(text: 'dQw4w9WgXcQ');

  Future<T?> _run<T>(String name, Future<T> Function() f, [String Function(T)? note]) async {
    final s = _Step(name);
    setState(() => steps.add(s));
    final sw = Stopwatch()..start();
    try {
      final r = await f().timeout(const Duration(seconds: 20));
      s.ms = sw.elapsedMilliseconds;
      if (note != null && r != null) s.note = note(r);
      return r;
    } catch (e) {
      s.ms = sw.elapsedMilliseconds;
      s.ok = false;
      s.note = '$e'.split('\n').first;
      return null;
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _start() async {
    final id = _vid.text.trim();
    setState(() {
      steps.clear();
      running = true;
    });
    final c = http.Client();
    await _run('Доступ к youtube.com', () => c.head(Uri.parse('https://www.youtube.com/generate_204')), (r) => 'HTTP ${r.statusCode}');
    await _run('visitorData', () => CtYtFast.visitorData(), (r) => r == null ? 'нет' : 'есть');
    final ios = await _run('player iOS (HLS)', () => CtYtFast.player(id, yt.YoutubeApiClient.ios),
        (r) => r == null ? 'недоступно' : 'ok');
    await _run('player ANDROID_VR', () => CtYtFast.player(id, yt.YoutubeApiClient.androidVr),
        (r) => r == null ? 'недоступно' : 'ok');
    await _run('next (канал, рекомендации)', () => CtYtFast.next(id), (r) => 'ok');
    final master = (ios?['streamingData'] as Map?)?['hlsManifestUrl'] as String?;
    if (master != null) {
      final m = await _run('HLS мастер-плейлист', () => c.get(Uri.parse(master), headers: ctDirectStreamHeaders(master)),
          (r) => 'HTTP ${r.statusCode}');
      final variant = m?.body.split('\n').where((l) => l.startsWith('http')).firstOrNull;
      if (variant != null) {
        final v = await _run('HLS плейлист качества',
            () => c.get(Uri.parse(variant), headers: ctDirectStreamHeaders(variant)), (r) => 'HTTP ${r.statusCode}');
        final seg = v?.body.split('\n').where((l) => l.startsWith('http')).firstOrNull;
        if (seg != null) {
          await _run('первый сегмент видео',
              () => c.get(Uri.parse(seg), headers: ctDirectStreamHeaders(seg)),
              (r) => 'HTTP ${r.statusCode}, ${(r.bodyBytes.length / 1024).round()} КБ');
        }
      }
    }
    ctDirectClearCache();
    await _run('Данные видео без обработки', () async {
      final r = await service.httpClient.get(Uri.parse('$kCtDirectUrl/api/v1/videos/$id'));
      return r;
    }, (r) => 'HTTP ${r.statusCode}, ${(r.bodyBytes.length / 1024).round()} КБ');
    await _run('Обработка приложением (фильтры, DeArrow)', () => service.getVideo(id), (v) => '«${v.title}»');
    ctDirectClearCache();
    await _run('Всё вместе (как при открытии видео)', () => service.getVideo(id), (v) => '«${v.title}»');
    await _run('Дизлайки (returnyoutubedislike)',
        () => c.get(Uri.parse('https://returnyoutubedislikeapi.com/votes?videoId=$id')), (r) => 'HTTP ${r.statusCode}');
    await _run('SponsorBlock', () => c.get(Uri.parse('https://sponsor.ajay.app/api/skipSegments?videoID=$id')),
        (r) => 'HTTP ${r.statusCode}');
    c.close();
    if (mounted) setState(() => running = false);
  }

  String _report() =>
      '${steps.map((s) => '${s.ok ? '✓' : '✗'} ${s.name}: ${s.ms} мс ${s.note}').join('\n')}\n\nПоследнее открытие видео:\n${CtTrace.report()}';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Проверка скорости YouTube'), actions: [
        if (steps.isNotEmpty && !running)
          IconButton(
              tooltip: 'Скопировать результат',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _report()));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопировано')));
              },
              icon: const Icon(Icons.copy)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Замеряет каждый шаг запуска видео на вашем устройстве и в вашей сети. '
            'Откройте любое видео из ленты, вернитесь сюда — ниже появится хронометраж от нажатия до старта. '
            'Скопируйте результат и пришлите — так видно, где задержка.',
            style: TextStyle(color: colors.onSurfaceVariant)),
        if (CtTrace.marks.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(children: [
            const Expanded(child: Text('Последнее открытие видео', style: TextStyle(fontWeight: FontWeight.w700))),
            TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: CtTrace.report()));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопировано')));
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Копировать')),
          ]),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: colors.surfaceContainerHigh, borderRadius: BorderRadius.circular(10)),
            child: SelectableText(CtTrace.report(), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ],
        const SizedBox(height: 12),
        TextField(controller: _vid, decoration: const InputDecoration(labelText: 'ID видео для проверки')),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: running ? null : _start,
          icon: running
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.speed),
          label: Text(running ? 'Идёт проверка…' : 'Начать проверку'),
        ),
        const SizedBox(height: 12),
        for (final s in steps)
          ListTile(
            dense: true,
            leading: Icon(s.ms == null ? Icons.hourglass_top : (s.ok ? Icons.check_circle : Icons.error),
                color: s.ms == null ? colors.outline : (s.ok ? Colors.green : colors.error)),
            title: Text(s.name),
            subtitle: s.note.isEmpty ? null : Text(s.note, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Text(s.ms == null ? '…' : '${s.ms} мс',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: (s.ms ?? 0) > 1500 ? colors.error : ((s.ms ?? 0) > 600 ? Colors.orange : null))),
          ),
      ]),
    );
  }
}
