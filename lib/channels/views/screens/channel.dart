import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clipious/l10n/generated/app_localizations.dart';
import 'package:clipious/channels/states/channel.dart';

import '../../../cloudtube/ui_state.dart';
import '../../../subscription_management/view/components/subscribe_button.dart';
import '../../../utils.dart';
import '../../../utils/models/image_object.dart';
import '../../../utils/views/components/thumbnail.dart';
import '../../models/channel.dart';
import '../components/info.dart';
import 'playlists_tab.dart';
import 'shorts_tab.dart';
import 'stream_tab.dart';
import 'video_tab.dart';

/// Страница канала (телефон/планшет): шапка с аватаром и подпиской, ниже вкладки.
/// Вкладки — обычный TabBarView (свайп), без вложенного роутера Clipious.
@RoutePage()
class ChannelScreen extends StatelessWidget {
  final String channelId;

  const ChannelScreen({super.key, @pathParam required this.channelId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ChannelCubit(channelId),
      child: BlocBuilder<ChannelCubit, ChannelState>(builder: (context, s) {
        final channel = s.channel;
        return Scaffold(
          appBar: AppBar(
            title: Text(channel?.author ?? ''),
            actions: [
              if (channel != null)
                IconButton(
                    tooltip: AppLocalizations.of(context)!.share,
                    onPressed: () => showSharingSheet(context, channel),
                    icon: const Icon(Icons.share_rounded)),
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: channel != null
                ? _ChannelBody(channel: channel)
                : s.loading
                    ? const Center(child: CircularProgressIndicator())
                    : CtErrorView(
                        message: 'Не удалось открыть канал', onRetry: context.read<ChannelCubit>().load),
          ),
        );
      }),
    );
  }
}

class _ChannelBody extends StatelessWidget {
  final Channel channel;

  const _ChannelBody({required this.channel});

  @override
  Widget build(BuildContext context) {
    final locals = AppLocalizations.of(context)!;
    final tabs = <(String, Widget)>[
      (locals.videos, ChannelVideoTab(channel: channel)),
      (locals.shorts, ChannelShortsTab(channel: channel)),
      (locals.streams, ChannelStreamTab(channel: channel)),
      (locals.playlists, ChannelPlaylistsTab(channelId: channel.authorId)),
      ('О канале', ChannelInfo(channel: channel)),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Column(children: [
        ChannelHeader(channel: channel),
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerHeight: 0.5,
          tabs: [for (final t in tabs) Tab(text: t.$1)],
        ),
        Expanded(
          child: TabBarView(children: [for (final t in tabs) CtKeepAlive(child: t.$2)]),
        ),
      ]),
    );
  }
}

/// Шапка канала: аватар, название, число подписчиков, кнопка подписки.
class ChannelHeader extends StatelessWidget {
  final Channel channel;

  const ChannelHeader({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final subs = channel.subCount > 0 ? ctSubscribers(channel.subCount) : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(children: [
        Thumbnail(
            width: 64,
            height: 64,
            thumbnails: ImageObject.getThumbnailUrlsByPreferredOrder(channel.authorThumbnails),
            decoration: BoxDecoration(color: colors.secondaryContainer, shape: BoxShape.circle)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(channel.author,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            if (subs != null)
              Text(subs, style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: 8),
            SubscribeButton(channelId: channel.authorId, subCount: ''),
          ]),
        ),
      ]),
    );
  }
}

/// «1 подписчик», «3 подписчика», «25 подписчиков», «1.2M подписчиков».
String ctSubscribers(int n) {
  if (n >= 1000) return '${compactCurrency.format(n).trim()} подписчиков';
  final m10 = n % 10, m100 = n % 100;
  final w = m10 == 1 && m100 != 11
      ? 'подписчик'
      : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)
          ? 'подписчика'
          : 'подписчиков';
  return '$n $w';
}
