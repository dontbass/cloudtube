import 'package:bloc/bloc.dart';
import 'package:clipious/videos/models/video.dart';
import 'package:logging/logging.dart';

import '../../globals.dart';
import '../models/playlist.dart';

final _log = Logger('Плейлист');

/// Состояние страницы плейлиста: ролики догружаются страницами, прогресс 0..1.
class PlaylistState {
  final Playlist playlist;
  final bool loading;
  final double progress;
  final String? error;

  const PlaylistState({required this.playlist, this.loading = true, this.progress = 0, this.error});

  /// Ролики, которые можно показать (без скрытых фильтром).
  List<Video> get visible => playlist.videos.where((v) => !v.filterHide).toList();

  PlaylistState copyWith({Playlist? playlist, bool? loading, double? progress, String? error, bool clearError = false}) =>
      PlaylistState(
          playlist: playlist ?? this.playlist,
          loading: loading ?? this.loading,
          progress: progress ?? this.progress,
          error: clearError ? null : error ?? this.error);
}

class PlaylistCubit extends Cubit<PlaylistState> {
  /// Свой плейлист (аккаунт Invidious) — его можно править, и он перечитывается целиком.
  final bool userPlaylist;

  PlaylistCubit(Playlist playlist, {this.userPlaylist = false}) : super(PlaylistState(playlist: playlist)) {
    load();
  }

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      if (userPlaylist) {
        final pl = await service.getUserPlaylist(state.playlist.playlistId);
        if (isClosed) return;
        emit(state.copyWith(playlist: pl));
      }
      await _loadAllPages();
      if (!isClosed) emit(state.copyWith(loading: false, progress: 1));
    } catch (e, st) {
      _log.warning('Плейлист ${state.playlist.playlistId} не загрузился', e, st);
      if (!isClosed) emit(state.copyWith(loading: false, error: '$e'));
    }
  }

  /// Публичный плейлист приходит страницами — догружаем, пока не наберём videoCount.
  Future<void> _loadAllPages() async {
    final total = state.playlist.videoCount;
    if (total <= 0 || state.playlist.videos.length >= total) return;
    final seen = {for (final v in state.playlist.videos) v.videoId};
    var filtered = 0;
    for (var page = 1; page < 200; page++) {
      final pl = await service.getPublicPlaylists(state.playlist.playlistId, page: page);
      if (isClosed) return;
      final add = pl.videos.where((v) => seen.add(v.videoId)).toList();
      filtered += pl.removedByFilter;
      final videos = [...state.playlist.videos, ...add];
      emit(state.copyWith(
          playlist: state.playlist.copyWith(videos: videos),
          progress: ((videos.length + filtered) / total).clamp(0, 1).toDouble()));
      // пустая страница или ничего нового — конец (защита от зацикливания)
      if (pl.videos.isEmpty && pl.removedByFilter == 0) break;
      if (add.isEmpty && pl.removedByFilter == 0) break;
      if (videos.length + filtered >= total) break;
    }
  }

  Future<void> deletePlaylist() => service.deleteUserPlaylist(state.playlist.playlistId);

  /// Убрать ролик из своего плейлиста. Ошибку пробрасываем — экран покажет её.
  Future<void> removeVideo(Video v) async {
    await service.deleteUserPlaylistVideo(state.playlist.playlistId, v.indexId ?? '');
    final videos = [...state.playlist.videos]..remove(v);
    if (!isClosed) {
      emit(state.copyWith(playlist: state.playlist.copyWith(videos: videos, videoCount: videos.length)));
    }
  }

  /// Очередь для плеера: с выбранного ролика, по порядку или вперемешку.
  List<Video> queue({Video? start, bool shuffle = false}) {
    final list = state.visible.where((v) => !v.filtered).toList();
    if (shuffle) return list..shuffle();
    final i = start == null ? 0 : list.indexWhere((v) => v.videoId == start.videoId);
    return i <= 0 ? list : list.sublist(i);
  }
}
