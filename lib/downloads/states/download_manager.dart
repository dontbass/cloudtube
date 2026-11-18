import 'dart:async';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:cloudtube/cloudtube/download.dart';
import 'package:flutter/services.dart';
import 'package:downloadsfolder/downloadsfolder.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:cloudtube/downloads/models/downloaded_video.dart';
import 'package:cloudtube/extensions.dart';
import 'package:cloudtube/globals.dart';
import 'package:cloudtube/utils/models/image_object.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../player/states/player.dart';
import '../../videos/models/adaptive_format.dart';
import '../../videos/models/video.dart';
import '../../settings/models/db/server.dart';

part 'download_manager.freezed.dart';

final Logger log = Logger('DownloadState');

class DownloadProgress {
  CtCancel cancelToken;
  int count = 0, total = 1;

  /// Этап: 1 — звук, 2 — видео, 3 — склейка (для «только звук» этапов 2).
  int step = 1, totalSteps = 1;

  DownloadProgress(this.cancelToken);

  /// Общий прогресс загрузки 0..1 по всем этапам (раньше сбрасывался на каждом файле).
  double get value {
    final part = total > 0 ? (count / total).clamp(0.0, 1.0) : 0.0;
    return ((step - 1 + part) / totalSteps).clamp(0.0, 1.0);
  }

  String get stage => switch (step) {
        1 => 'звук',
        2 when totalSteps == 3 => 'видео',
        _ => 'сохранение',
      };
}

class DownloadManagerCubit extends Cubit<DownloadManagerState> {
  final PlayerCubit player;

  final _starting = <String>{};

  DownloadManagerCubit(super.initialState, this.player) {
    onReady();
  }

  onReady() {
    setVideos();
  }

  setVideos() async {
    var vids = List<DownloadedVideo>.from(db.getAllDownloads());
    // checking if we have any video that are not fail, not completed and not currently downloading
    for (int i = 0; i < vids.length; i++) {
      var v = vids[i];
      if (!v.downloadComplete &&
          !v.downloadFailed &&
          !state.downloadProgresses.containsKey(v.videoId)) {
        // this download was interrupted by app restart or crash or something else, we set it as errored
        v = v.copyWith(downloadFailed: true);
        vids[i] = v;
        await db.upsertDownload(v);
      }
    }

    emit(state.copyWith(videos: vids));
  }

  onProgress(int count, int total, DownloadedVideo video,
      {required int step, required int totalSteps}) async {
    if (count == total && step == totalSteps) {
      var progresses =
          Map<String, DownloadProgress>.from(state.downloadProgresses);
      var downloadProgress = progresses[video.videoId];

      if (downloadProgress == null ||
          downloadProgress.cancelToken.isCancelled) {
        return;
      }

      progresses.remove(video.videoId);
      video = video.copyWith(downloadComplete: true);
      await db.upsertDownload(video);
      emit(state.copyWith(downloadProgresses: progresses));
      setVideos();
    } else {
      EasyThrottle.throttle(
          'download-${video.videoId}', const Duration(milliseconds: 500), () {
        log.fine(
            'Download of video ${video.videoId}, $count / $total =  ${count / total}, Total: ${state.totalProgress}');
        var progresses =
            Map<String, DownloadProgress>.from(state.downloadProgresses);
        final dp = progresses[video.videoId];
        if (dp != null) {
          // новый объект: состояние сравнивается по значению, и с тем же объектом
          // обновление отбрасывалось — полоска прогресса стояла до конца загрузки
          progresses[video.videoId] = DownloadProgress(dp.cancelToken)
            ..count = count
            ..total = total
            ..step = step
            ..totalSteps = totalSteps;
        }
        emit(state.copyWith(downloadProgresses: progresses));
      });
    }
  }

  Future<bool> addDownload(String videoId,
      {String quality = '720p', bool audioOnly = false}) async {
    // повторное нажатие, пока ролик ещё готовится, — раньше шли две загрузки в одни и те же файлы
    if (state.videos.any((element) => element.videoId == videoId) ||
        db.getAllDownloads().any((e) => e.videoId == videoId) ||
        !_starting.add(videoId)) {
      return false;
    } else {
      final Video vid;
      final Server server;
      final DownloadedVideo downloadedVideo;
      try {
        vid = await service.getVideo(videoId);
        server = await db.getCurrentlySelectedServer();
        downloadedVideo = DownloadedVideo(
            videoId: vid.videoId,
            title: vid.title ?? '',
            author: vid.author,
            authorUrl: vid.authorUrl,
            audioOnly: audioOnly,
            lengthSeconds: vid.lengthSeconds ?? 0,
            quality: quality);
        await db.upsertDownload(downloadedVideo);
      } finally {
        _starting.remove(videoId);
      }

      String? videoUrl;

      if (!audioOnly) {
        // FormatStream stream = vid.formatStreams
        //     .firstWhere((element) => element.resolution == quality);

        // WebM-видео нужного качества; если такого нет — лучшее WebM не выше него
        // (раньше при отсутствии точного качества загрузка падала и оставалась «висеть» в списке)
        int h(AdaptiveFormat f) =>
            int.tryParse(RegExp(r'(\d+)p').firstMatch(f.qualityLabel ?? f.resolution ?? '')?.group(1) ?? '') ?? 0;
        final want = int.tryParse(quality.replaceAll(RegExp(r'\D'), '')) ?? 720;
        final webm = vid.adaptiveFormats!.where((f) => f.type.contains('video/webm') && h(f) > 0).toList()
          ..sort((a, b) => h(b).compareTo(h(a)));
        final stream = webm.where((f) => h(f) <= want).firstOrNull ?? webm.lastOrNull;
        if (stream == null) {
          await onDownloadError('Нет подходящего видеопотока', downloadedVideo);
          return false;
        }
        videoUrl = stream.url;
      }
      final audio = vid.adaptiveFormats!
          .sortByReversed((e) => int.parse(e.bitrate ?? "0"))
          .where((element) => element.type.contains("audio/webm"))
          .firstOrNull;
      if (audio == null) {
        await onDownloadError('Нет звуковой дорожки', downloadedVideo);
        return false;
      }
      String audioUrl = audio.url;

      final cancelToken = CtCancel();

      var progresses =
          Map<String, DownloadProgress>.from(state.downloadProgresses);
      progresses[downloadedVideo.videoId] = DownloadProgress(cancelToken);
      emit(state.copyWith(downloadProgresses: progresses));

      setVideos();
      // download thumbnail
      String? thumbUrl = ImageObject.getBestThumbnail(vid.videoThumbnails)?.url;
      log.fine(thumbUrl);
      if (thumbUrl != null) {
        //download thumbnail
        var thumbnailPath = await downloadedVideo.thumbnailPath;
        log.fine("Downloading thumbnail to: $thumbnailPath");
        try {
          await ctDownloadFile(thumbUrl, thumbnailPath,
              cancel: cancelToken, headers: server.headersForUrl(thumbUrl));
        } on CtCancelled {
          return false;
        } catch (e) {
          log.info('миниатюра не скачалась: $e'); // без неё ролик всё равно сохраняем
        }
      }

      if (cancelToken.isCancelled) {
        return false;
      }

      // download video
      var mediaPath = await downloadedVideo.downloadPath;

      final tempDir = await getTemporaryDirectory();
      final audioPath = '${tempDir.path}/${videoId}_audio.webm';
      final videoPath = '${tempDir.path}/${videoId}_video.webm';

      log.info(
          "Downloading video ${vid.title}, audioOnly ? $audioOnly, quality: $quality  to path: $tempDir");
      try {
        if (cancelToken.isCancelled) {
          return false;
        }
        // раньше после ошибки звука загрузка шла дальше и пыталась склеить несуществующий файл
        await ctDownloadFile(audioUrl, audioPath,
            onProgress: (count, total) =>
                onProgress(count, total, downloadedVideo, step: 1, totalSteps: audioOnly ? 2 : 3),
            cancel: cancelToken,
            headers: server.headersForUrl(audioUrl));

        if (videoUrl != null) {
          await ctDownloadFile(videoUrl, videoPath,
              onProgress: (count, total) => onProgress(count, total, downloadedVideo, step: 2, totalSteps: 3),
              cancel: cancelToken,
              headers: server.headersForUrl(videoUrl));
        }

        if (audioOnly) {
          final audio = File(audioPath);
          await audio.copy(mediaPath);
          onProgress(1, 1, downloadedVideo, step: 2, totalSteps: 2);
          return true;
        } else {
          onProgress(0, 1, downloadedVideo, step: 3, totalSteps: 3);
          // CloudTube: склейка видео и звука без перекодирования — встроенным в Android
          // MediaMuxer (раньше ради этого в установщик входил FFmpeg, +27 МБ)
          var success = false;
          try {
            success = await const MethodChannel('cloudtube/media').invokeMethod<bool>(
                    'mux', {'video': videoPath, 'audio': audioPath, 'out': mediaPath}) ??
                false;
            if (!success) onDownloadError("Couldn't merge audio and video", downloadedVideo);
          } catch (e) {
            onDownloadError("Couldn't merge audio and video: $e", downloadedVideo);
          }
          if (success) onProgress(1, 1, downloadedVideo, step: 3, totalSteps: 3);
          return success;
        }
      } catch (e) {
        await onDownloadError(e, downloadedVideo);
        return false;
      } finally {
        final audio = File(audioPath);
        final video = File(videoPath);

        if (await audio.exists()) {
          await audio.delete();
        }

        if (await video.exists()) {
          await video.delete();
        }
      }
    }
  }

  Future<void> deleteVideo(DownloadedVideo vid) async {
    var progresses =
        Map<String, DownloadProgress>.from(state.downloadProgresses);
    var downloadProgress = progresses[vid.videoId];
    log.fine(
        'cancelling download for video ${vid.videoId}, present ? : ${downloadProgress != null}');
    downloadProgress?.cancelToken.cancel();

    progresses.remove(vid.videoId);

    try {
      String path = await vid.effectivePath;
      await File(path).delete();
    } catch (e) {
      log.fine('Video file might not be available, that\'s ok');
    }

    try {
      String path = await vid.thumbnailPath;
      await File(path).delete();
    } catch (e) {
      log.fine('Thumbnail might not be available, that\'s ok');
    }

    await db.deleteDownload(vid);
    emit(state.copyWith(downloadProgresses: progresses));

    setVideos();
  }

  FutureOr<void> onDownloadError(dynamic err, DownloadedVideo vid) async {
    if (err is CtCancelled) {
      log.fine("video cancelled, nothing to do");
      return;
    }
    if (err is Error) {
      log.severe(
          "Failed to download video ${vid.title}, removing it", err.stackTrace);
    } else {
      log.severe("Failed to download video ${vid.title}, removing it", err);
    }
    // раньше здесь вызывался onProgress(1, 1) — он успевал записать «загружено» поверх ошибки
    vid = vid.copyWith(downloadComplete: false, downloadFailed: true);
    var progresses =
        Map<String, DownloadProgress>.from(state.downloadProgresses);
    progresses.remove(vid.videoId);
    await db.upsertDownload(vid);
    setVideos();
    emit(state.copyWith(downloadProgresses: progresses));
    return;
  }

  Future<void> retryDownload(DownloadedVideo vid) async {
    await deleteVideo(vid);
    await addDownload(vid.videoId,
        quality: vid.quality, audioOnly: vid.audioOnly);
  }

  /// Копия в общую папку «Загрузки». Имя — по названию ролика (кириллица сохраняется).
  Future<bool> copyToDownloadFolder(DownloadedVideo v) async {
    final file = File(await v.effectivePath);
    if (!await file.exists()) return false;
    var name = v.title.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    if (name.length > 80) name = name.substring(0, 80);
    final fileName = '${name.isEmpty ? 'video' : name}_${v.videoId}${p.extension(file.path)}';
    try {
      final ok = await copyFileIntoDownloadFolder(file.path, fileName) ?? false;
      log.info('file ${file.path} copied to download folder as $fileName (success $ok)');
      return ok;
    } catch (e) {
      log.warning('copy to downloads failed: $e');
      return false;
    }
  }
}

@freezed
sealed class DownloadManagerState with _$DownloadManagerState {
  const factory DownloadManagerState(
          {@Default([]) List<DownloadedVideo> videos,
          @Default({}) Map<String, DownloadProgress> downloadProgresses}) =
      _DownloadManagerState;

  const DownloadManagerState._();

  double get totalProgress {

    if (downloadProgresses.isEmpty) return 0;
    var sum = 0.0;
    for (final e in downloadProgresses.values) {
      sum += e.value;
    }
    return sum / downloadProgresses.length;
  }
}
