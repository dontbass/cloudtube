import 'package:clipious/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clipious/l10n/generated/app_localizations.dart';
import 'package:clipious/subscription_management/states/subscribe_button.dart';

import '../../../notifications/views/components/bell_icon.dart';

class SubscribeButton extends StatelessWidget {
  final String channelId;
  final String subCount;

  const SubscribeButton(
      {super.key, required this.channelId, required this.subCount});

  static showSubscriptionSheet(BuildContext context) {
    final cubit = context.read<SubscribeButtonCubit>();
    final locals = AppLocalizations.of(context)!;

    if (cubit.state.isLoggedIn) {
      showSafeModalBottomSheet(
        context: context,
        builder: (context) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (cubit.state.isLoggedIn)
                TextButton(
                    onPressed: () async {
                      await cubit.setAccountSubscription(true);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: Text(locals.invidiousAccount)),
              TextButton(
                  onPressed: () async {
                    await cubit.setOfflineSubscription(true);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Text(locals.onDeviceSubscriptions)),
              if (cubit.state.isLoggedIn)
                TextButton(
                    onPressed: () async {
                      await Future.wait<void>([
                        cubit.setOfflineSubscription(true),
                        cubit.setAccountSubscription(true)
                      ]);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: Text(locals.both)),
            ],
          );
        },
      );
    } else {
      cubit.setOfflineSubscription(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    var locals = AppLocalizations.of(context)!;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BlocProvider(
          create: (context) =>
              SubscribeButtonCubit(SubscribeButtonState.init(channelId)),
          child: BlocBuilder<SubscribeButtonCubit, SubscribeButtonState>(
            builder: (context, state) {
              var cubit = context.read<SubscribeButtonCubit>();
              final label = state.isSubscribed ? locals.subscribed : locals.subscribe;
              final text = subCount.isEmpty ? label : '$label · $subCount';
              final icon = state.loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(state.isSubscribed ? Icons.done_rounded : Icons.add_rounded, size: 20);
              void tap() => state.isSubscribed ? cubit.unsubscribe() : showSubscriptionSheet(context);
              const shape = StadiumBorder();
              const pad = EdgeInsets.symmetric(horizontal: 16);
              // подписан — спокойная кнопка, не подписан — акцентная
              return SizedBox(
                  height: 38,
                  child: state.isSubscribed
                      ? FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(shape: shape, padding: pad),
                          onPressed: tap,
                          icon: icon,
                          label: Text(text))
                      : FilledButton.icon(
                          style: FilledButton.styleFrom(shape: shape, padding: pad),
                          onPressed: tap,
                          icon: icon,
                          label: Text(text)));
            },
          ),
        ),
        BellIcon(
          itemId: channelId,
          type: BellIconType.channel,
        )
      ],
    );
  }
}
