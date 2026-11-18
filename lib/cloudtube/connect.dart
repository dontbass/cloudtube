import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app/states/app.dart';
import '../globals.dart';
import '../settings/models/db/server.dart';
import 'direct.dart';
import 'prefs.dart';

class CtConnectError implements Exception {
  final String message;

  CtConnectError(this.message);

  @override
  String toString() => message;
}

/// Подключить приложение к серверу: проверить адрес и пароль сайта, при необходимости войти
/// в аккаунт Invidious, сохранить сервер и сделать его текущим.
/// Используется входом с телефона на ТВ и мастером «Свой сервер».
Future<Server> ctConnectServer({
  required String url,
  required AppCubit app,
  String siteUser = '',
  String sitePass = '',
  String user = '',
  String pass = '',
  void Function(String status)? onStatus,
}) async {
  url = url.trim();
  if (url.isEmpty) throw CtConnectError('Укажите адрес сервера');
  if (!url.startsWith('http')) url = 'https://$url';
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  final existing = db.getServer(url);
  final headers = Map<String, String>.from(existing?.customHeaders ?? {});
  if (siteUser.trim().isNotEmpty) {
    headers['Authorization'] = 'Basic ${base64.encode(utf8.encode('${siteUser.trim()}:$sitePass'))}';
  }
  onStatus?.call('Проверяю сервер…');
  try {
    final r = await http.get(Uri.parse('$url/api/v1/stats'), headers: headers).timeout(const Duration(seconds: 15));
    if (r.statusCode == 401) {
      throw CtConnectError('Сервер просит пароль сайта — проверьте логин и пароль сайта');
    }
    if (r.statusCode != 200) throw CtConnectError('Сервер ответил ${r.statusCode} — это точно Invidious?');
  } on CtConnectError {
    rethrow;
  } catch (e) {
    throw CtConnectError('Сервер недоступен: $e');
  }
  var s = (existing ?? Server(url: url)).copyWith(customHeaders: headers, inUse: true);
  if (user.trim().isNotEmpty) {
    onStatus?.call('Вхожу в аккаунт ${user.trim()}…');
    try {
      final cookie = await service.loginWithCookies(url, user.trim(), pass, headers: headers);
      s = s.copyWith(sidCookie: cookie, authToken: null);
    } catch (_) {
      throw CtConnectError('Не удалось войти в аккаунт: неверный логин или пароль');
    }
  }
  await db.upsertServer(s);
  await db.useServer(s);
  await CtPrefs.lastServer.set(s.url);
  app.setServer(s);
  return s;
}

/// Последний свой сервер (не «напрямую»), если он сохранён.
Future<Server?> ctLastOwnServer() async {
  final all = (await db.getServers()).where((s) => !ctIsDirectUrl(s.url)).toList();
  if (all.isEmpty) return null;
  final url = CtPrefs.lastServer.value;
  return all.firstWhere((s) => s.url == url, orElse: () => all.first);
}

/// Переключиться на свой сервер — тот же адрес, вход и пароль сайта, что были.
/// null — своего сервера ещё нет (нужно подключить).
Future<Server?> ctConnectLastServer(AppCubit app) async {
  final s = await ctLastOwnServer();
  if (s == null) return null;
  final cur = s.copyWith(inUse: true);
  await db.useServer(cur);
  await CtPrefs.lastServer.set(cur.url);
  app.setServer(cur);
  return cur;
}

/// Режим «без сервера»: приложение ходит в YouTube напрямую.
Future<Server> ctConnectDirect(AppCubit app) async {
  // запоминаем свой сервер, чтобы вернуться к нему одним нажатием
  try {
    final cur = await db.getCurrentlySelectedServer();
    if (!ctIsDirectUrl(cur.url)) await CtPrefs.lastServer.set(cur.url);
  } catch (_) {}
  final existing = db.getServer(kCtDirectUrl);
  final s = (existing ?? const Server(url: kCtDirectUrl)).copyWith(inUse: true);
  await db.upsertServer(s);
  await db.useServer(s);
  app.setServer(s);
  return s;
}
