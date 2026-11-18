import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloudtube/l10n/generated/app_localizations.dart';
import 'package:cloudtube/settings/models/db/settings.dart';
import 'package:cloudtube/settings/states/settings.dart';
import 'package:cloudtube/settings/views/tv/screens/settings.dart';
import 'package:cloudtube/utils/views/tv/components/tv_overscan.dart';

import '../../../../videos/models/sponsor_segment_types.dart';

@RoutePage()
class TvSponsorBlockSettingsScreen extends StatelessWidget {
  const TvSponsorBlockSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations locals = AppLocalizations.of(context)!;
    return Scaffold(
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          var cubit = context.read<SettingsCubit>();
          return TvOverscan(
            child: CtTvTileScope(child: ListView(
              children: ctTvTiles([
                SettingsTitle(
                    title: locals.sponsorBlockSettingsQuickDescription),
                ...SponsorSegmentType.values.map((t) {
                  bool value =
                      state.settings[t.settingsName()]?.value == 'true';
                  return SettingsTile(
                    trailing: Switch(value: value, onChanged: (value) {}),
                    onSelected: (context) => cubit.saveSetting(
                        SettingsValue(t.settingsName(), (!value).toString())),
                    title: SponsorSegmentType.getLabel(t, locals),
                    description: SponsorSegmentType.getDescription(t, locals),
                  );
                })
              ]),
            )),
          );
        },
      ),
    );
  }
}
