import 'package:auto_route/auto_route.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:back_button_interceptor/back_button_interceptor.dart';
import 'package:flutter/material.dart';
import 'package:clipious/cloudtube/updater.dart';
import 'package:clipious/cloudtube/theme_button.dart';
import 'package:clipious/cloudtube/onboarding.dart';
import 'package:clipious/main.dart' show isTv;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clipious/l10n/generated/app_localizations.dart';
import 'package:clipious/app/states/app.dart';
import 'package:clipious/downloads/views/components/download_app_bar_button.dart';
import 'package:clipious/globals.dart';
import 'package:clipious/home/models/db/home_layout.dart';
import 'package:clipious/router.dart';
import 'package:clipious/settings/states/settings.dart';
import 'package:clipious/utils.dart';
import 'package:clipious/utils/views/components/app_icon.dart';
import 'package:logging/logging.dart';
import 'package:clipious/cloudtube/logo.dart';
import 'package:clipious/cloudtube/theme.dart';
import 'package:flutter/services.dart';
import 'package:clipious/cloudtube/shorts.dart';
import 'package:clipious/cloudtube/shorts_icon.dart';
import 'package:clipious/cloudtube/you.dart';

import '../../../notifications/notifications.dart';

var log = Logger('Home Screen');

@RoutePage()
class MainContentScreen extends StatefulWidget {
  const MainContentScreen({super.key});

  @override
  State<MainContentScreen> createState() => _MainScreenState();
}

/// В Shorts нижнее меню всегда тёмное, как в YouTube, даже в светлой теме.
Widget _ctNavTheme(BuildContext context, bool dark, Widget nav) {
  if (!dark) return nav;
  final t = Theme.of(context);
  return Theme(
    data: t.copyWith(
      colorScheme: ctDarkScheme,
      navigationBarTheme: t.navigationBarTheme.copyWith(
        backgroundColor: Colors.black,
        indicatorColor: Colors.transparent,
        iconTheme: const WidgetStatePropertyAll(IconThemeData(color: Colors.white)),
        labelTextStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 11, color: Colors.white)),
      ),
    ),
    child: nav,
  );
}

class _MainScreenState extends State<MainContentScreen> {
  // CloudTube: нижнее меню как в YouTube — 0 Главная, 1 Shorts, 2 Подписки, 3 Вы
  int _ct = 0;
  bool _railExtended = false;

  openSettings(BuildContext context) {
    AutoRouter.of(context).push(const SettingsRoute());
  }

  openSubscriptionManagement(BuildContext context) {
    AutoRouter.of(context).push(const ManageSubscriptionsRoute());
  }

  openLayoutEditor(BuildContext context) {
    var app = context.read<AppCubit>();
    AutoRouter.of(context)
        .push(const EditHomeLayoutRoute())
        .then((value) => app.updateLayout());
  }

  @override
  void initState() {
    super.initState();
    // CloudTube: проверка обновления приложения через несколько секунд после запуска
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) CtUpdater.check(context);
    });
    // CloudTube: гид и тур при первом запуске (телефоны и планшеты)
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && !isTv) CtOnboarding.maybeStart(context);
    });

    // Only after at least the action method is set, the notification events are delivered
    AwesomeNotifications()
        .setListeners(
            onActionReceivedMethod:
                NotificationController.onActionReceivedMethod,
            onNotificationCreatedMethod:
                NotificationController.onNotificationCreatedMethod,
            onNotificationDisplayedMethod:
                NotificationController.onNotificationDisplayedMethod,
            onDismissActionReceivedMethod:
                NotificationController.onDismissActionReceivedMethod)
        .then(
      (value) {
        AwesomeNotifications()
            .getInitialNotificationAction()
            .then((initialNotification) {
          log.fine('Initial notification ${initialNotification?.payload}');

          if (initialNotification != null) {
            NotificationController.onActionReceivedMethod(initialNotification);
          }
        });
      },
    );
  }

  @override
  void dispose() {
    BackButtonInterceptor.removeByName('mainNavigator');
    super.dispose();
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    ColorScheme colorScheme = Theme.of(context).colorScheme;
    var locals = AppLocalizations.of(context)!;

    return BlocBuilder<AppCubit, AppState>(buildWhen: (previous, current) {
      return previous.server != current.server;
    }, builder: (context, appState) {
      var app = context.read<AppCubit>();
      var settings = context.watch<SettingsCubit>().state;

      var allowedPages = settings.appLayout
          .where((element) =>
              element.isPermitted(context, app.isLoggedIn) &&
              element.route != null)
          .toList();
      var navigationWidgets = allowedPages
          .map((e) => e.getBottomBarNavigationWidget(context))
          .toList();

      var selectedIndex = appState.firstIndex;
      if (selectedIndex >= allowedPages.length) {
        selectedIndex = 0;
      }

      final deviceType = getDeviceType();

      return allowedPages.isEmpty
          ? Scaffold(
              body: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Center(
                      child: AppIcon(
                    width: 150,
                    height: 150,
                  )),
                  FilledButton.tonalIcon(
                      onPressed: () => openSettings(context),
                      icon: const Icon(Icons.settings),
                      label: Text(locals.settings))
                ],
              ),
            )
          : AutoTabsRouter.tabBar(
              key: ValueKey(appState.server?.url),
              homeIndex: selectedIndex,
              routes: allowedPages.map((e) => e.route!).toList(),
              physics: const NeverScrollableScrollPhysics(),
              builder: (context, child, controller) {
                final tabsRouter = AutoTabsRouter.of(context);
                final selectedPage = allowedPages[tabsRouter.activeIndex];
                final homeIdx = allowedPages.indexOf(HomeDataSource.popular);
                final subsIdx =
                    allowedPages.indexOf(HomeDataSource.subscription);
                final ctPhone = deviceType == DeviceType.phone;
                // широкий экран (ПК, планшет в альбомной): шапка и меню как на сайте
                final ctWide = !ctPhone && MediaQuery.of(context).size.width >= 900;
                return Scaffold(
                    // so we rebuild the view if the server changes
                    backgroundColor:
                        _ct == 1 ? Colors.black : colorScheme.surface,
                    bottomNavigationBar: ctPhone
                        ? _ctNavTheme(context, _ct == 1, KeyedSubtree(key: CtTourKeys.navBar, child: NavigationBar(
                            labelBehavior: NavigationDestinationLabelBehavior
                                .alwaysShow,
                            selectedIndex: _ct,
                            onDestinationSelected: (i) {
                              setState(() => _ct = i);
                              if (i == 0 && homeIdx >= 0) {
                                tabsRouter.setActiveIndex(homeIdx);
                              } else if (i == 2 && subsIdx >= 0) {
                                tabsRouter.setActiveIndex(subsIdx);
                              }
                            },
                            destinations: const [
                              NavigationDestination(
                                  icon: Icon(Icons.home_outlined),
                                  selectedIcon: Icon(Icons.home),
                                  label: 'Главная'),
                              NavigationDestination(
                                  icon: CtShortsIcon(),
                                  selectedIcon: CtShortsIcon(filled: true),
                                  label: 'Shorts'),
                              NavigationDestination(
                                  icon: Icon(Icons.subscriptions_outlined),
                                  selectedIcon: Icon(Icons.subscriptions),
                                  label: 'Подписки'),
                              NavigationDestination(
                                  icon: Icon(Icons.account_circle_outlined),
                                  selectedIcon: Icon(Icons.account_circle),
                                  label: 'Вы'),
                            ],
                          )))
                        : null,
                    appBar: ctPhone && _ct == 1
                        ? null
                        : AppBar(
                      titleSpacing: ctWide ? 4 : 12,
                      leading: ctWide
                          ? IconButton(
                              tooltip: 'Меню',
                              icon: const Icon(Icons.menu),
                              onPressed: () => setState(() => _railExtended = !_railExtended))
                          : null,
                      title: ctWide
                          ? Row(children: [
                              const CtLogo(),
                              const Spacer(),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 560),
                                child: SizedBox(
                                  width: MediaQuery.of(context).size.width * 0.38,
                                  height: 42,
                                  child: Material(
                                    color: colorScheme.surfaceContainerHigh,
                                    shape: const StadiumBorder(),
                                    child: InkWell(
                                      customBorder: const StadiumBorder(),
                                      onTap: () => AutoRouter.of(context).push(SearchRoute()),
                                      child: Row(children: [
                                        const SizedBox(width: 16),
                                        Icon(Icons.search, color: colorScheme.onSurfaceVariant),
                                        const SizedBox(width: 10),
                                        Text('Искать',
                                            style: TextStyle(
                                                fontSize: 15, color: colorScheme.onSurfaceVariant)),
                                      ]),
                                    ),
                                  ),
                                ),
                              ),
                              const Spacer(),
                            ])
                          : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ctPhone && _ct == 3
                              ? const Text('Вы')
                              : selectedPage == HomeDataSource.popular
                                  ? const CtLogo()
                                  : Text(selectedPage.getLabel(locals)),
                          if (selectedPage == HomeDataSource.home)
                            IconButton(
                                iconSize: 15,
                                onPressed: () => openLayoutEditor(context),
                                icon: Icon(
                                  Icons.edit,
                                  color: colorScheme.secondary,
                                ))
                        ],
                      ),
                      actions: [
                        selectedPage == HomeDataSource.subscription
                            ? IconButton(
                                onPressed: () =>
                                    openSubscriptionManagement(context),
                                icon: const Icon(Icons.checklist))
                            : const SizedBox.shrink(),
                        KeyedSubtree(key: CtTourKeys.theme, child: const CtThemeButton()),
                        const AppBarDownloadButton(),
                        if (!ctWide) IconButton(
                          key: CtTourKeys.search,
                          onPressed: () {
                            AutoRouter.of(context).push(SearchRoute());
                          },
                          icon: const Icon(Icons.search),
                        ),
                        if (!ctPhone)
                          IconButton(
                            tooltip: 'Вы',
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => Scaffold(
                                    appBar: AppBar(title: const Text('Вы')),
                                    body: const Center(
                                        child: SizedBox(width: 720, child: CtYouPage()))))),
                            icon: const Icon(Icons.account_circle_outlined),
                          ),
                        IconButton(
                          onPressed: () => openSettings(context),
                          icon: const Icon(Icons.settings),
                        ),
                      ],
                    ),
                    body: ctPhone && _ct == 1
                        ? const AnnotatedRegion<SystemUiOverlayStyle>(
                            value: SystemUiOverlayStyle(
                                statusBarColor: Colors.black,
                                statusBarIconBrightness: Brightness.light,
                                statusBarBrightness: Brightness.dark,
                                systemNavigationBarColor: Colors.black,
                                systemNavigationBarIconBrightness:
                                    Brightness.light),
                            child: SafeArea(
                                bottom: false, child: CtShortsPage()))
                        : ctPhone && _ct == 3
                        ? const CtYouPage()
                        : Row(
                      children: [
                        if (deviceType == DeviceType.tablet &&
                            allowedPages.length > 2)
                          OrientationBuilder(
                            builder: (context, orientation) => NavigationRail(
                                extended: ctWide
                                    ? _railExtended
                                    : getOrientation() == Orientation.landscape,
                                labelType: ctWide && !_railExtended
                                    ? NavigationRailLabelType.all
                                    : null,
                                minWidth: ctWide ? 72 : null,
                                onDestinationSelected:
                                    tabsRouter.setActiveIndex,
                                destinations: allowedPages
                                    .map((e) =>
                                        e.getNavigationRailWidget(context))
                                    .toList(),
                                selectedIndex: tabsRouter.activeIndex),
                          ),
                        Expanded(
                          child: Container(
                              // home handles its own padding because we don't want to cut horizontal scroll lists on the right
                              padding: EdgeInsets.symmetric(
                                  horizontal:
                                      selectedPage == HomeDataSource.home ||
                                              selectedPage ==
                                                  HomeDataSource.popular ||
                                              selectedPage ==
                                                  HomeDataSource.subscription ||
                                              selectedPage ==
                                                  HomeDataSource.history
                                          ? 0
                                          : innerHorizontalPadding),
                              child: child),
                        ),
                      ],
                    ));
              });
    });
  }
}
