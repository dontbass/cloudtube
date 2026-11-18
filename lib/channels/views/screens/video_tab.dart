import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloudtube/channels/models/channel_sort_by.dart';
import 'package:cloudtube/l10n/generated/app_localizations.dart';

import '../../../globals.dart';
import '../../models/channel.dart';
import '../../states/channel.dart';
import '../components/videos.dart';

/// Вкладка «Видео»: сортировка чипами над списком.
@RoutePage()
class ChannelVideoTab extends StatelessWidget {
  final Channel? channel;

  const ChannelVideoTab({super.key, this.channel});

  @override
  Widget build(BuildContext context) {
    final c = channel;
    if (c == null) return const SizedBox.shrink();
    final locals = AppLocalizations.of(context)!;
    final cubit = context.read<ChannelCubit>();
    final sortBy = context.select((ChannelCubit x) => x.state.sortBy);
    return Column(children: [
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: [
            for (final v in ChannelSortBy.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(v.getLabel(locals)),
                  selected: v == sortBy,
                  showCheckmark: false,
                  onSelected: (_) => cubit.onSortByChanged(v),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: ChannelVideosView(
          key: ValueKey(sortBy),
          channel: c,
          getVideos: (id, continuation) => service.getChannelVideos(id, continuation, sortBy: sortBy),
        ),
      ),
    ]);
  }
}
