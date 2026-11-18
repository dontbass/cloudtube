import 'dart:async';

import 'package:flutter/widgets.dart';

import '../settings/models/db/server.dart';
import 'direct.dart';

final _yt3 = RegExp(r'^https?://(yt3\.ggpht\.com|yt3\.googleusercontent\.com)(/.*)$');

/// Адрес картинки с учётом режима. Со своим сервером аватарки каналов (yt3.ggpht.com /
/// googleusercontent) идут через его прокси /ggpht — у части провайдеров эти адреса Google
/// не открываются, и картинка «крутилась» бесконечно (так было в Windows-версии).
String ctImageUrl(String u, Server? server) {
  if (u.startsWith('//')) u = 'https:$u';
  if (server == null || ctIsDirectUrl(server.url)) return u;
  final m = _yt3.firstMatch(u);
  if (m != null) return '${server.url}/ggpht${m.group(2)}';
  if (u.startsWith('/')) return server.url + u;
  return u;
}

/// Показывается, пока картинка грузится; если загрузка «висит» дольше [after] —
/// вызывает [onTimeout] (попробовать другой адрес или показать заглушку).
class CtLoadTimeout extends StatefulWidget {
  final Widget child;
  final Duration after;
  final VoidCallback onTimeout;

  const CtLoadTimeout({super.key, required this.child, required this.onTimeout, this.after = const Duration(seconds: 8)});

  @override
  State<CtLoadTimeout> createState() => _CtLoadTimeoutState();
}

class _CtLoadTimeoutState extends State<CtLoadTimeout> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(widget.after, () {
      if (mounted) widget.onTimeout();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
