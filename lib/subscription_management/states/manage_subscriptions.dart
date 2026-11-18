import 'package:bloc/bloc.dart';
import 'package:cloudtube/offline_subscriptions/models/offline_subscription.dart';
import 'package:logging/logging.dart';

import '../../globals.dart';

final _log = Logger('Подписки');

/// Подписка на канал: в аккаунте, на устройстве или и там, и там.
class CtSub {
  final String id;
  final String name;
  final bool account;
  final bool device;

  const CtSub(this.id, this.name, {this.account = false, this.device = false});

  CtSub copyWith({bool? account, bool? device}) =>
      CtSub(id, name, account: account ?? this.account, device: device ?? this.device);
}

class ManageSubscriptionsState {
  final List<CtSub> subs;
  final bool loading;
  final bool isLoggedIn;
  final String? error;
  final String query;

  const ManageSubscriptionsState(
      {this.subs = const [], this.loading = true, this.isLoggedIn = false, this.error, this.query = ''});

  /// Отфильтрованный поиском список.
  List<CtSub> get visible {
    final q = query.trim().toLowerCase();
    return q.isEmpty ? subs : subs.where((s) => s.name.toLowerCase().contains(q)).toList();
  }

  ManageSubscriptionsState copyWith(
          {List<CtSub>? subs, bool? loading, bool? isLoggedIn, String? error, bool clearError = false, String? query}) =>
      ManageSubscriptionsState(
          subs: subs ?? this.subs,
          loading: loading ?? this.loading,
          isLoggedIn: isLoggedIn ?? this.isLoggedIn,
          error: clearError ? null : error ?? this.error,
          query: query ?? this.query);
}

/// Все подписки одним списком (аккаунт + устройство), отписка с возможностью вернуть.
class ManageSubscriptionCubit extends Cubit<ManageSubscriptionsState> {
  ManageSubscriptionCubit() : super(const ManageSubscriptionsState()) {
    refreshSubs();
  }

  Future<void> refreshSubs() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final loggedIn = await service.isLoggedIn();
      final map = <String, CtSub>{};
      String? accountError;
      if (loggedIn) {
        try {
          for (final s in await service.getSubscriptions()) {
            map[s.authorId] = CtSub(s.authorId, s.author, account: true);
          }
        } catch (e) {
          // аккаунт недоступен — покажем хотя бы подписки на устройстве
          accountError = 'Подписки аккаунта не загрузились';
          _log.warning('account subs: $e');
        }
      }
      for (final o in await db.getOfflineSubscriptions()) {
        final cur = map[o.channelId];
        map[o.channelId] = cur?.copyWith(device: true) ?? CtSub(o.channelId, o.channelName, device: true);
      }
      final list = map.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!isClosed) emit(state.copyWith(subs: list, loading: false, isLoggedIn: loggedIn, error: accountError));
    } catch (e) {
      _log.warning('subs: $e');
      if (!isClosed) emit(state.copyWith(loading: false, error: 'Не удалось загрузить подписки'));
    }
  }

  void setQuery(String q) => emit(state.copyWith(query: q));

  /// Отписаться везде, где есть подписка. Возвращает false, если аккаунт не ответил.
  Future<bool> unsubscribe(CtSub s) async {
    var ok = true;
    if (s.account) {
      try {
        ok = await service.unSubscribe(s.id);
      } catch (e) {
        ok = false;
      }
    }
    if (s.device) await db.deleteOfflineSubscription(s.id);
    if (ok && !isClosed) emit(state.copyWith(subs: state.subs.where((x) => x.id != s.id).toList()));
    if (!ok) await refreshSubs();
    return ok;
  }

  /// Вернуть подписку после «Отменить».
  Future<void> restore(CtSub s) async {
    if (s.account) {
      try {
        await service.subscribe(s.id);
      } catch (_) {}
    }
    if (s.device) {
      await db.addOfflineSubscription(OfflineSubscription(channelId: s.id, channelName: s.name));
    }
    await refreshSubs();
  }
}
