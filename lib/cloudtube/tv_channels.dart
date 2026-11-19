import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../globals.dart';
import '../router.dart';
import '../subscription_management/states/subscribe_button.dart';
import '../subscription_management/view/components/subscribe_button.dart';
import '../utils/views/tv/components/tv_button.dart';

/// ТВ: переход на канал, подписка и ряд подписанных каналов — общие кусочки
/// для плиток, плеера и экрана «Подписки».

void ctOpenTvChannel(BuildContext context, String channelId) {
  if (channelId.isEmpty) return;
  AutoRouter.of(context).push(TvChannelRoute(channelId: channelId));
}

/// Все подписки: аккаунт (если вошли) + на устройстве, без повторов, по алфавиту.
Future<List<(String, String)>> ctSubscribedChannels() async {
  final out = <String, String>{};
  try {
    if (await service.isLoggedIn()) {
      for (final s in await service.getSubscriptions()) {
        out[s.authorId] = s.author;
      }
    }
  } catch (_) {}
  try {
    for (final o in await db.getOfflineSubscriptions()) {
      out.putIfAbsent(o.channelId, () => o.channelName);
    }
  } catch (_) {}
  final list = [for (final e in out.entries) (e.key, e.value)];
  list.sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
  return list;
}

/// Кнопка «Подписаться / Вы подписаны» для пульта.
class CtTvSubscribeChip extends StatelessWidget {
  final String channelId;
  final bool autofocus;

  const CtTvSubscribeChip({super.key, required this.channelId, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SubscribeButtonCubit(SubscribeButtonState.init(channelId)),
      child: BlocBuilder<SubscribeButtonCubit, SubscribeButtonState>(builder: (context, s) {
        final cubit = context.read<SubscribeButtonCubit>();
        return CtTvChip(
          autofocus: autofocus,
          icon: s.loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(s.isSubscribed ? Icons.done_rounded : Icons.add_rounded, size: 26),
          label: s.isSubscribed ? 'Вы подписаны' : 'Подписаться',
          onPressed: (ctx) {
            if (s.loading) return;
            if (s.isSubscribed) {
              cubit.unsubscribe();
            } else {
              SubscribeButton.showSubscriptionSheet(ctx);
            }
          },
        );
      }),
    );
  }
}

/// Пилюля «значок + текст» для ТВ.
class CtTvChip extends StatelessWidget {
  final Widget icon;
  final String label;
  final void Function(BuildContext context) onPressed;
  final bool autofocus;

  const CtTvChip({super.key, required this.icon, required this.label, required this.onPressed, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    return TvButton(
      autofocus: autofocus,
      unfocusedColor: Colors.white.withValues(alpha: 0.12),
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          icon,
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// Меню ролика на ТВ (долгое нажатие ОК или кнопка «Меню»): смотреть, канал, подписка.
Future<void> ctShowTvVideoMenu(BuildContext context,
    {required String title, required String author, required String channelId, required VoidCallback onPlay}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final text = Theme.of(ctx).textTheme;
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleLarge),
              const SizedBox(height: 18),
              CtTvChip(
                  autofocus: true,
                  icon: const Icon(Icons.play_arrow_rounded, size: 26),
                  label: 'Смотреть',
                  onPressed: (_) {
                    Navigator.of(ctx).pop();
                    onPlay();
                  }),
              if (channelId.isNotEmpty) ...[
                const SizedBox(height: 10),
                CtTvChip(
                    icon: const Icon(Icons.account_circle_outlined, size: 26),
                    label: author.isEmpty ? 'Канал автора' : 'Канал: $author',
                    onPressed: (_) {
                      Navigator.of(ctx).pop();
                      ctOpenTvChannel(context, channelId);
                    }),
                const SizedBox(height: 10),
                CtTvSubscribeChip(channelId: channelId),
              ],
            ]),
          ),
        ),
      );
    },
  );
}
