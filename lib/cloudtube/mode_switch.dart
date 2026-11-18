import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../app/states/app.dart';
import 'connect.dart';
import 'connect_screen.dart';
import 'direct.dart';

/// Переключить режим: напрямую ↔ свой сервер (тот, что был, со входом и паролем сайта).
/// Своего сервера ещё нет — открывает экран подключения.
Future<void> ctToggleMode(BuildContext context, {required bool toDirect}) async {
  final app = context.read<AppCubit>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (toDirect) {
    await ctConnectDirect(app);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(const SnackBar(content: Text('Режим: YouTube напрямую')));
    return;
  }
  final s = await ctConnectLastServer(app);
  if (s == null) {
    if (context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CtConnectScreen()));
    }
    return;
  }
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(content: Text('Режим: свой сервер (${s.url.replaceFirst(RegExp('^https?://'), '')})')));
}

/// Переключатель «YouTube напрямую | Свой сервер» для шапки профиля и настроек.
class CtModeSwitch extends StatelessWidget {
  const CtModeSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final server = context.select((AppCubit a) => a.state.server);
    final direct = ctIsDirectUrl(server?.url);
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: true, icon: Icon(Icons.play_circle_outline), label: Text('YouTube напрямую')),
          ButtonSegment(value: false, icon: Icon(Icons.dns_outlined), label: Text('Свой сервер')),
        ],
        selected: {direct},
        onSelectionChanged: (v) {
          if (v.first != direct) ctToggleMode(context, toDirect: v.first);
        },
      ),
    );
  }
}
