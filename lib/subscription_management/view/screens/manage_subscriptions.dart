import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloudtube/router.dart';
import 'package:cloudtube/utils.dart';

import '../../../cloudtube/avatars.dart';
import '../../../cloudtube/theme.dart';
import '../../../cloudtube/ui_state.dart';
import '../../states/manage_subscriptions.dart';

/// Мои подписки: один список (аккаунт + устройство), поиск по названию,
/// отписка с «Отменить», нажатие — страница канала.
@RoutePage()
class ManageSubscriptionsScreen extends StatelessWidget {
  const ManageSubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ManageSubscriptionCubit(),
      child: BlocBuilder<ManageSubscriptionCubit, ManageSubscriptionsState>(builder: (context, s) {
        final cubit = context.read<ManageSubscriptionCubit>();
        return Scaffold(
          appBar: AppBar(title: Text(s.subs.isEmpty ? 'Подписки' : 'Подписки · ${s.subs.length}')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: tabletMaxVideoWidth),
                child: _body(context, s, cubit),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _body(BuildContext context, ManageSubscriptionsState s, ManageSubscriptionCubit cubit) {
    if (s.subs.isEmpty) {
      if (s.loading) return const Center(child: CircularProgressIndicator());
      if (s.error != null && !s.isLoggedIn) return CtErrorView(message: s.error!, onRetry: cubit.refreshSubs);
      return const CtEmptyView(
          icon: Icons.subscriptions_outlined,
          text: 'Подписок пока нет.\nНажмите «Подписаться» на странице канала или ролика.');
    }
    final list = s.visible;
    return RefreshIndicator(
      onRefresh: cubit.refreshSubs,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: cubit.setQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Найти канал',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
        if (s.error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Text(s.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ),
        if (s.loading) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
        if (list.isEmpty)
          const SliverFillRemaining(
              hasScrollBody: false, child: CtEmptyView(icon: Icons.search_off_rounded, text: 'Ничего не найдено')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
          sliver: SliverList.builder(
            itemCount: list.length,
            itemBuilder: (context, i) => _SubTile(key: ValueKey(list[i].id), sub: list[i], showSource: s.isLoggedIn),
          ),
        ),
      ]),
    );
  }
}

class _SubTile extends StatelessWidget {
  final CtSub sub;
  final bool showSource;

  const _SubTile({super.key, required this.sub, required this.showSource});

  Future<void> _unsubscribe(BuildContext context) async {
    final cubit = context.read<ManageSubscriptionCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Отписаться от «${sub.name}»?'),
        content: const Text('Ролики канала пропадут из «Подписок». Подписаться снова можно в любой момент.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Отписаться')),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await cubit.unsubscribe(sub);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(ok
        ? SnackBar(
            content: Text('Вы отписались от «${sub.name}»'),
            action: SnackBarAction(label: 'Отменить', onPressed: () => cubit.restore(sub)))
        : const SnackBar(content: Text('Аккаунт не ответил — попробуйте ещё раз')));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final source = sub.account && sub.device
        ? 'аккаунт и устройство'
        : sub.account
            ? 'аккаунт'
            : 'на устройстве';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: CtChannelAvatar(channelId: sub.id, author: sub.name, size: 44),
      title: Text(sub.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: showSource
          ? Text(source, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant))
          : null,
      onTap: () => AutoRouter.of(context)
          .push(ChannelRoute(channelId: sub.id))
          .then((_) => context.mounted ? context.read<ManageSubscriptionCubit>().refreshSubs() : null),
      trailing: IconButton(
        tooltip: 'Отписаться',
        onPressed: () => _unsubscribe(context),
        icon: Icon(Icons.person_remove_alt_1_outlined, color: ctAccent(colors)),
      ),
    );
  }
}
