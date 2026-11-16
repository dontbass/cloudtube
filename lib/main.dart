import 'package:clipious/cloudtube/tv_scale.dart';
import 'package:clipious/videos/models/video.dart';
import 'package:clipious/settings/models/db/server.dart';
import 'package:clipious/cloudtube/direct.dart';
import 'package:clipious/cloudtube/yt_account.dart';
import 'package:clipious/cloudtube/yt_cookies.dart';
import 'package:clipious/cloudtube/platform.dart';
import 'package:clipious/cloudtube/desktop_player.dart';
import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'cloudtube/sponsor_toast.dart';
import 'cloudtube/yt_fast.dart';
import 'cloudtube/tv_nav.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:clipious/cloudtube/theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:clipious/l10n/generated/app_localizations.dart';
import 'package:clipious/app/states/app.dart';
import 'package:clipious/downloads/states/download_manager.dart';
import 'package:clipious/globals.dart';
import 'package:clipious/home/models/db/home_layout.dart';
import 'package:clipious/http_overrides.dart';
import 'package:clipious/media_handler.dart';
import 'package:clipious/notifications/notifications.dart';
import 'package:clipious/player/states/player.dart';
import 'package:clipious/router.dart';
import 'package:clipious/settings/models/db/settings.dart';
import 'package:clipious/videos/models/sponsor_segment_types.dart';
import 'package:clipious/settings/states/settings.dart';
import 'package:clipious/utils.dart';
import 'package:clipious/utils/sembast_sqflite_database.dart';
import 'package:clipious/workmanager.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'settings/models/db/app_logs.dart';

const brandColor = Color(0xFF4f0096);

final scaffoldKey = GlobalKey<ScaffoldMessengerState>();
bool isTv = false;

late MediaHandler mediaHandler;

final Logger log = Logger('main');

Future<void> main() async {
  Logger.root.level =
      kDebugMode ? Level.FINEST : Level.INFO; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) async {
    debugPrint(
        '[${record.level.name}] [${record.loggerName}] ${record.message}');
    // we don't want debug
    if (record.level == Level.INFO || record.level == Level.SEVERE) {
      await db.insertLogs(AppLog(
          logger: record.loggerName,
          level: record.level.name,
          time: record.time,
          message: record.message,
          stacktrace: record.stackTrace?.toString()));
    }
  });

  HttpOverrides.global = MyHttpOverrides();

  WidgetsFlutterBinding.ensureInitialized();
  if (ctDesktop) CtDesktopPlayer.ensureInitialized();
  await ctInitDesktopCerts();

  packageInfo = await PackageInfo.fromPlatform();

  // FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  db = await SembastSqfDb.create();
  await fileDb.syncWithDb();

  // CloudTube: по умолчанию — проксировать видео через сервер и все категории SponsorBlock
  for (final n in [
    useProxySettingName,
    lockOrientationFullScreen,
    playerAutoplayOnLoad,
    ...SponsorSegmentType.values.map((t) => t.settingsName())
  ]) {
    if (db.getSettings(n) == null) {
      await db.saveSetting(SettingsValue(n, 'true'));
    }
  }

  ctSoftTheme.value = db.getSettings(ctSoftThemeKey)?.value == 'true';

  // автотест сборки (CI): режим без сервера и, при желании, сразу открыть видео
  if (ctDesktop && Platform.environment['CT_SMOKE_DIRECT'] == '1') {
    final s = db.getServer(kCtDirectUrl) ?? const Server(url: kCtDirectUrl);
    await db.upsertServer(s.copyWith(inUse: true));
    await db.useServer(s.copyWith(inUse: true));
    await db.saveSetting(SettingsValue('ct-onboarding-done', '1'));
    final vid = Platform.environment['CT_SMOKE_VIDEO'];
    if (vid != null && vid.isNotEmpty) {
      Future.delayed(const Duration(seconds: 12), () => CtDesktopPlayer.open(Video(videoId: vid)));
    }
  }

  late final bool hasServer;
  try {
    final cur = await db.getCurrentlySelectedServer();
    ctDirectActive = ctIsDirectUrl(cur.url);
    CtYtCookies.load();
    ctYtRefreshToken = ctDirectActive && (cur.authToken?.isNotEmpty ?? false) ? cur.authToken : null;
    hasServer = true;
  } catch (err) {
    hasServer = false;
  }
  appRouter = AppRouter(hasServer: hasServer);

  // CloudTube: уведомления и частота экрана — только Android
  isTv = await isDeviceTv();
  if (Platform.isAndroid) {
    initializeNotifications();
    // телефон: включаем 90/120 Гц. На ТВ этот запрос заставляет телевизор переключать режим
    // HDMI — экран при запуске моргал, будто меняется разрешение. Поэтому на ТВ не трогаем
    if (!isTv) {
      try {
        log.fine("Forcing refresh rate");
        await FlutterDisplayMode.setHighRefreshRate();
      } catch (err) {
        log.severe("failed to set high refresh mode", err);
      }
    }
  }

  CtYtFast.wantAdaptive = isTv;
  if (isTv) ctLoadTvScale();
  await ctSponsorDefaults();
  runApp(BetterFeedback(
    child: MultiBlocProvider(providers: [
      BlocProvider(
        create: (context) {
          return AppCubit(AppState(0, null, HomeLayout()));
        },
      ),
      BlocProvider(
        create: (context) {
          var settingsCubit =
              SettingsCubit(SettingsState.init(), context.read<AppCubit>());
          configureBackgroundService(settingsCubit);
          return settingsCubit;
        },
      ),
      BlocProvider(
        create: (context) =>
            PlayerCubit(PlayerState.init(null), context.read<SettingsCubit>()),
      ),
      BlocProvider(
        create: (context) => DownloadManagerCubit(
            const DownloadManagerState(), context.read<PlayerCubit>()),
      )
    ], child: const MyApp()),
  ));
}

late ColorScheme darkColorScheme;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
        buildWhen: (previous, current) => previous.server != current.server,
        // we want to rebuild only when anything other than the navigation index is changed
        builder: (context, state) {
          bool useBlackBackground = context
              .select((SettingsCubit value) => value.state.blackBackground);
          String? locale =
              context.select((SettingsCubit value) => value.state.locale);
          ThemeMode themeMode =
              context.select((SettingsCubit value) => value.state.themeMode);

          var navigationBarBehavior = context
              .select((SettingsCubit s) => s.state.navigationBarLabelBehavior);

          return ValueListenableBuilder<bool>(
              valueListenable: ctSoftTheme,
              builder: (context, soft, _) => DynamicColorBuilder(
              builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            // CloudTube: фиксированная палитра как у сайта (динамические цвета Android не используем)
            final ColorScheme lightColorScheme = soft ? ctSoftScheme : ctLightScheme;
            darkColorScheme = soft ? ctDimScheme : ctDarkScheme;

            if (useBlackBackground) {
              darkColorScheme = darkColorScheme.copyWith(
                  surface: Colors.black, surfaceContainerLowest: Colors.black);
            }

            List<String>? localeString;
            var dbLocale = locale;
            if (dbLocale != null && dbLocale != 'null') {
              localeString = dbLocale.split('_');
            }

            log.fine(
                'locale from db ${db.getSettings(localeSettingName)?.value} from cubit: $dbLocale, $localeString');
            Locale? savedLocale = localeString != null
                ? Locale.fromSubtags(
                    languageCode: localeString[0],
                    scriptCode:
                        localeString.length >= 2 ? localeString[1] : null)
                : null;

            var colors = getColorSchemeOutsideOfMaterial(context,
                dark: darkColorScheme, light: lightColorScheme);

            var navigationBarTheme = NavigationBarThemeData(
              elevation: 0,
              height: 60,
              backgroundColor: colors.surface,
              indicatorColor: Colors.transparent,
              labelBehavior: navigationBarBehavior,
              labelTextStyle: WidgetStatePropertyAll(
                  TextStyle(fontSize: 11, color: colors.onSurface)),
              iconTheme:
                  WidgetStatePropertyAll(IconThemeData(color: colors.onSurface)),
            );

            var navigationRailTheme = NavigationRailThemeData(
              elevation: 0,
              backgroundColor: colors.surface,
            );

            var appBarTheme = AppBarTheme(
                backgroundColor: colors.surface,
                elevation: 0,
                scrolledUnderElevation: 0,
                systemOverlayStyle: getUiOverlayStyle(context,
                    dark: darkColorScheme, light: lightColorScheme));

            var sliderTheme =
                const SliderThemeData(inactiveTrackColor: Colors.blue);

            return MaterialApp.router(
              builder: isTv ? (context, child) => CtTvScale(child: CtTvSmoothTraversal(child: child ?? const SizedBox())) : null,
              routerConfig: appRouter.config(
                  navigatorObservers: () => [MyRouteObserver()],
                  includePrefixMatches: true),
              locale: savedLocale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              localeListResolutionCallback: (locales, supportedLocales) {
                log.info(
                    'device locales=$locales supported locales=$supportedLocales, saved: $savedLocale');
                if (savedLocale != null) {
                  log.info("using saved locale, $savedLocale");
                  return savedLocale;
                }
                if (locales != null) {
                  for (Locale locale in locales) {
                    // if device language is supported by the app,
                    // just return it to set it as current app language
                    if (supportedLocales.contains(locale)) {
                      log.info("Locale match found, $locale");
                      return locale;
                    } else {
                      Locale? match = supportedLocales
                          .where((element) =>
                              element.languageCode == locale.languageCode)
                          .firstOrNull;
                      if (match != null) {
                        log.info("found partial match $locale with $match");
                        return match;
                      }
                    }
                  }
                }
                // if device language is not supported by the app,
                // the app will set it to english but return this to set to Bahasa instead
                log.info("locale not supported, returning english");
                return const Locale('en', 'US');
              },
              supportedLocales: AppLocalizations.supportedLocales,
              scaffoldMessengerKey: scaffoldKey,
              debugShowCheckedModeBanner: false,
              themeMode: ThemeMode.values.firstWhere(
                  (element) => element.name == themeMode.name,
                  orElse: () => ThemeMode.system),
              title: 'CloudTube',
              theme: ThemeData(
                  useMaterial3: true,
                  colorScheme: lightColorScheme,
                  navigationBarTheme: navigationBarTheme,
                  navigationRailTheme: navigationRailTheme,
                  appBarTheme: appBarTheme,
                  checkboxTheme: ctCheckboxTheme(lightColorScheme),
                  // ПК: заметная полоса прокрутки, которую легко поймать мышью
                  scrollbarTheme: ctDesktop
                      ? ScrollbarThemeData(
                          thumbVisibility: const WidgetStatePropertyAll(true),
                          thickness: const WidgetStatePropertyAll(10),
                          radius: const Radius.circular(8),
                          interactive: true,
                          thumbColor: WidgetStatePropertyAll(lightColorScheme.onSurfaceVariant.withValues(alpha: 0.5)))
                      : null,
                  switchTheme: ctSwitchTheme(lightColorScheme),
                  snackBarTheme: ctSnackBarTheme,
                  radioTheme: ctRadioTheme(lightColorScheme),
                  scaffoldBackgroundColor: lightColorScheme.surface,
                  sliderTheme: sliderTheme.copyWith(
                      inactiveTrackColor: lightColorScheme.secondaryContainer),
                  progressIndicatorTheme: ProgressIndicatorThemeData(
                      circularTrackColor: lightColorScheme.secondaryContainer
                          .withValues(alpha: 0.8))),
              darkTheme: ThemeData(
                  useMaterial3: true,
                  colorScheme: darkColorScheme,
                  appBarTheme: appBarTheme,
                  navigationBarTheme: navigationBarTheme,
                  navigationRailTheme: navigationRailTheme,
                  checkboxTheme: ctCheckboxTheme(darkColorScheme),
                  // ПК: заметная полоса прокрутки, которую легко поймать мышью
                  scrollbarTheme: ctDesktop
                      ? ScrollbarThemeData(
                          thumbVisibility: const WidgetStatePropertyAll(true),
                          thickness: const WidgetStatePropertyAll(10),
                          radius: const Radius.circular(8),
                          interactive: true,
                          thumbColor: WidgetStatePropertyAll(darkColorScheme.onSurfaceVariant.withValues(alpha: 0.5)))
                      : null,
                  switchTheme: ctSwitchTheme(darkColorScheme),
                  snackBarTheme: ctSnackBarTheme,
                  radioTheme: ctRadioTheme(darkColorScheme),
                  scaffoldBackgroundColor: darkColorScheme.surface,
                  sliderTheme: sliderTheme.copyWith(
                      inactiveTrackColor: darkColorScheme.secondaryContainer),
                  progressIndicatorTheme: ProgressIndicatorThemeData(
                      circularTrackColor: darkColorScheme.secondaryContainer
                          .withValues(alpha: 0.8))),
            );
          }));
        });
  }
}
