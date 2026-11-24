import 'dart:io';
import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:cloudtube/l10n/generated/app_localizations.dart';
import 'cloudtube/direct.dart';
import 'cloudtube/yt_account.dart';
import 'package:cloudtube/globals.dart';
import 'package:cloudtube/notifications/models/db/subscription_notifications.dart';
import 'package:cloudtube/settings/states/settings.dart';
import 'package:cloudtube/utils/file_db.dart';
import 'package:logging/logging.dart';
import 'package:workmanager/workmanager.dart';

import 'notifications/notifications.dart';
import 'videos/models/video.dart';

var log = Logger('background-task');
const taskName = "Clipious background refresh task";

Future<void> configureBackgroundService(SettingsCubit settings) async {
  if (!Platform.isAndroid) return; // фоновые задачи — только Android
  if (settings.state.backgroundNotifications) {
    await Workmanager()
        .initialize(callbackDispatcher, isInDebugMode: kDebugMode);
  }
}

Future<void> setupTasks(SettingsCubit settings) async {
  try {
    await Workmanager().cancelByUniqueName(taskName);
  } catch (e) {
    log.fine('task not registered');
    // fail silently in case no tasks have been already defined
  }
  await Workmanager().registerPeriodicTask(taskName, taskName,
      frequency: kDebugMode
          ? const Duration(seconds: 15)
          : Duration(hours: settings.state.backgroundNotificationFrequency),
      constraints: Constraints(
          networkType: NetworkType.connected, requiresBatteryNotLow: true));
}

Future<void> stopTasks() async {
  await Workmanager().cancelAll();
}

@pragma(
    'vm:entry-point') // Mandatory if the App is obfuscated or using Flutter 3.1+
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    log.info(
        "Native called background task: $task"); //simpleTask will be emitted here.
    if (task == taskName) {
      await _backgroundCheck();
    }
    return Future.value(true);
  });
}

_backgroundCheck() async {
  try {
    Logger.root.level =
        kDebugMode ? Level.FINEST : Level.INFO; // defaults to Level.INFO
    Logger.root.onRecord.listen((record) async {
      debugPrint(
          '[${record.level.name}] [${record.loggerName}] ${record.message}');
    });
    db = FileDB();
    await initializeNotificationChannels();
    // CloudTube: фоновая задача работает в отдельном изоляте — режим «без сервера» и вход
    // в YouTube нужно поднять заново, иначе уведомления работали только со своим сервером
    try {
      final cur = await db.getCurrentlySelectedServer();
      ctDirectActive = ctIsDirectUrl(cur.url);
      ctYtRefreshToken = ctDirectActive && (cur.authToken?.isNotEmpty ?? false) ? cur.authToken : null;
    } catch (_) {}
    // каждая проверка сама по себе: ошибка одной (сеть, канал удалён) не отменяет остальные
    for (final step in [_handleSubscriptionsNotifications, _handleChannelNotifications, _handlePlaylistNotifications]) {
      try {
        await step();
      } catch (e) {
        log.info('фоновая проверка: $e');
      }
    }
  } catch (e) {
    log.severe("Error while running workmanager", e);
    rethrow;
  }
}

Future<AppLocalizations> getLocalization() async {
  List<String>? localeString;
  String dbLocale = await fileDb.getLocale() ?? PlatformDispatcher.instance.locale.languageCode;
  localeString = dbLocale.split('_');
  // переводы есть только для русского и английского
  final lang = AppLocalizations.supportedLocales.any((l) => l.languageCode == localeString![0])
      ? localeString[0]
      : 'en';
  return await AppLocalizations.delegate.load(Locale(lang));
}

Future<void> _handlePlaylistNotifications() async {
  final notifs = await fileDb.getAllPlaylistNotifications();
  for (final n in notifs) {
    try {
      final pl = await service.getPublicPlaylists(n.playlistId, saveLastSeen: false);
      // новых роликов = сейчас − сколько было (раньше вычиталось наоборот и уведомлений не было)
      final fresh = pl.videoCount - n.lastVideoCount;
      if (n.lastVideoCount > 0 && fresh > 0) {
        final locals = await getLocalization();
        await sendNotification(locals.playlistNotificationTitle(n.playlistName),
            pl.videos.isNotEmpty && fresh == 1 ? (pl.videos.last.title ?? '') : locals.playlistNotificationContent(n.playlistName, fresh),
            type: NotificationTypes.playlist, payload: {playlistId: n.playlistId}, id: n.playlistId.hashCode);
        // запомнить: раньше то же уведомление приходило при каждой проверке, пока плейлист не откроют
        await fileDb.setPlaylistNotificationLastViewedVideo(n.playlistId, pl.videoCount);
      }
    } catch (e) {
      log.info('плейлист ${n.playlistId}: $e');
    }
  }
}

Future<void> _handleChannelNotifications() async {
  final notifs = await fileDb.getAllChannelNotifications();
  for (final n in notifs) {
    try {
      final videos = await service.getChannelVideos(n.channelId, null, saveLastSeen: false);
      if (videos.videos.isEmpty || n.lastSeenVideoId.isEmpty) continue;
      final index = videos.videos.indexWhere((e) => e.videoId == n.lastSeenVideoId);
      final fresh = index >= 0 ? index : videos.videos.length;
      if (fresh <= 0) continue;
      final locals = await getLocalization();
      // одно новое видео — его название, несколько — сколько их
      await sendNotification(locals.channelNotificationTitle(n.channelName),
          fresh == 1 ? (videos.videos.first.title ?? '') : locals.channelNotificationContent(n.channelName, fresh),
          type: NotificationTypes.channel,
          payload: {channelId: n.channelId, lastSeenVideo: videos.videos.first.videoId},
          id: n.channelId.hashCode);
      // запомнить: раньше то же уведомление приходило при каждой проверке, пока канал не откроют
      await fileDb.setChannelNotificationLastViewedVideo(n.channelId, videos.videos.first.videoId);
    } catch (e) {
      log.info('канал ${n.channelId}: $e');
    }
  }
}

Future<void> _handleSubscriptionsNotifications() async {
  bool isEnabled = await fileDb.getSubscriptionNotifications();
  if (!isEnabled) return;
  // без входа в аккаунт — по подпискам на устройстве (режим без сервера тоже)
  if (!await db.isLoggedInToCurrentServer()) {
    await _handleOfflineSubscriptions();
    return;
  }
  {
    // we need to get the last notification before we call the feed endpoint as it is going to save the last seen video
    final lastNotification = await fileDb.getLastSubscriptionNotification();
    var feed = await service.getUserFeed(maxResults: 100, saveLastSeen: false);

    List<Video> videos = [];
    videos.addAll(feed.notifications ?? []);
    videos.addAll(feed.videos ?? []);

    if (videos.isNotEmpty) {
      // we don't send notification for the first run ever to avoid weird behavior
      if (lastNotification == null) {
        // запоминаем самое свежее видео (раньше — самое старое, и следующая проверка
        // сообщала обо всей ленте как о новых)
        var toSave = SubscriptionNotification(
            videos.first.videoId, DateTime.now().millisecondsSinceEpoch);
        await fileDb.setLastSubscriptionNotification(toSave);
      } else {
        late int videosToNotifyAbout;
        int index = videos.indexWhere(
            (element) => element.videoId == lastNotification.lastSeenVideoId);
        //more than 100 videos
        if (index == -1) {
          videosToNotifyAbout = videos.length;
        } else {
          videosToNotifyAbout = index;
        }

        var locals = await getLocalization();

        if (kDebugMode || videosToNotifyAbout > 0) {
          await sendNotification(locals.subscriptionNotificationTitle,
              locals.subscriptionNotificationContent(videosToNotifyAbout),
              type: NotificationTypes.subscription,
              payload: {lastSeenVideo: videos.first.videoId});
        }
      }
    }
  }
}

/// Подписки на устройстве: у каждого канала берём последний ролик и сравниваем с прошлой
/// проверкой. Первый раз только запоминаем (иначе пришло бы уведомление обо всём сразу).
/// Не больше 60 каналов за раз и 3 запросов одновременно — бережно к YouTube и серверу.
Future<void> _handleOfflineSubscriptions() async {
  final all = (await fileDb.getOfflineSubscriptions()).toList();
  if (all.isEmpty) return;
  final seen = await fileDb.getOfflineSeen();
  // по кругу: каждый запуск — следующие 60 каналов (раньше всегда первые 60, остальные не проверялись)
  const cursorKey = '__cursor';
  final start = (int.tryParse(seen[cursorKey] ?? '') ?? 0) % all.length;
  final subs = [for (var k = 0; k < all.length && k < 60; k++) all[(start + k) % all.length]];
  seen[cursorKey] = '${(start + subs.length) % all.length}';
  final fresh = <(String channel, Video video)>[];
  var i = 0;
  Future<void> worker() async {
    while (i < subs.length) {
      final s = subs[i++];
      try {
        final v = (await service.getChannelVideos(s.channelId, null, saveLastSeen: false)).videos;
        if (v.isEmpty) continue;
        final last = seen[s.channelId];
        if (last != null && last != v.first.videoId) {
          final idx = v.indexWhere((e) => e.videoId == last);
          for (final e in v.take(idx < 0 ? 3 : idx)) {
            fresh.add((s.channelName, e));
          }
        }
        seen[s.channelId] = v.first.videoId;
      } catch (e) {
        log.info('подписка ${s.channelId}: $e');
      }
    }
  }

  await Future.wait([worker(), worker(), worker()]);
  await fileDb.setOfflineSeen(seen);
  if (fresh.isEmpty) return;
  final locals = await getLocalization();
  final title = fresh.length == 1 ? fresh.first.$1 : locals.subscriptionNotificationTitle;
  final body = fresh.length == 1
      ? (fresh.first.$2.title ?? '')
      : '${locals.subscriptionNotificationContent(fresh.length)}: ${fresh.map((e) => e.$1).toSet().take(3).join(', ')}';
  await sendNotification(title, body,
      type: NotificationTypes.subscription, payload: {lastSeenVideo: fresh.first.$2.videoId});
}
