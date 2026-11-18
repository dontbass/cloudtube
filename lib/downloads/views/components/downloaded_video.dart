import 'dart:io';

import 'package:cloudtube/downloads/models/downloaded_video.dart';
import 'package:cloudtube/downloads/states/download_manager.dart';
import 'package:cloudtube/player/states/player.dart';
import 'package:cloudtube/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cloudtube/theme.dart';

/// «1,4 ГБ», «820 МБ».
String ctFileSize(int bytes) {
  if (bytes <= 0) return '';
  const mb = 1024 * 1024, gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1).replaceAll('.', ',')} ГБ';
  if (bytes >= mb) return '${(bytes / mb).round()} МБ';
  return '${(bytes / 1024).round()} КБ';
}

/// Строка загрузки: миниатюра, название, состояние (прогресс / ошибка / размер),
/// действия — по нажатию и через «⋮».
class DownloadedVideoView extends StatefulWidget {
  final DownloadedVideo video;

  /// null — не загружается; иначе прогресс 0..1 и этап.
  final DownloadProgress? progress;

  const DownloadedVideoView({super.key, required this.video, this.progress});

  @override
  State<DownloadedVideoView> createState() => _DownloadedVideoViewState();
}

class _DownloadedVideoViewState extends State<DownloadedVideoView> {
  String? _thumb;
  int _size = 0;

  @override
  void initState() {
    super.initState();
    _readFiles();
  }

  @override
  void didUpdateWidget(covariant DownloadedVideoView old) {
    super.didUpdateWidget(old);
    // миниатюра и размер появляются по ходу загрузки — перечитываем при смене состояния
    if (old.video.downloadComplete != widget.video.downloadComplete ||
        (old.progress == null) != (widget.progress == null) ||
        _thumb == null) {
      _readFiles();
    }
  }

  Future<void> _readFiles() async {
    final v = widget.video;
    String? thumb;
    var size = 0;
    try {
      final t = await v.thumbnailPath;
      if (await File(t).exists()) thumb = t;
      if (v.downloadComplete) {
        final f = File(await v.effectivePath);
        if (await f.exists()) size = await f.length();
      }
    } catch (_) {}
    if (mounted && (thumb != _thumb || size != _size)) {
      setState(() {
        _thumb = thumb;
        _size = size;
      });
    }
  }

  DownloadedVideo get v => widget.video;

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _delete() async {
    final cubit = context.read<DownloadManagerCubit>();
    final active = widget.progress != null;
    await cubit.deleteVideo(v);
    _snack(active ? 'Загрузка отменена' : 'Видео удалено');
  }

  Future<void> _copy() async {
    final ok = await context.read<DownloadManagerCubit>().copyToDownloadFolder(v);
    _snack(ok ? 'Сохранено в папку «Загрузки»' : 'Не удалось скопировать файл');
  }

  void _tap() {
    final cubit = context.read<DownloadManagerCubit>();
    if (v.downloadComplete) {
      context.read<PlayerCubit>().playOfflineVideos([v]);
    } else if (v.downloadFailed) {
      cubit.retryDownload(v);
    } else {
      _menu();
    }
  }

  void _menu() {
    showSafeModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        ListTile item(IconData icon, String text, Future<void> Function() action, {bool danger = false}) {
          final color = danger ? Theme.of(ctx).colorScheme.error : null;
          return ListTile(
            leading: Icon(icon, color: color),
            title: Text(text, style: TextStyle(color: color)),
            onTap: () {
              Navigator.of(ctx).pop();
              action();
            },
          );
        }

        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            if (v.downloadComplete) ...[
              item(Icons.play_arrow_rounded, 'Смотреть', () async => _tap()),
              item(Icons.save_alt_rounded, 'Сохранить в «Загрузки»', _copy),
            ],
            if (v.downloadFailed)
              item(Icons.refresh_rounded, 'Повторить загрузку', () => context.read<DownloadManagerCubit>().retryDownload(v)),
            if (widget.progress != null)
              item(Icons.close_rounded, 'Отменить загрузку', _delete, danger: true)
            else
              item(Icons.delete_outline_rounded, 'Удалить', _delete, danger: true),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final p = widget.progress;

    final Widget status;
    if (p != null) {
      final pct = (p.value * 100).floor();
      status = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(pct == 0 ? 'Подготовка…' : 'Загрузка: ${p.stage} · $pct%',
            style: text.bodySmall?.copyWith(color: ctAccent(colors))),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: pct == 0 ? null : p.value, borderRadius: BorderRadius.circular(4)),
      ]);
    } else if (v.downloadFailed) {
      status = Row(children: [
        Icon(Icons.error_outline_rounded, size: 16, color: colors.error),
        const SizedBox(width: 4),
        Flexible(child: Text('Ошибка — нажмите, чтобы повторить', style: text.bodySmall?.copyWith(color: colors.error))),
      ]);
    } else {
      final parts = [
        if (v.audioOnly) 'только звук' else v.quality,
        if (v.lengthSeconds > 0) prettyDurationCustom(Duration(seconds: v.lengthSeconds)),
        if (_size > 0) ctFileSize(_size),
      ];
      status = Text(parts.join(' · '), style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant));
    }

    final thumb = _thumb;
    return InkWell(
      onTap: _tap,
      onLongPress: _menu,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 136,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(fit: StackFit.expand, children: [
                  thumb != null
                      ? Image.file(File(thumb), fit: BoxFit.cover, cacheWidth: 400, gaplessPlayback: true)
                      : Container(color: colors.secondaryContainer),
                  if (v.audioOnly)
                    const Center(child: Icon(Icons.headphones_rounded, color: Colors.white, size: 30)),
                  if (v.downloadFailed) Container(color: Colors.black.withValues(alpha: 0.45)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall),
              if ((v.author ?? '').isNotEmpty)
                Text(v.author!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
              const SizedBox(height: 6),
              status,
            ]),
          ),
          IconButton(
              onPressed: _menu,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.more_vert_rounded, color: colors.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
