import 'package:bloc/bloc.dart';
import 'package:logging/logging.dart';

import '../../globals.dart';
import '../models/channel.dart';
import '../models/channel_sort_by.dart';

final _log = Logger('Канал');

/// Состояние страницы канала: загрузка → канал или ошибка (с повтором).
class ChannelState {
  final String channelId;
  final Channel? channel;
  final bool loading;
  final String? error;
  final ChannelSortBy sortBy;

  const ChannelState(
      {required this.channelId, this.channel, this.loading = true, this.error, this.sortBy = ChannelSortBy.newest});

  ChannelState copyWith({Channel? channel, bool? loading, String? error, bool clearError = false, ChannelSortBy? sortBy}) =>
      ChannelState(
          channelId: channelId,
          channel: channel ?? this.channel,
          loading: loading ?? this.loading,
          error: clearError ? null : error ?? this.error,
          sortBy: sortBy ?? this.sortBy);
}

class ChannelCubit extends Cubit<ChannelState> {
  ChannelCubit(String channelId) : super(ChannelState(channelId: channelId)) {
    load();
  }

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final channel = await service.getChannel(state.channelId);
      if (!isClosed) emit(state.copyWith(channel: channel, loading: false));
    } catch (e, st) {
      _log.warning('Канал ${state.channelId} не загрузился', e, st);
      if (!isClosed) emit(state.copyWith(loading: false, error: '$e'));
    }
  }

  void onSortByChanged(ChannelSortBy v) {
    if (v != state.sortBy) emit(state.copyWith(sortBy: v));
  }
}
