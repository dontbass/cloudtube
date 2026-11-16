import '../../../../cloudtube/updater.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clipious/l10n/generated/app_localizations.dart';
import 'package:clipious/app/states/tv_home.dart';
import 'package:clipious/globals.dart';
import 'package:clipious/settings/states/settings.dart';
import 'package:clipious/utils/models/paginated_list.dart';
import 'package:clipious/utils/views/tv/components/tv_button.dart';
import 'package:clipious/utils/views/tv/components/tv_overscan.dart';
import 'package:clipious/videos/views/components/subscriptions.dart';
import 'package:clipious/videos/views/components/trending.dart';

import '../../../../home/models/db/home_layout.dart';
import '../../../../router.dart';
import '../../../../utils/views/components/app_icon.dart';
import '../../../../cloudtube/tv_link.dart';
import '../../../../cloudtube/direct.dart';
import '../../../../cloudtube/tv_nav.dart';
import 'package:clipious/utils/views/tv/components/tv_horizontal_item_list.dart';
import '../../../../cloudtube/home_feed.dart';
import '../../../../cloudtube/yt_login.dart';
import '../../../../videos/views/components/popular.dart';
import '../../../states/app.dart';

const overlayBackgroundOpacity = 0.8;
const double overlayBlur = 25.0;
GlobalKey popularTitle = GlobalKey(debugLabel: 'popular title');
GlobalKey subscriptionTitle = GlobalKey(debugLabel: 'subscription title');
DateTime _ctLastBack = DateTime(2000);
GlobalKey? _ctCurRow;

/// Вертикальная прокрутка к ряду — только при смене ряда. Раньше она запускалась на КАЖДОМ
/// ролике при движении вправо-влево и спорила с горизонтальной прокруткой — отсюда рывки.
void ctTvScrollToRow(GlobalKey? key) {
  if (key == null || identical(key, _ctCurRow)) return;
  final ctx = key.currentContext;
  if (ctx == null) return;
  _ctCurRow = key;
  // как в SmartTube: выбранный ряд всегда встаёт вверху экрана, плавно
  Scrollable.ensureVisible(ctx,
      alignment: 0.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic);
}

final _ctRowKeys = {for (final c in ctSections.skip(1)) c.id: GlobalKey(debugLabel: 'row ${c.id}')};

/// Ряды разделов (Музыка, Новости, Спорт…) под основными лентами стартового экрана.
List<Widget> _ctSectionRows(BuildContext context) {
  final textTheme = Theme.of(context).textTheme;
  final colors = Theme.of(context).colorScheme;
  return [
    for (final (i, c) in ctSections.skip(1).where((c) => c.id != 'movies').indexed)
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            key: _ctRowKeys[c.id],
            padding: const EdgeInsets.only(top: 10.0, bottom: 6, left: 4),
            child: Text(c.label, style: textTheme.titleMedium!.copyWith(color: colors.onSurfaceVariant)),
          ),
          TvHorizontalVideoList(
            // разделы грузятся после главной и подписок, по очереди
            paginatedVideoList: ctSectionList(c.id, fill: false, delay: Duration(milliseconds: 100 + 250 * i)),
            autoFocusedIndex: -1,
            onItemFocus: (video, index, focus) {
              if (focus) ctTvScrollToRow(_ctRowKeys[c.id]);
            },
          ),
        ],
      ),
  ];
}
GlobalKey trendingTitle = GlobalKey(debugLabel: 'trending title');

@RoutePage()
class TvHomeScreen extends StatelessWidget {
  const TvHomeScreen({super.key});

  openSettings(BuildContext context) {
    AutoRouter.of(context).push(const TVSettingsRoute());
  }

  openPopular(BuildContext context) {
    var locals = AppLocalizations.of(context)!;
    AutoRouter.of(context).push(TvGridRoute(
        paginatedVideoList: ctSectionList(''),
        title: locals.home));
  }

  openTrending(BuildContext context) {
    var locals = AppLocalizations.of(context)!;
    AutoRouter.of(context).push(TvGridRoute(
        paginatedVideoList: SingleEndpointList(service.getTrending),
        title: locals.trending));
  }

  openSubscriptions(BuildContext context) {
    var locals = AppLocalizations.of(context)!;
    AutoRouter.of(context).push(TvGridRoute(
        paginatedVideoList: SubscriptionVideoList(),
        title: locals.subscriptions));
  }

  openSearch(BuildContext context) {
    AutoRouter.of(context).push(const TvSearchRoute());
  }

  openPlaylists(BuildContext context) {
    AutoRouter.of(context).push(TvPlaylistGridRoute(
        playlistList: SingleEndpointList(service.getUserPlaylists)));
  }

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    TextTheme textTheme = Theme.of(context).textTheme;
    var locals = AppLocalizations.of(context)!;
    return _CtTvStartup(
      child: PopScope(
      // выход из приложения — двойным «Назад», как в SmartTube
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        if (now.difference(_ctLastBack) < const Duration(milliseconds: 2500)) {
          SystemNavigator.pop();
          return;
        }
        _ctLastBack = now;
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              content: Text('Нажмите «Назад» ещё раз для выхода', textAlign: TextAlign.center),
              behavior: SnackBarBehavior.floating,
              width: 420,
              duration: Duration(milliseconds: 2500)));
      },
      child: Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
      },
      child: BlocProvider(
        create: (BuildContext context) => TvHomeCubit(false),
        child: Scaffold(
          body: BlocBuilder<TvHomeCubit, bool>(builder: (context, homeState) {
            var homeCubit = context.read<TvHomeCubit>();
            var appLayout =
                context.select((SettingsCubit value) => value.state.appLayout);
            var isLoggedIn =
                context.select((AppCubit value) => value.isLoggedIn);
            var allowedPages = appLayout
                .where((element) => element.isPermitted(context, isLoggedIn))
                .toList();
            return BlocBuilder<AppCubit, AppState>(
                buildWhen: (previous, current) {
              return previous.server != current.server;
            }, builder: (context, state) {
              return DefaultTextStyle(
                style: textTheme.bodyLarge!,
                child: Stack(
                  children: [
                    Positioned.fill(
                      // CloudTube: стрелка влево у левого края открывает боковое меню
                      // ленты — отдельный виджет: открытие меню и переходы по нему больше не
                      // перерисовывают все ряды с картинками (раньше это давало подтормаживания)
                      child: const _CtTvRows(),
                    ),
                    Positioned(
                      left: 0, top: 0, bottom: 0,
                      child: AnimatedContainer(
                      width: homeState ? 236 : 0,
                      duration: animationDuration ~/ 2,
                      curve: Curves.easeInOutQuad,
                      decoration: BoxDecoration(
                          color: colors.surfaceContainer.withValues(alpha: 0.97),
                          boxShadow: const [BoxShadow(blurRadius: 24, color: Colors.black54)]),
                      // меню как в SmartTube: скрыто, выезжает поверх лент по стрелке «влево»
                      child: ClipRect(child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: 236,
                          maxWidth: 236,
                          child: Padding(
                          padding: EdgeInsets.only(
                              top: TvOverscan.vertical,
                              left: 16,
                              bottom: TvOverscan.vertical,
                              right: 10),
                          child: FocusScope(
                              // закрытое меню не участвует в переходах стрелками: «влево» по роликам
                              // ведёт к соседнему ролику, а меню открывается только с края ряда.
                              // Сама область меню (во всю высоту) тоже не цель для стрелок — иначе
                              // «вниз» с верхнего ряда иногда уходило в меню
                              node: ctTvMenuScope..descendantsAreTraversable = homeState,
                              skipTraversal: true,
                              // стрелка вправо из меню — обратно к роликам, туда, откуда пришли
                              onKeyEvent: (node, e) {
                                if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowRight) {
                                  final back = ctTvLastContent;
                                  if (back != null && back.context != null && back.canRequestFocus) {
                                    back.requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  // некуда вернуться (вернулись с другого экрана, старт приложения) —
                                  // первый видимый ролик слева сверху
                                  final first = ctTvFirstVisibleContent();
                                  if (first != null) {
                                    first.requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                }
                                return KeyEventResult.ignored;
                              },
                              child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 18.0),
                                  child: SizedBox(
                                      height: 40,
                                      child: Row(
                                        children: [
                                          const AppIcon(
                                            width: 40,
                                            height: 40,
                                          ),
                                          if (homeState)
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    left: 16.0),
                                                child: MenuItemText(
                                                  'CloudTube',
                                                  style: textTheme.titleLarge!
                                                      .copyWith(
                                                          color:
                                                              colors.primary),
                                                ))
                                        ],
                                      )),
                                ),
                                Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: allowedPages
                                        .map(
                                          (e) => Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 4.0),
                                            child: TvButton(
                                              onFocusChanged: homeCubit
                                                  .menuItemFocusChanged,
                                              onPressed: (context) =>
                                                  switch (e) {
                                                (HomeDataSource.search) =>
                                                  openSearch(context),
                                                (HomeDataSource.subscription) =>
                                                  openSubscriptions(context),
                                                (HomeDataSource.playlist) =>
                                                  openPlaylists(context),
                                                (HomeDataSource.trending) =>
                                                  openTrending(context),
                                                (HomeDataSource.popular) =>
                                                  openPopular(context),
                                                (_) => const SizedBox.shrink()
                                              },
                                              unfocusedColor: colors
                                                  .secondaryContainer
                                                  .withValues(alpha: 0.0),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                                child: Row(
                                                  children: [
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              right: 8.0),
                                                      child: Icon(e.getIcon()),
                                                    ),
                                                    if (homeState)
                                                      MenuItemText(
                                                          e.getLabel(locals))
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList()),
                                TvButton(
                                  onFocusChanged:
                                      homeCubit.menuItemFocusChanged,
                                  onPressed: (context) => Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => ctDirectActive ? const CtYtLoginScreen() : const CtTvLinkScreen())),
                                  unfocusedColor: colors.secondaryContainer
                                      .withValues(alpha: 0.0),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    child: Row(
                                      children: [
                                        const Padding(
                                          padding: EdgeInsets.only(right: 8.0),
                                          child: Icon(Icons.qr_code_2),
                                        ),
                                        if (homeState)
                                          MenuItemText(ctDirectActive ? 'Вход в YouTube' : 'Вход с телефона')
                                      ],
                                    ),
                                  ),
                                ),
                                TvButton(
                                  onFocusChanged:
                                      homeCubit.menuItemFocusChanged,
                                  onPressed: (context) => openSettings(context),
                                  unfocusedColor: colors.secondaryContainer
                                      .withValues(alpha: 0.0),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    child: Row(
                                      children: [
                                        const Padding(
                                          padding: EdgeInsets.only(right: 8.0),
                                          child: Icon(Icons.settings),
                                        ),
                                        if (homeState)
                                          MenuItemText(locals.settings)
                                      ],
                                    ),
                                  ),
                                )
                              ]))))),
                    ),
                    ),
                  ],
                ),
              );
            });
          }),
        ),
      ),
    )));
  }
}

/// Ряды стартового экрана ТВ (перерисовываются только при смене раскладки, входа или сервера).
class _CtTvRows extends StatelessWidget {
  const _CtTvRows();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final locals = AppLocalizations.of(context)!;
    final homeCubit = context.read<TvHomeCubit>();
    final appLayout = context.select((SettingsCubit value) => value.state.appLayout);
    final isLoggedIn = context.select((AppCubit value) => value.isLoggedIn);
    context.select((AppCubit value) => value.state.server);
    final allowedPages = appLayout.where((element) => element.isPermitted(context, isLoggedIn)).toList();
    return Focus(
                      focusNode: ctTvContentArea,
                      canRequestFocus: false,
                      skipTraversal: true,
                      child: CtTvLeftEdge(
                      popRoute: false,
                      // terrible work around to be able to scroll to all the global keys
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.only(
                              top: TvOverscan.vertical,
                              bottom: TvOverscan.vertical,
                              right: TvOverscan.horizontal,
                              left: TvOverscan.horizontal),
                          child: ListView(
                            controller: homeCubit.scrollController,
                            physics: const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            // crossAxisAlignment: CrossAxisAlignment.start,
                            children: [...allowedPages
                                .where((e) =>
                                    e == HomeDataSource.subscription ||
                                    e == HomeDataSource.trending ||
                                    e == HomeDataSource.popular)
                                .map((e) {
                              GlobalKey? key = switch (e) {
                                (HomeDataSource.popular) => popularTitle,
                                (HomeDataSource.subscription) =>
                                  subscriptionTitle,
                                (HomeDataSource.trending) => trendingTitle,
                                (_) => null,
                              };

                              focusFunction(video, index, focus) {
                                if (focus) ctTvScrollToRow(key);
                              }

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    key: key,
                                    padding: const EdgeInsets.only(top: 10.0, bottom: 6, left: 4),
                                    child: Text(e.getLabel(locals),
                                        style: textTheme.titleMedium!.copyWith(color: colors.onSurfaceVariant)),
                                  ),
                                  switch (e) {
                                    (HomeDataSource.popular) => Popular(
                                        onItemFocus: focusFunction,
                                      ),
                                    (HomeDataSource.subscription) =>
                                      Subscriptions(
                                        onItemFocus: focusFunction,
                                      ),
                                    (HomeDataSource.trending) => Trending(
                                        onItemFocus: focusFunction,
                                      ),
                                    (_) => const SizedBox.shrink(),
                                  }
                                ],
                              );
                            }),
                              // ещё ленты разделов, как в SmartTube: экран заполнен, вниз — новые ряды
                              ..._ctSectionRows(context),
                            ],
                          ),
                        ),
                      )));
  }
}

class MenuItemText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const MenuItemText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      // компактное меню: всё, включая «Вход в YouTube», помещается в одну строку
      style: style ?? const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
    )
        .animate()
        .fadeIn(delay: const Duration(milliseconds: 50), duration: const Duration(milliseconds: 110))
        .slideX(curve: Curves.easeOutCubic, duration: const Duration(milliseconds: 160));
  }
}


/// Проверка обновления приложения после запуска (как на телефоне).
class _CtTvStartup extends StatefulWidget {
  final Widget child;

  const _CtTvStartup({required this.child});

  @override
  State<_CtTvStartup> createState() => _CtTvStartupState();
}

class _CtTvStartupState extends State<_CtTvStartup> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) CtUpdater.check(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}


/// Область бокового меню ТВ (чтобы открыть его стрелкой влево с левого края контента).
final ctTvMenuScope = FocusScopeNode(debugLabel: 'ct-tv-menu');

/// Ролик, с которого ушли в меню (чтобы стрелкой вправо вернуться к нему).
FocusNode? ctTvLastContent;

/// Область лент стартового экрана.
final ctTvContentArea = FocusNode(debugLabel: 'ct-tv-content', canRequestFocus: false, skipTraversal: true);

/// Первый видимый ролик (верхний ряд, левее всех).
FocusNode? ctTvFirstVisibleContent() {
  FocusNode? best;
  for (final n in ctTvContentArea.descendants) {
    if (n is FocusScopeNode || !n.canRequestFocus || n.skipTraversal || n.context == null) continue;
    final r = n.rect;
    if (r.isEmpty || r.bottom < 0) continue;
    if (best == null ||
        r.top < best.rect.top - 8 ||
        ((r.top - best.rect.top).abs() <= 8 && r.left < best.rect.left)) {
      best = n;
    }
  }
  return best;
}

void ctOpenTvMenu() {
  if (ctTvMenuScope.focusedChild != null) {
    ctTvMenuScope.focusedChild!.requestFocus();
  } else {
    // закрытое меню исключено из обхода стрелками — фокусируем первый пункт напрямую
    final first = ctTvMenuScope.descendants
        .where((n) => n is! FocusScopeNode && n.canRequestFocus && n.context != null)
        .firstOrNull;
    if (first != null) {
      first.requestFocus();
    } else {
      ctTvMenuScope.requestFocus();
    }
  }
}
