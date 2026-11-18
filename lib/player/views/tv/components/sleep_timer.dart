import 'package:cloudtube/player/models/sleep_timer.dart';
import 'package:cloudtube/l10n/generated/app_localizations.dart';

import 'package:cloudtube/player/states/sleep_timer.dart';
import 'package:cloudtube/player/views/tv/components/player_settings.dart';
import 'package:cloudtube/utils.dart';
import 'package:cloudtube/utils/views/tv/components/tv_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

class TvSleepTimer extends StatelessWidget {
  final Function(SleepTimer? sleepTimer) onSet;

  const TvSleepTimer({super.key, required this.onSet});

  @override
  Widget build(BuildContext context) {
    var locals = AppLocalizations.of(context)!;

    return BlocProvider(
        create: (context) =>
            SleepTimerCubit(const SleepTimer(stopVideo: false)),
        child:
            BlocBuilder<SleepTimerCubit, SleepTimer>(builder: (context, state) {
          final cubit = context.read<SleepTimerCubit>();

          var textTheme = Theme.of(context).textTheme;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  TvButton(
                    unfocusedColor: Colors.transparent,
                    onPressed: (context) => cubit.setDuration(
                        state.duration - const Duration(minutes: 1)),
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(Icons.remove),
                    ),
                  ),
                  const Gap(16),
                  Text(
                    prettyDurationCustom(state.duration),
                    style: textTheme.bodyLarge,
                  ),
                  const Gap(16),
                  TvButton(
                    unfocusedColor: Colors.transparent,
                    onPressed: (context) => cubit.setDuration(
                        state.duration + const Duration(minutes: 1)),
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(Icons.add),
                    ),
                  )
                ],
              ),
              TvSettingButton(
                label: locals.setTimer,
                onPressed: (selected) {
                  onSet(state);
                },
              )
            ],
          );
        }));
  }
}
