import 'package:cloudtube/cloudtube/theme.dart';
import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloudtube/l10n/generated/app_localizations.dart';
import 'package:cloudtube/settings/states/server_list_settings.dart';
import 'package:cloudtube/settings/views/components/manager_server_inner.dart';

import '../../../app/states/app.dart';

@RoutePage()
class ManageServersScreen extends StatefulWidget {
  const ManageServersScreen({super.key});

  @override
  ManageServerState createState() => ManageServerState();
}

class ManageServerState extends State<ManageServersScreen> {
  @override
  Widget build(BuildContext context) {
    var locals = AppLocalizations.of(context)!;
    ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
        appBar: AppBar(
          title: Text(locals.manageServers),
        ),
        backgroundColor: ctBg(colorScheme),
        body: SafeArea(
            bottom: false,
            child: BlocProvider(
                create: (BuildContext context) => ServerListSettingsCubit(
                    const ServerListSettingsState(
                        dbServers: [], publicServers: []),
                    context.read<AppCubit>()),
                child: const ManagerServersView())));
  }
}
