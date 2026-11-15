import 'package:clipious/cloudtube/connect.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clipious/l10n/generated/app_localizations.dart';
import 'package:clipious/app/states/app.dart';
import 'package:clipious/router.dart';
import 'package:clipious/settings/views/tv/components/manage_server_inner.dart';
import 'package:clipious/utils/views/tv/components/tv_button.dart';
import 'package:clipious/utils/views/tv/components/tv_overscan.dart';
import 'package:clipious/welcome_wizard/states/welcome_wizard.dart';
import 'package:clipious/cloudtube/tv_link.dart';

import '../../../../settings/models/db/server.dart';
import '../../../../settings/states/server_list_settings.dart';

@RoutePage()
class TvWelcomeWizardScreen extends StatelessWidget {
  const TvWelcomeWizardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    var locals = AppLocalizations.of(context)!;
    ColorScheme colors = Theme.of(context).colorScheme;
    TextTheme textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: TvOverscan(
        child: MultiBlocProvider(
          providers: [
            BlocProvider(create: (context) => WelcomeWizardCubit(null)),
            BlocProvider(
              create: (context) => ServerListSettingsCubit(
                  const ServerListSettingsState(
                      publicServers: [], dbServers: []),
                  context.read<AppCubit>()),
            )
          ],
          child: BlocListener<ServerListSettingsCubit, ServerListSettingsState>(
            listener: (context, state) {
              context.read<WelcomeWizardCubit>().getSelectedServer();
            },
            child: BlocBuilder<WelcomeWizardCubit, Server?>(
                builder: (context, server) {
              return DefaultTextStyle(
                style: textTheme.bodyLarge!,
                child: Column(
                  children: [
                    Text(
                      locals.wizardIntro,
                      style: textTheme.titleLarge,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TvButton(
                        autofocus: true,
                        onPressed: (context) async {
                          await ctConnectDirect(context.read<AppCubit>());
                          if (context.mounted) AutoRouter.of(context).replace(const TvHomeRoute());
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.play_circle_outline),
                            const SizedBox(width: 12),
                            Text('Смотреть сразу — без сервера', style: textTheme.titleLarge),
                          ]),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: TvButton(
                        onPressed: (context) => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => CtTvLinkScreen(
                                onDone: (c) => AutoRouter.of(context).replace(const TvHomeRoute())))),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.qr_code_2),
                            const SizedBox(width: 12),
                            Text('Настроить с телефона — QR-код', style: textTheme.titleLarge),
                          ]),
                        ),
                      ),
                    ),
                    const Expanded(child: TvManageServersInner()),
                    TvButton(
                      unfocusedColor: server == null ? colors.surface : null,
                      onPressed: server != null
                          ? (context) {
                              AutoRouter.of(context)
                                  .replace(const TvHomeRoute());
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          locals.startUsingClipious,
                          style: textTheme.titleLarge!.copyWith(
                              color: server == null
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : Colors.white),
                        ),
                      ),
                    )
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
