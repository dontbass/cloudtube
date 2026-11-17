import 'package:clipious/cloudtube/connect_screen.dart';
import 'package:clipious/cloudtube/connect.dart';
import 'package:clipious/cloudtube/direct.dart';
import 'package:clipious/cloudtube/theme.dart';
import 'package:clipious/cloudtube/updater.dart';
import 'package:clipious/cloudtube/ui_card.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clipious/l10n/generated/app_localizations.dart';
import 'package:clipious/app/states/app.dart';
import 'package:clipious/router.dart';
import 'package:clipious/utils/views/components/app_icon.dart';
import 'package:clipious/cloudtube/settings_ui.dart';

import '../../states/settings.dart';

/// Оформление вложенных экранов настроек (плеер, просмотр, внешний вид…) в цветах CloudTube.
settingsTheme(ColorScheme colorScheme) => SettingsThemeData(
    settingsSectionBackground: colorScheme.surface,
    settingsListBackground: colorScheme.surface,
    titleTextColor: ctAccent(colorScheme),
    dividerColor: colorScheme.outlineVariant,
    tileDescriptionTextColor: colorScheme.onSurfaceVariant,
    leadingIconsColor: ctAccent(colorScheme),
    tileHighlightColor: colorScheme.secondaryContainer);

/// Главный экран настроек (телефон, планшет, магнитола): крупные карточки с иконкой и короткой
/// подписью; на широком экране — в две колонки. Заменил список Clipious.
@RoutePage()
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final locals = AppLocalizations.of(context)!;
    final router = AutoRouter.of(context);

    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (ctx, state) {
        final server = ctx.select((AppCubit a) => a.state.server);
        final cards = <Widget>[
          CtCard(
            icon: Icons.swap_horiz,
            title: 'Режим работы',
            subtitle: ctDirectActive ? 'Сейчас: без сервера, YouTube напрямую' : 'Сейчас: свой сервер',
            onTap: () async {
              if (ctDirectActive) {
                await Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const CtConnectScreen()));
              } else {
                await ctConnectDirect(ctx.read<AppCubit>());
              }
              if (ctx.mounted) (ctx as Element).markNeedsBuild();
            },
          ),
          CtCard(
            icon: Icons.video_settings,
            title: locals.videoPlayer,
            subtitle: 'Качество, субтитры, SponsorBlock, автозапуск',
            onTap: () => router.push(const VideoPlayerSettingsRoute()),
          ),
          CtCard(
            icon: Icons.home_outlined,
            title: locals.browsing,
            subtitle: 'Разделы, страна и язык, фильтры, история поиска',
            onTap: () => router.push(const BrowsingSettingsRoute()),
          ),
          CtCard(
            icon: Icons.palette_outlined,
            title: locals.appearance,
            subtitle: 'Тема, чёрный фон, подписи вкладок',
            onTap: () => router.push(const AppearanceSettingsRoute()),
          ),
          CtCard(
            icon: Icons.cloud_queue,
            title: locals.manageServers,
            subtitle: server != null && !ctDirectActive ? server.url : 'Свой сервер Invidious не подключён',
            onTap: () => router.push(const ManageServersRoute()),
          ),
          CtCard(
            icon: Icons.notifications_outlined,
            title: locals.notifications,
            subtitle: state.backgroundNotifications ? 'Включены' : 'Новые видео с подписок',
            onTap: () => router.push(const NotificationSettingsRoute()),
          ),
        ];
        final about = <Widget>[
          CtCard(
            icon: Icons.system_update_outlined,
            title: 'Проверить обновления',
            subtitle: 'Установлена версия ${state.packageInfo.version}',
            onTap: () => CtUpdater.check(ctx, manual: true),
          ),
          CtCard(
            icon: Icons.toc,
            title: locals.appLogs,
            subtitle: 'Пригодится, если что-то работает не так',
            onTap: () => router.push(const AppLogsRoute()),
          ),
        ];

        return Scaffold(
          appBar: AppBar(title: Text(locals.settings)),
          backgroundColor: colors.surface,
          body: SafeArea(
            child: LayoutBuilder(builder: (context, c) {
              // магнитола и планшет — две колонки, телефон — одна
              final cols = c.maxWidth >= 680 ? 2 : 1;
              const gap = 12.0;
              final w = (c.maxWidth - 32 - gap * (cols - 1)) / cols;
              Widget grid(List<Widget> items) => Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [for (final i in items) SizedBox(width: w, child: i)]);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  grid(cards),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
                    child: Row(children: [
                      const SizedBox(width: 36, height: 36, child: AppIcon()),
                      const SizedBox(width: 12),
                      Text('CloudTube ${state.packageInfo.version}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Text('сборка ${state.packageInfo.buildNumber}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                    ]),
                  ),
                  grid(about),
                ],
              );
            }),
          ),
        );
      },
    );
  }
}
