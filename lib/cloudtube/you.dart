import 'package:auto_route/auto_route.dart';
import 'package:cloudtube/app/states/app.dart';
import 'package:cloudtube/globals.dart';
import 'package:cloudtube/home/models/db/home_layout.dart';
import 'package:cloudtube/router.dart';
import 'package:cloudtube/settings/models/db/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'updater.dart';
import 'direct.dart';
import 'mode_switch.dart';
import 'connect_screen.dart';
import 'deploy.dart';
import 'onboarding.dart';
import 'yt_login.dart';
import 'yt_cookies.dart';
import 'platform.dart';
import '../main.dart' show isTv;
import 'theme.dart';
import 'ui_card.dart';

/// Вкладка «Профиль»: аккаунт (вход/выход), история, плейлисты, загрузки, подписки, настройки.
class CtYouPage extends StatelessWidget {
  const CtYouPage({super.key});

  static Future<void> login(BuildContext context) async {
    final app = context.read<AppCubit>();
    final user = TextEditingController();
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Вход в аккаунт'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Логин и пароль вашего аккаунта CloudTube (тот же, что на сайте).',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
              controller: user,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Логин')),
          TextField(
              controller: pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Пароль')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Войти')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      Server s = await db.getCurrentlySelectedServer();
      final cookie = await service.loginWithCookies(s.url, user.text.trim(), pass.text,
          headers: s.customHeaders);
      s = s.copyWith(sidCookie: cookie);
      await db.upsertServer(s);
      app.setServer(s);
      messenger.showSnackBar(const SnackBar(content: Text('Вы вошли в аккаунт')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось войти: $e')));
    }
  }

  static Future<void> logout(BuildContext context) async {
    final app = context.read<AppCubit>();
    Server s = await db.getCurrentlySelectedServer();
    s = s.copyWith(sidCookie: null, authToken: null);
    await db.upsertServer(s);
    app.setServer(s);
  }

  void _open(BuildContext context, String title, Widget body) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (c) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: body),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final loggedIn = context.select((AppCubit a) => a.isLoggedIn);
    final server = context.select((AppCubit a) => a.state.server);
    final direct = ctIsDirectUrl(server?.url);
    final accent = ctAccent(colors);

    // шапка: кто вы и куда подключены — в той же карточке, что и остальное
    final header = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.16), shape: BoxShape.circle),
            child: Icon(loggedIn ? Icons.person : Icons.person_outline, color: accent, size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  direct
                      ? (loggedIn ? 'Аккаунт YouTube' : 'Без входа')
                      : (loggedIn ? 'Аккаунт сервера' : 'Без входа'),
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Row(children: [
                Icon(direct ? Icons.play_circle_outline : Icons.dns_outlined,
                    size: 16, color: colors.onSurfaceVariant),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                      direct ? 'YouTube напрямую' : (server?.url.replaceFirst('https://', '') ?? ''),
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                ),
              ]),
            ]),
          ),
        ]),
        if (server != null) ...[
          const SizedBox(height: 14),
          // режим работы — одним нажатием, без захода в настройки
          const CtModeSwitch(),
        ],
        if (!loggedIn) ...[
          const SizedBox(height: 12),
          Text(
              direct
                  ? 'Войдите в аккаунт YouTube — будут ваши рекомендации, подписки и история. '
                      'Вход кодом с телефона или компьютера, как на телевизоре.'
                  : 'Войдите, чтобы видеть свои подписки, историю и плейлисты.',
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.login),
            style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: () => direct
                ? Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CtYtLoginScreen()))
                : login(context),
            label: Text(direct ? 'Войти в аккаунт YouTube' : 'Войти в аккаунт'),
          ),
        ],
      ]),
    );

    final mine = <Widget>[
      if (loggedIn) ...[
        CtCard(
            icon: Icons.history,
            title: 'История',
            subtitle: 'Что вы смотрели',
            onTap: () => _open(context, 'История', HomeDataSource.history.build(context, false))),
        if (!direct)
          CtCard(
              icon: Icons.playlist_play,
              title: 'Плейлисты',
              subtitle: 'Ваши подборки видео',
              onTap: () => _open(context, 'Плейлисты', HomeDataSource.playlist.build(context, false))),
        CtCard(
            icon: Icons.subscriptions_outlined,
            title: 'Подписки на каналы',
            subtitle: 'Список каналов, отписаться',
            onTap: () => AutoRouter.of(context).push(const ManageSubscriptionsRoute())),
      ],
      if (direct && !isTv && !ctDesktop)
        CtCard(
            icon: Icons.forum_outlined,
            title: 'Аккаунт для комментариев',
            subtitle: CtYtCookies.active
                ? 'Пишете как: ${CtYtCookies.identity?.name ?? 'основной канал'}'
                : 'Вход через сайт Google — чтобы писать комментарии',
            onTap: () async {
              await CtYtCookies.manage(context);
              if (context.mounted) (context as Element).markNeedsBuild();
            }),
      CtCard(
          icon: Icons.download_outlined,
          title: 'Загрузки',
          subtitle: 'Видео для просмотра без интернета',
          onTap: () => AutoRouter.of(context).push(const DownloadManagerRoute())),
    ];

    final watch = <Widget>[
      if (server != null && !direct)
        CtCard(
            icon: Icons.dns_outlined,
            title: 'Сервер и пароль сайта',
            subtitle: server.url.replaceFirst('https://', ''),
            onTap: () => AutoRouter.of(context).push(ManageSingleServerRoute(server: server))),
      if (direct)
        CtCard(
            icon: Icons.add_link,
            title: 'Подключить другой сервер',
            subtitle: 'Адрес своего Invidious и пароль сайта',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CtConnectScreen()))),
      CtCard(
          icon: Icons.rocket_launch_outlined,
          title: 'Развернуть свой сервер',
          subtitle: 'Invidious на вашем VPS за 10–15 минут',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CtDeployScreen()))),
    ];

    final app = <Widget>[
      CtCard(
          icon: Icons.settings_outlined,
          title: 'Настройки',
          subtitle: 'Плеер, качество, тема, уведомления',
          onTap: () => AutoRouter.of(context).push(const SettingsRoute())),
      FutureBuilder<String>(
        future: CtUpdater.installedVersion(),
        builder: (context, snap) => CtCard(
            icon: Icons.system_update_outlined,
            title: 'Проверить обновления',
            subtitle: snap.hasData ? 'Установлена версия ${snap.data}' : null,
            onTap: () => CtUpdater.check(context, manual: true)),
      ),
      CtCard(
          icon: Icons.tour_outlined,
          title: 'Обучающий тур',
          subtitle: 'Короткая экскурсия по приложению',
          onTap: () => CtOnboarding.start(context)),
      if (loggedIn)
        CtCard(
            icon: Icons.logout,
            title: direct ? 'Выйти из аккаунта YouTube' : 'Выйти из аккаунта',
            danger: true,
            onTap: () => logout(context)),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        header,
        if (mine.isNotEmpty) ...[const CtCardSection('Моё'), CtCardGrid(children: mine)],
        const CtCardSection('Как смотреть'),
        CtCardGrid(children: watch),
        const CtCardSection('Приложение'),
        CtCardGrid(children: app),
      ],
    );
  }
}


/// Вкладка «Подписки», пока не вошли: объясняем, что нужно сделать.
class CtSubsHint extends StatelessWidget {
  const CtSubsHint({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final server = context.select((AppCubit a) => a.state.server);
    final direct = ctIsDirectUrl(server?.url);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.subscriptions_outlined, size: 64, color: colors.primary),
          const SizedBox(height: 16),
          const Text('Здесь будут новые видео ваших каналов',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
              direct
                  ? 'Войдите в аккаунт YouTube — подписки, рекомендации и история подтянутся сами. '
                      'Пароль вводится только на сайте Google.'
                  : 'Войдите в аккаунт вашего сервера, чтобы видеть подписки.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant)),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.login),
            label: Text(direct ? 'Войти в аккаунт YouTube' : 'Войти в аккаунт'),
            onPressed: () => direct
                ? Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CtYtLoginScreen()))
                : CtYouPage.login(context),
          ),
        ]),
      ),
    );
  }
}
