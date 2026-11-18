import 'package:bloc/bloc.dart';
import 'package:cloudtube/globals.dart';
import 'package:cloudtube/notifications/models/db/channel_notifications.dart';
import 'package:cloudtube/notifications/models/db/playlist_notifications.dart';

abstract class NotificationListCubit<T> extends Cubit<List<T>> {
  NotificationListCubit(super.initialState);

  getNotifications();

  deleteNotification(T notif);
}

class ChannelNotificationListCubit
    extends NotificationListCubit<ChannelNotification> {
  ChannelNotificationListCubit(super.initialState) {
    getNotifications();
  }

  @override
  getNotifications() async {
    emit(List.of(await fileDb.getAllChannelNotifications()));
  }

  @override
  deleteNotification(ChannelNotification notif) async {
    await fileDb.deleteChannelNotification(notif);
    await getNotifications();
  }
}

class PlaylistNotificationListCubit
    extends NotificationListCubit<PlaylistNotification> {
  PlaylistNotificationListCubit(super.initialState) {
    getNotifications();
  }

  @override
  deleteNotification(PlaylistNotification notif) async {
    await fileDb.deletePlaylistNotification(notif);
    getNotifications();
  }

  @override
  getNotifications() async {
    emit(List.of(await fileDb.getAllPlaylistNotifications()));
  }
}
