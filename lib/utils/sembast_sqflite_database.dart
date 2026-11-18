import 'package:cloudtube/cloudtube/platform.dart';
import 'package:cloudtube/globals.dart' show fileDb;
import 'package:sembast/sembast_io.dart';
import 'dart:async';
import 'dart:io';

import 'package:cloudtube/downloads/models/downloaded_video.dart';
import 'package:cloudtube/home/models/db/home_layout.dart';
import 'package:cloudtube/offline_subscriptions/models/offline_subscription.dart';
import 'package:cloudtube/search/models/db/search_history_item.dart';
import 'package:cloudtube/settings/models/db/app_logs.dart';
import 'package:cloudtube/settings/models/db/server.dart';
import 'package:cloudtube/settings/models/db/settings.dart';
import 'package:cloudtube/settings/models/db/video_filter.dart';
import 'package:cloudtube/utils/interfaces/db.dart';
import 'package:cloudtube/videos/models/db/dearrow_cache.dart';
import 'package:cloudtube/videos/models/db/history_video_cache.dart';
import 'package:cloudtube/videos/models/db/progress.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast_sqflite/sembast_sqflite.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:uuid/uuid.dart';

import '../settings/states/settings.dart';

const maxLogs = 1000;
const singleId = 1;

class SembastSqfDb extends IDbClient {
  final log = Logger('SembastSqfLDB');
  final Database db;
  final downloadedVideosStore = stringMapStoreFactory.store('downloadedVideo');
  final homeLayoutStore =
      intMapStoreFactory.store('homeLayout'); // always use id = 1
  final searchHistoryStore =
      stringMapStoreFactory.store('searchHistory'); // use term as key
  final appLogsStore = stringMapStoreFactory.store('appLogs');
  final serversStore =
      stringMapStoreFactory.store('serviers'); // use server url as key
  final videoFiltersStore = stringMapStoreFactory.store('videoFilters');
  final settingsStore =
      stringMapStoreFactory.store('settings'); // settings name as key;
  final deArrowCacheStore =
      stringMapStoreFactory.store('dearrow'); // use video id as key
  final historyVideoCacheStore =
      stringMapStoreFactory.store('historyVideoCache'); // use historyVideoCache
  final progressStore = stringMapStoreFactory.store('progress');
  final offlineSubscriptions =
      stringMapStoreFactory.store('offline_subscriptions');

  SembastSqfDb(this.db);

  static Future<SembastSqfDb> create() async {
    final Directory docsDir = await ctDataDir();

    var dbPath = p.join(docsDir.path, "clipious.db");

    // CloudTube: на ПК — обычный файл sembast (sqflite там без ffi не работает)
    if (ctDesktop) {
      await docsDir.create(recursive: true);
      final db = await databaseFactoryIo.openDatabase(p.join(docsDir.path, "cloudtube.db"), version: 1);
      return SembastSqfDb(db);
    }

    final databaseFactorySqflite =
        getDatabaseFactorySqflite(sqflite.databaseFactory);
    var db = await databaseFactorySqflite.openDatabase(
      dbPath.toString(),
      version: 1,
    );

    return SembastSqfDb(db);
  }

  static Future<SembastSqfDb> createInMemory() async {
    var factory = newDatabaseFactoryMemory();
    var db = await factory.openDatabase("${const Uuid().v4()}.db");
    return SembastSqfDb(db);
  }

  @override
  Future<void> addToSearchHistory(SearchHistoryItem searchHistoryItem) async {
    searchHistoryItem.time = DateTime.now().millisecondsSinceEpoch;
    await searchHistoryStore
        .record(searchHistoryItem.search)
        .put(db, searchHistoryItem.toJson());
    await clearExcessSearchHistory();
  }

  @override
  Future<void> deleteFromSearchHistory(String search) async {
    await searchHistoryStore.record(search).delete(db);
  }

  /// Ограничение роста базы. sembast при запуске читает базу в память целиком, поэтому
  /// записи о позиции просмотра, кэш истории и DeArrow, копившиеся годами без предела,
  /// замедляли запуск. Оставляем самые свежие.
  Future<void> trimCaches() async {
    Future<void> trim(StoreRef<String, Map<String, Object?>> store, int keep, String? timeField) async {
      final all = await store.find(db);
      if (all.length <= keep) return;
      int t(RecordSnapshot<String, Map<String, Object?>> r) {
        final v = timeField == null ? null : r.value[timeField];
        if (v is int) return v;
        if (v is String) return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
        return 0;
      }

      final sorted = List.of(all)..sort((a, b) => t(a).compareTo(t(b)));
      final drop = sorted.take(all.length - keep).map((r) => r.key).toList();
      await store.records(drop).delete(db);
      log.info('База: ${store.name} — удалено ${drop.length} старых записей из ${all.length}');
    }

    await trim(progressStore, 3000, 't');
    await trim(historyVideoCacheStore, 1000, 'created');
    await trim(deArrowCacheStore, 1000, null);
  }

  @override
  Future<void> cleanOldLogs() async {
    // TODO: implement cleanOldLogs
    var all = getAppLogs();
    List<String> ids = all.reversed.skip(maxLogs).map((e) => e.uuid).toList();
    await appLogsStore.delete(db,
        finder: Finder(
            sortOrders: [SortOrder("time")], offset: 0, limit: ids.length));
    log.fine("clearing ${ids.length} logs out of ${all.length}");
  }

  @override
  Future<void> clearExcessSearchHistory() async {
    final limit = int.parse(getSettings(searchHistoryLimitSettingName)?.value ??
        searchHistoryDefaultLength);

    log.fine('History limit ? $limit');

    var count = searchHistoryStore.countSync(db);
    log.fine('search history clear $count/$limit');
    if (count > limit) {
      await searchHistoryStore.delete(db,
          finder: Finder(
              sortOrders: [SortOrder("time")],
              offset: 0,
              limit: count - limit));
      log.fine('clearing ${count - limit} history itens');
    }
  }

  @override
  Future<void> clearSearchHistory() async {
    // TODO: implement clearSearchHistory
    await searchHistoryStore.delete(db);
  }

  @override
  close() async {
    await db.close();
  }

  @override
  Future<void> deleteDownload(DownloadedVideo vid) async {
    await downloadedVideosStore.record(vid.videoId).delete(db);
  }

  @override
  Future<void> deleteFilter(VideoFilter filter) async {
    await videoFiltersStore.record(filter.uuid).delete(db);
  }

  @override
  deleteServerById(Server server) async {
    await serversStore.record(server.url).delete(db);
  }

  @override
  deleteSetting(String name) async {
    await settingsStore.record(name).delete(db);
  }

  @override
  List<DownloadedVideo> getAllDownloads() {
    var records = downloadedVideosStore.findSync(db);
    return records.map((e) {
      var d = DownloadedVideo.fromJson(e.value);
      d = d.copyWith(videoId: e.key);
      return d;
    }).toList();
  }

  @override
  List<VideoFilter> getAllFilters() {
    return videoFiltersStore
        .findSync(db)
        .map((e) => VideoFilter.fromJson(e.value)..uuid = e.key)
        .toList();
  }

  @override
  List<SettingsValue> getAllSettings() {
    return settingsStore
        .findSync(db)
        .map((e) => SettingsValue.fromJson(e.value))
        .toList();
  }

  @override
  List<AppLog> getAppLogs() {
    return appLogsStore
        .findSync(db)
        .map((e) => AppLog.fromJson(e.value)..uuid = e.key)
        .toList();
  }

  @override
  DeArrowCache? getDeArrowCache(String videoId) {
    var v = deArrowCacheStore.record(videoId).getSync(db);

    return v != null ? DeArrowCache.fromJson(v) : null;
  }

  @override
  DownloadedVideo? getDownloadByVideoId(String videoId) {
    var v = downloadedVideosStore.record(videoId).getSync(db);
    return v != null ? DownloadedVideo.fromJson(v) : null;
  }

  @override
  HistoryVideoCache? getHistoryVideoByVideoId(String videoId) {
    var v = historyVideoCacheStore.record(videoId).getSync(db);
    return v != null ? HistoryVideoCache.fromJson(v) : null;
  }

  @override
  HomeLayout getHomeLayout() {
    var findFirstSync = homeLayoutStore.findFirstSync(db);
    if (findFirstSync != null) {
      return HomeLayout.fromJson(findFirstSync.value);
    } else {
      return HomeLayout();
    }
  }

  @override
  List<String> getSearchHistory() {
    var list = searchHistoryStore
        .findSync(db)
        .map((e) => SearchHistoryItem.fromJson(e.value))
        .toList();
    list.sort((a, b) => b.time.compareTo(a.time));
    return list.map((e) => e.search).toList();
  }

  @override
  Server? getServer(String url) {
    var v = serversStore.record(url).getSync(db);
    return v != null ? Server.fromJson(v) : null;
  }

  @override
  Future<List<Server>> getServers() async {
    return (await serversStore.find(db))
        .map((e) => Server.fromJson(e.value))
        .toList();
  }

  @override
  SettingsValue? getSettings(String name) {
    var v = settingsStore.record(name).getSync(db);
    return v != null ? SettingsValue.fromJson(v) : null;
  }

  @override
  double getVideoProgress(String videoId) {
    var v = progressStore.record(videoId).getSync(db);
    return v != null ? Progress.fromJson(v).progress : 0;
  }

  @override
  Future<void> insertLogs(AppLog log) async {
    log.uuid = const Uuid().v4();
    await appLogsStore.add(db, log.toJson());
    super.insertLogs(log);
  }

  @override
  Future<void> saveFilter(VideoFilter filter) async {
    if (filter.uuid == VideoFilter(value: "").uuid) {
      // generate new id
      filter.uuid = const Uuid().v4();
    }
    await videoFiltersStore.record(filter.uuid).put(db, filter.toJson());
  }

  @override
  saveProgress(Progress progress) async {
    // 't' — когда смотрели: по нему чистим самые старые записи (см. trimCaches)
    await progressStore
        .record(progress.videoId)
        .put(db, {...progress.toJson(), 't': DateTime.now().millisecondsSinceEpoch});
  }

  @override
  saveSetting(SettingsValue setting) async {
    await settingsStore.record(setting.name).put(db, setting.toJson());
  }

  @override
  Future<void> upsertDeArrowCache(DeArrowCache cache) async {
    await deArrowCacheStore.record(cache.videoId).put(db, cache.toJson());
  }

  @override
  Future<void> upsertDownload(DownloadedVideo vid) async {
    await downloadedVideosStore.record(vid.videoId).put(db, vid.toJson());
  }

  @override
  Future<void> upsertHistoryVideo(HistoryVideoCache vid) async {
    await historyVideoCacheStore.record(vid.videoId).put(db, vid.toJson());
  }

  @override
  Future<void> upsertHomeLayout(HomeLayout layout) async {
    await homeLayoutStore.record(singleId).put(db, layout.toJson());
  }

  @override
  Future<void> upsertServer(Server server) async {
    await serversStore.record(server.url).put(db, server.toJson());
    await super.upsertServer(server);
    // копия текущего сервера для фоновой проверки уведомлений — теперь всегда здесь,
    // а не вручную в десятке мест (где её легко было забыть)
    if (server.inUse) await _mirror(server);
  }

  @override
  Future<void> useServer(Server server) async {
    List<Server> servers = List.from(await getServers());
    for (int i = 0; i < servers.length; i++) {
      Server s = servers[i].copyWith(inUse: false);
      await serversStore.record(s.url).put(db, s.toJson());
    }

    await serversStore
        .record(server.url)
        .put(db, server.copyWith(inUse: true).toJson());
    await _mirror(server.copyWith(inUse: true));
  }

  Future<void> _mirror(Server s) async {
    try {
      await fileDb.useServer(s);
    } catch (e) {
      log.fine('файловая копия сервера: $e');
    }
  }

  @override
  Future<void> addOfflineSubscription(OfflineSubscription sub) async {
    await offlineSubscriptions.record(sub.channelId).put(db, sub.toJson());
    await _mirrorSubs();
  }

  @override
  Future<void> deleteOfflineSubscription(String channelId) async {
    await offlineSubscriptions.record(channelId).delete(db);
    await _mirrorSubs();
  }

  /// Копия подписок на устройстве для фоновой проверки новых видео.
  Future<void> _mirrorSubs() async {
    try {
      await fileDb.setOfflineSubscriptions(await getOfflineSubscriptions());
    } catch (e) {
      log.fine('файловая копия подписок: $e');
    }
  }

  @override
  Future<List<OfflineSubscription>> getOfflineSubscriptions() {
    return offlineSubscriptions.find(db).then((values) =>
        values.map((e) => OfflineSubscription.fromJson(e.value)).toList());
  }

  @override
  Future<bool> isOfflineSubscribed(String channelId) {
    return offlineSubscriptions.record(channelId).exists(db);
  }
}
