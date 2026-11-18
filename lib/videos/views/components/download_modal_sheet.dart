import 'package:cloudtube/globals.dart';
import 'package:cloudtube/main.dart';
import 'package:cloudtube/utils.dart';
import 'package:cloudtube/videos/models/adaptive_format.dart';
import 'package:cloudtube/videos/models/video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cloudtube/theme.dart';
import '../../../cloudtube/ui_state.dart';
import '../../../downloads/states/download_manager.dart';
import '../../../downloads/views/components/downloaded_video.dart' show ctFileSize;

/// Шторка «Скачать»: список качеств с примерным размером и «Только звук».
/// Качества берутся из WebM-потоков ролика (их же скачивает менеджер загрузок).
class DownloadModalSheet extends StatefulWidget {
  final Video video;
  final Function()? onDownload;
  final Function(bool isDownloadStarted)? onDownloadStarted;

  const DownloadModalSheet({super.key, required this.video, this.onDownloadStarted, this.onDownload});

  static void showVideoModalSheet(BuildContext context, Video video,
      {Function(bool isDownloadStarted)? onDownloadStarted, Function()? onDownload}) {
    showSafeModalBottomSheet<void>(
        enableDrag: true,
        showDragHandle: true,
        context: context,
        builder: (_) => DownloadModalSheet(video: video, onDownload: onDownload, onDownloadStarted: onDownloadStarted));
  }

  @override
  State<DownloadModalSheet> createState() => _DownloadModalSheetState();
}

/// Вариант загрузки: высота (0 — только звук) и примерный размер в байтах.
typedef _Option = ({int height, int bytes, String label});

int _height(AdaptiveFormat f) =>
    int.tryParse(RegExp(r'(\d+)p').firstMatch(f.qualityLabel ?? f.resolution ?? '')?.group(1) ?? '') ?? 0;

int _len(AdaptiveFormat f) => int.tryParse(f.clen) ?? 0;

/// Из форматов ролика — по одному варианту на высоту (лучший поток), от большего к меньшему.
List<_Option> ctDownloadOptions(List<AdaptiveFormat> formats) {
  final audio = formats.where((f) => f.type.contains('audio/webm')).toList()
    ..sort((a, b) => (int.tryParse(b.bitrate ?? '') ?? 0).compareTo(int.tryParse(a.bitrate ?? '') ?? 0));
  final audioLen = audio.isEmpty ? 0 : _len(audio.first);
  final best = <int, AdaptiveFormat>{};
  for (final f in formats.where((f) => f.type.contains('video/webm'))) {
    final h = _height(f);
    if (h <= 0) continue;
    final cur = best[h];
    if (cur == null || _len(f) > _len(cur)) best[h] = f;
  }
  final heights = best.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final h in heights)
      (height: h, bytes: _len(best[h]!) + audioLen, label: h >= 2160 ? '4K · ${h}p' : '${h}p'),
    if (audio.isNotEmpty) (height: 0, bytes: audioLen, label: 'Только звук'),
  ];
}

class _DownloadModalSheetState extends State<DownloadModalSheet> {
  late Future<List<_Option>> _options = _load();
  int? _picked;

  Future<List<_Option>> _load() async {
    final vid = await service.getVideo(widget.video.videoId);
    return ctDownloadOptions(vid.adaptiveFormats ?? const []);
  }

  Future<void> _start(_Option o) async {
    final manager = context.read<DownloadManagerCubit>();
    widget.onDownload?.call();
    Navigator.of(context).pop();
    scaffoldKey.currentState?.showSnackBar(const SnackBar(content: Text('Загрузка началась — она в «Загрузках»')));
    final ok = await manager.addDownload(widget.video.videoId,
        audioOnly: o.height == 0, quality: o.height == 0 ? '720p' : '${o.height}p');
    if (!ok) {
      scaffoldKey.currentState?.showSnackBar(const SnackBar(content: Text('Это видео уже скачано или скачивается')));
    }
    widget.onDownloadStarted?.call(ok);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: FutureBuilder<List<_Option>>(
        future: _options,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
          }
          final options = snap.data ?? const <_Option>[];
          if (snap.hasError || options.isEmpty) {
            return SizedBox(
              height: 260,
              child: CtErrorView(
                  message: snap.hasError ? 'Не удалось получить качества' : 'Для этого видео нет файлов для загрузки',
                  onRetry: () => setState(() => _options = _load())),
            );
          }
          // по умолчанию — 1080p или ближайшее ниже
          final picked = _picked ??
              (options.where((o) => o.height > 0 && o.height <= 1080).firstOrNull ?? options.first).height;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Скачать видео', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(widget.video.title ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final o in options)
                  ChoiceChip(
                    showCheckmark: false,
                    selected: o.height == picked,
                    avatar: o.height == 0 ? const Icon(Icons.headphones_rounded, size: 18) : null,
                    label: Text(o.bytes > 0 ? '${o.label} · ~${ctFileSize(o.bytes)}' : o.label),
                    onSelected: (_) => setState(() => _picked = o.height),
                  ),
              ]),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      shape: const StadiumBorder(), minimumSize: const Size(0, 48), backgroundColor: ctAccent(colors)),
                  onPressed: () => _start(options.firstWhere((o) => o.height == picked)),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Скачать'),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}

/// Значок «Скачать» в шапке плеера: идёт загрузка — кружок прогресса,
/// уже скачано — галочка (нажатие открывает «Загрузки»).
class CtDownloadIconButton extends StatelessWidget {
  final Video video;
  final VoidCallback onOpenDownloads;

  const CtDownloadIconButton({super.key, required this.video, required this.onOpenDownloads});

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DownloadManagerCubit>().state;
    final p = dm.downloadProgresses[video.videoId];
    final saved = dm.videos.any((d) => d.videoId == video.videoId && d.downloadComplete);
    if (p != null) {
      return IconButton(
        tooltip: 'Скачивается',
        onPressed: onOpenDownloads,
        icon: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, value: p.value > 0 ? p.value : null)),
      );
    }
    return IconButton(
      tooltip: saved ? 'Скачано' : 'Скачать',
      onPressed: saved ? onOpenDownloads : () => DownloadModalSheet.showVideoModalSheet(context, video),
      icon: Icon(saved ? Icons.download_done_rounded : Icons.download_rounded),
    );
  }
}
