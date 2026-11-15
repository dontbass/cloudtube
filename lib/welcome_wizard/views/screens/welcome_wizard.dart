import 'package:clipious/cloudtube/connect.dart';
import 'package:clipious/cloudtube/deploy.dart';
import 'package:clipious/cloudtube/connect_screen.dart';
import 'package:clipious/cloudtube/theme.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clipious/l10n/generated/app_localizations.dart';
import 'package:clipious/app/states/app.dart';
import 'package:clipious/router.dart';
import 'package:clipious/settings/states/server_list_settings.dart';
import 'package:clipious/settings/views/components/manager_server_inner.dart';
import 'package:clipious/utils/views/components/app_icon.dart';
import 'package:clipious/welcome_wizard/states/welcome_wizard.dart';

import '../../../settings/models/db/server.dart';

@RoutePage()
class WelcomeWizardScreen extends StatelessWidget {
  const WelcomeWizardScreen({super.key});

  void _toMain(BuildContext context) => AutoRouter.of(context).replace(const MainRoute());

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget choice(IconData icon, String title, String text, VoidCallback onTap, {bool primary = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Material(
            color: primary ? CtColors.logoRed.withValues(alpha: 0.12) : colors.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                        color: primary ? CtColors.logoRed : colors.surfaceContainerHighest, shape: BoxShape.circle),
                    child: Icon(icon, color: primary ? Colors.white : colors.onSurface),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(text, style: TextStyle(color: colors.onSurfaceVariant, height: 1.3)),
                    ]),
                  ),
                  Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
                ]),
              ),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 20), shrinkWrap: true, children: [
              const Center(child: SizedBox(width: 110, height: 110, child: AppIcon())),
              const SizedBox(height: 10),
              Text('CloudTube',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Видео без рекламы и слежки — через ваш сервер Invidious.',
                  textAlign: TextAlign.center, style: textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant)),
              const SizedBox(height: 28),
              choice(Icons.play_circle_outline, 'Смотреть сразу',
                  'YouTube напрямую — ничего настраивать не нужно. Подписки и история хранятся на устройстве',
                  () async {
                await ctConnectDirect(context.read<AppCubit>());
                if (context.mounted) _toMain(context);
              }, primary: true),
              choice(Icons.dns_outlined, 'У меня есть сервер', 'Введите адрес, пароль сайта и аккаунт — и всё готово',
                  () async {
                final ok = await Navigator.of(context)
                    .push<bool>(MaterialPageRoute(builder: (_) => const CtConnectScreen()));
                if (ok == true && context.mounted) _toMain(context);
              }),
              choice(Icons.rocket_launch_outlined, 'Развернуть свой сервер',
                  'Нужен VPS и домен — приложение само всё установит за 10–15 минут', () async {
                final ok = await Navigator.of(context)
                    .push<bool>(MaterialPageRoute(builder: (_) => const CtDeployScreen()));
                if (ok == true && context.mounted) _toMain(context);
              }),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _ServerList())),
                child: const Text('Публичные серверы и расширенные настройки'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Прежний экран Clipious: публичные серверы, свои заголовки, пропуск проверки SSL.
class _ServerList extends StatelessWidget {
  const _ServerList();

  @override
  Widget build(BuildContext context) {
    var locals = AppLocalizations.of(context)!;
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => WelcomeWizardCubit(null)),
        BlocProvider(
          create: (context) => ServerListSettingsCubit(
              const ServerListSettingsState(publicServers: [], dbServers: []), context.read<AppCubit>()),
        )
      ],
      child: BlocListener<ServerListSettingsCubit, ServerListSettingsState>(
        listener: (context, state) => context.read<WelcomeWizardCubit>().getSelectedServer(),
        child: BlocBuilder<WelcomeWizardCubit, Server?>(
          builder: (context, server) => Scaffold(
            appBar: AppBar(title: const Text('Серверы')),
            body: SafeArea(
              child: Column(children: [
                Padding(padding: const EdgeInsets.all(8.0), child: Text(locals.wizardIntro)),
                const Expanded(child: ManagerServersView(fromWizard: true)),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: FilledButton.tonal(
                      onPressed: server != null
                          ? () => AutoRouter.of(context).replaceAll([const MainRoute()])
                          : null,
                      child: Text(locals.startUsingClipious)),
                )
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
