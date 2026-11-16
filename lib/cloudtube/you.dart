import 'package:auto_route/auto_route.dart';
import 'package:clipious/app/states/app.dart';
import 'package:clipious/globals.dart';
import 'package:clipious/home/models/db/home_layout.dart';
import 'package:clipious/router.dart';
import 'package:clipious/settings/models/db/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'updater.dart';
import 'direct.dart';
import 'connect.dart';
import 'connect_screen.dart';
import 'deploy.dart';
import 'onboarding.dart';
import 'yt_login.dart';
import 'yt_cookies.dart';
import 'speed_test.dart';
import 'platform.dart';
import '../main.dart' show isTv;

/// Вкладка «Вы»: аккаунт (вход/выход), история, плейлисты, загрузки, подписки, настройки.
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
    if (ok != true) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      Server s = await db.getCurrentlySelectedServer();
      final cookie = await service.loginWithCookies(s.url, user.text.trim(), pass.text,
          headers: s.customHeaders);
      s = s.copyWith(sidCookie: cookie);
      await db.upsertServer(s);
      if (s.inUse) await fileDb.useServer(s);
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
    if (s.inUse) await fileDb.useServer(s);
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
    final loggedIn = context.select((AppCubit a) => a.isLoggedIn);
    final server = context.select((AppCubit a) => a.state.server);
    final direct = ctIsDirectUrl(server?.url);
    Widget tile(IconData icon, String title, VoidCallback onTap, {String? subtitle}) => ListTile(
          leading: Icon(icon, color: colors.onSurface),
          title: Text(title),
          subtitle: subtitle != null ? Text(subtitle) : null,
          onTap: onTap,
        );
    Widget section(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
          child: Text(t,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.primary, letterSpacing: .3)),
        );
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: const Color(0xFF7B5CD6),
              child: Icon(loggedIn ? Icons.person : Icons.person_outline, color: Colors.white, size: 34),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(direct ? (loggedIn ? 'Аккаунт YouTube' : 'Без сервера') : (loggedIn ? 'Вы вошли в аккаунт' : 'Вы не вошли'),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(direct ? 'YouTube напрямую' : (server?.url.replaceFirst('https://', '') ?? ''),
                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
              ]),
            ),
          ]),
        ),
        if (!loggedIn && direct)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Войдите в аккаунт YouTube — будут ваши рекомендации, подписки и история. '
                  'Вход кодом с телефона или компьютера, как на телевизоре.',
                  style: TextStyle(color: colors.onSurfaceVariant)),
              const SizedBox(height: 12),
              FilledButton.icon(
                  icon: const Icon(Icons.login),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CtYtLoginScreen())),
                  label: const Text('Войти в аккаунт YouTube')),
              const SizedBox(height: 8),
            ]),
          ),
        if (!loggedIn && !direct)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Войдите, чтобы видеть свои подписки, историю и плейлисты.',
                  style: TextStyle(color: colors.onSurfaceVariant)),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => login(context), child: const Text('Войти в аккаунт')),
              const SizedBox(height: 8),
            ]),
          ),
        section('Моё'),
        if (loggedIn) ...[
          tile(Icons.history, 'История', () => _open(context, 'История', HomeDataSource.history.build(context, false)),
              subtitle: 'Что вы смотрели'),
          if (!direct)
            tile(Icons.playlist_play, 'Плейлисты',
                () => _open(context, 'Плейлисты', HomeDataSource.playlist.build(context, false)),
                subtitle: 'Ваши подборки видео'),
          tile(Icons.subscriptions_outlined, 'Управление подписками',
              () => AutoRouter.of(context).push(const ManageSubscriptionsRoute()),
              subtitle: 'Список каналов, отписаться'),
        ],
        if (direct && !isTv && !ctDesktop)
          tile(Icons.forum_outlined, 'Комментарии от своего имени',
              () async {
                if (CtYtCookies.active) {
                  await CtYtCookies.save(null);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Вход через сайт YouTube отключён')));
                  }
                } else {
                  await Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const CtYtWebLoginScreen()));
                }
                (context as Element).markNeedsBuild();
              },
              subtitle: CtYtCookies.active
                  ? 'Включено (вход через сайт). Нажмите, чтобы отключить'
                  : 'Вход через сайт Google — нужен, чтобы писать комментарии'),
        tile(Icons.download_outlined, 'Загрузки', () => AutoRouter.of(context).push(const DownloadManagerRoute()),
            subtitle: 'Видео, сохранённые для просмотра без интернета'),
        section('Как смотреть'),
        if (server != null && ctIsDirectUrl(server.url))
          tile(Icons.dns_outlined, 'Подключить свой сервер',
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CtConnectScreen())),
              subtitle: 'Сейчас: YouTube напрямую. Свой сервер Invidious — без рекламы для всей семьи'),
        if (server != null && !ctIsDirectUrl(server.url))
          tile(Icons.play_circle_outline, 'Смотреть без сервера',
              () => ctConnectDirect(context.read<AppCubit>()),
              subtitle: 'YouTube напрямую; вернуться к серверу можно в настройках серверов'),
        if (server != null && !ctIsDirectUrl(server.url))
          tile(Icons.dns_outlined, 'Сервер и пароль сайта',
              () => AutoRouter.of(context).push(ManageSingleServerRoute(server: server)),
              subtitle: 'Логин/пароль сайта (Basic Auth), другие серверы'),
        tile(Icons.rocket_launch_outlined, 'Развернуть свой сервер',
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CtDeployScreen())),
            subtitle: 'Invidious на вашем VPS за 10–15 минут'),
        section('Приложение'),
        tile(Icons.settings_outlined, 'Настройки', () => AutoRouter.of(context).push(const SettingsRoute()),
            subtitle: 'Тема, качество видео, плеер, язык'),
        FutureBuilder<String>(
          future: CtUpdater.installedVersion(),
          builder: (context, snap) => tile(Icons.system_update_outlined, 'Проверить обновления',
              () => CtUpdater.check(context, manual: true),
              subtitle: snap.hasData ? 'Установлена версия ${snap.data}' : null),
        ),
        tile(Icons.speed, 'Проверка скорости YouTube',
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CtSpeedTestScreen())),
            subtitle: 'Где задержка при запуске видео: сеть, YouTube, внешние сервисы'),
        tile(Icons.tour_outlined, 'Обучающий тур', () => CtOnboarding.start(context),
            subtitle: 'Короткая экскурсия по кнопкам и вкладкам'),
        if (loggedIn)
          tile(Icons.logout, direct ? 'Выйти из аккаунта YouTube' : 'Выйти из аккаунта', () => logout(context)),
        const SizedBox(height: 24),
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
