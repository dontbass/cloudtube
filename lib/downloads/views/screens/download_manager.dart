import 'dart:io';

import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloudtube/downloads/models/downloaded_video.dart';
import 'package:cloudtube/downloads/views/components/downloaded_video.dart';
import 'package:cloudtube/player/states/player.dart';

import '../../../cloudtube/ui_card.dart';
import '../../../cloudtube/ui_state.dart';
import '../../../utils.dart';
import '../../states/download_manager.dart';

/// Загрузки: сверху сводка и «Смотреть все», ниже группы
/// «Загружаются» / «Не удалось» / «Сохранено».
@RoutePage()
class DownloadManagerScreen extends StatelessWidget {
  const DownloadManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Загрузки'), actions: const [_ClearFailedButton()]),
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<DownloadManagerCubit, DownloadManagerState>(builder: (context, s) {
          if (s.videos.isEmpty) {
            return const CtEmptyView(
                icon: Icons.download_rounded,
                text: 'Здесь появятся скачанные видео.\nСкачать можно со страницы ролика.');
          }
          final active = s.videos.where((v) => s.downloadProgresses.containsKey(v.videoId)).toList();
          final failed = s.videos.where((v) => v.downloadFailed && !s.downloadProgresses.containsKey(v.videoId)).toList();
          final done = s.videos.where((v) => v.downloadComplete && !v.downloadFailed).toList();

          final rows = <Widget>[
            _Summary(done: done),
            if (active.isNotEmpty) ...[
              CtCardSection('Загружаются · ${active.length}'),
              for (final v in active)
                DownloadedVideoView(key: ValueKey('a-${v.videoId}'), video: v, progress: s.downloadProgresses[v.videoId]),
            ],
            if (failed.isNotEmpty) ...[
              CtCardSection('Не удалось · ${failed.length}'),
              for (final v in failed) DownloadedVideoView(key: ValueKey('f-${v.videoId}'), video: v),
            ],
            if (done.isNotEmpty) ...[
              CtCardSection('Сохранено · ${done.length}'),
              for (final v in done) DownloadedVideoView(key: ValueKey('d-${v.videoId}'), video: v),
            ],
            const SizedBox(height: 80),
          ];
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: tabletMaxVideoWidth),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: rows.length,
                itemBuilder: (_, i) => rows[i],
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// «N видео · X ГБ» и кнопки «Смотреть все» / «Перемешать».
class _Summary extends StatefulWidget {
  final List<DownloadedVideo> done;

  const _Summary({required this.done});

  @override
  State<_Summary> createState() => _SummaryState();
}

class _SummaryState extends State<_Summary> {
  int _bytes = 0;
  int _count = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sum();
  }

  @override
  void didUpdateWidget(covariant _Summary old) {
    super.didUpdateWidget(old);
    if (old.done.length != widget.done.length) _sum();
  }

  Future<void> _sum() async {
    final list = widget.done;
    if (list.length == _count) return;
    _count = list.length;
    var total = 0;
    for (final v in list) {
      try {
        final f = File(await v.effectivePath);
        if (await f.exists()) total += await f.length();
      } catch (_) {}
    }
    if (mounted) setState(() => _bytes = total);
  }

  void _play({bool shuffle = false}) {
    final list = [...widget.done];
    if (list.isEmpty) return;
    if (shuffle) list.shuffle();
    context.read<PlayerCubit>().playOfflineVideos(list);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final n = widget.done.length;
    final ready = n > 0;
    final size = ctFileSize(_bytes);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ready ? 'Сохранено видео: $n${size.isEmpty ? '' : ' · $size'}' : 'Пока ничего не сохранено',
            style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
                style: FilledButton.styleFrom(shape: const StadiumBorder(), minimumSize: const Size(0, 44)),
                onPressed: ready ? () => _play() : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Смотреть все')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(shape: const StadiumBorder(), minimumSize: const Size(0, 44)),
                onPressed: n > 1 ? () => _play(shuffle: true) : null,
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('Перемешать')),
          ),
        ]),
      ]),
    );
  }
}

/// Убрать все неудачные загрузки одним нажатием (видна, только когда они есть).
class _ClearFailedButton extends StatelessWidget {
  const _ClearFailedButton();

  @override
  Widget build(BuildContext context) {
    final failed = context.select((DownloadManagerCubit c) => c.state.videos
        .where((v) => v.downloadFailed && !c.state.downloadProgresses.containsKey(v.videoId))
        .toList());
    if (failed.isEmpty) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Убрать неудачные',
      icon: const Icon(Icons.delete_sweep_outlined),
      onPressed: () async {
        final cubit = context.read<DownloadManagerCubit>();
        for (final v in failed) {
          await cubit.deleteVideo(v);
        }
      },
    );
  }
}
