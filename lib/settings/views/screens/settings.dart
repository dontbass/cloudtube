import 'package:clipious/cloudtube/connect_screen.dart';
import 'package:clipious/cloudtube/connect.dart';
import 'package:clipious/cloudtube/direct.dart';
import 'package:clipious/cloudtube/theme.dart';
import 'package:clipious/cloudtube/updater.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clipious/l10n/generated/app_localizations.dart';
import 'package:clipious/app/states/app.dart';
import 'package:clipious/router.dart';
import 'package:clipious/utils/views/components/app_icon.dart';
import 'package:settings_ui/settings_ui.dart';

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
          _CtCard(
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
          _CtCard(
            icon: Icons.video_settings,
            title: locals.videoPlayer,
            subtitle: 'Качество, субтитры, SponsorBlock, автозапуск',
            onTap: () => router.push(const VideoPlayerSettingsRoute()),
          ),
          _CtCard(
            icon: Icons.home_outlined,
            title: locals.browsing,
            subtitle: 'Разделы, страна и язык, фильтры, история поиска',
            onTap: () => router.push(const BrowsingSettingsRoute()),
          ),
          _CtCard(
            icon: Icons.palette_outlined,
            title: locals.appearance,
            subtitle: 'Тема и панель навигации',
            onTap: () => router.push(const AppearanceSettingsRoute()),
          ),
          _CtCard(
            icon: Icons.cloud_queue,
            title: locals.manageServers,
            subtitle: server != null && !ctDirectActive ? server.url : 'Свой сервер Invidious не подключён',
            onTap: () => router.push(const ManageServersRoute()),
          ),
          _CtCard(
            icon: Icons.notifications_outlined,
            title: locals.notifications,
            subtitle: state.backgroundNotifications ? 'Включены' : 'Новые видео с подписок',
            onTap: () => router.push(const NotificationSettingsRoute()),
          ),
        ];
        final about = <Widget>[
          _CtCard(
            icon: Icons.system_update_outlined,
            title: 'Проверить обновления',
            subtitle: 'Установлена версия ${state.packageInfo.version}',
            onTap: () => CtUpdater.check(ctx, manual: true),
          ),
          _CtCard(
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

class _CtCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CtCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accent = ctAccent(colors);
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          // крупная цель для пальца — удобно и на экране в машине
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }
}
