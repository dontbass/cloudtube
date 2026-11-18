import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'download.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'prefs.dart';

final _log = Logger('CtUpdater');
const _channel = MethodChannel('cloudtube/update');

/// Откуда брать обновления: релизы GitHub публичного репозитория.
/// В своём форке поменяйте на свой owner/repo.
const kCtUpdateRepo = 'dontbass/cloudtube';

/// Сведения о свежей сборке из GitHub Releases.
class CtRelease {
  final String version;
  final String notes;
  final Map<String, String> files; // abi -> url
  final Map<String, int> sizes;

  CtRelease(this.version, this.notes, this.files, this.sizes);

  factory CtRelease.fromGitHub(Map<String, dynamic> j) {
    final files = <String, String>{};
    final sizes = <String, int>{};
    for (final a in (j['assets'] as List? ?? [])) {
      final m = RegExp(r'-(arm64-v8a|armeabi-v7a|x86_64)\.apk$').firstMatch('${a['name']}');
      if (m != null) {
        files[m.group(1)!] = '${a['browser_download_url']}';
        sizes[m.group(1)!] = (a['size'] as num?)?.toInt() ?? 0;
      }
    }
    final notes = '${j['body'] ?? ''}'.replaceAll(RegExp(r'\n*Для большинства телефонов.*$', dotAll: true), '');
    return CtRelease('${j['tag_name']}'.replaceFirst('v', ''), notes, files, sizes);
  }
}

/// 1.1.3 > 1.0.19: сравнение по частям версии
int ctCompareVersions(String a, String b) {
  final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

class CtUpdater {
  static bool _busy = false;

  static Future<String> installedVersion() async => (await PackageInfo.fromPlatform()).version;

  static Future<CtRelease?> fetch() async {
    if (Platform.isWindows) return _fetchWindows();
    final r = await http.get(Uri.parse('https://api.github.com/repos/$kCtUpdateRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw 'GitHub ответил ${r.statusCode}';
    return CtRelease.fromGitHub(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  /// Проверка обновлений. [manual] — пользователь нажал сам: сообщаем и «обновлений нет».
  /// Автопроверка при сбое сети повторяется через 30 с и через 2 мин (в машине и на ТВ сеть
  /// часто поднимается позже запуска приложения).
  static Future<void> check(BuildContext context, {bool manual = false, int attempt = 0}) async {
    if (!(Platform.isAndroid || Platform.isWindows) || _busy) return;
    _busy = true;
    if (Platform.isWindows) unawaited(_cleanupWindows());
    try {
      final rel = await fetch();
      final cur = await installedVersion();
      if (!context.mounted || rel == null) return;
      if (ctCompareVersions(rel.version, cur) <= 0 || rel.files.isEmpty) {
        if (manual) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('У вас последняя версия')));
        }
        return;
      }
      // «Позже» откладывает напоминание об этой версии на сутки (раньше — навсегда)
      if (!manual) {
        final skip = CtPrefs.updateSkip.value.split('|');
        final at = skip.length > 1 ? int.tryParse(skip[1]) ?? 0 : 0;
        if (skip.first == rel.version &&
            DateTime.now().millisecondsSinceEpoch - at < const Duration(hours: 24).inMilliseconds) {
          return;
        }
      }
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Доступно обновление ${rel.version}'),
          content: SingleChildScrollView(
            child: Text(rel.notes.trim().isEmpty ? 'Новая версия CloudTube.' : rel.notes.trim()),
          ),
          actions: [
            TextButton(
                onPressed: () {
                  CtPrefs.updateSkip.set('${rel.version}|${DateTime.now().millisecondsSinceEpoch}');
                  Navigator.pop(ctx, false);
                },
                child: const Text('Позже')),
            FilledButton(autofocus: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Обновить')),
          ],
        ),
      );
      if (go == true && context.mounted) await _downloadAndInstall(context, rel);
    } catch (e) {
      _log.warning('update check: $e');
      if (manual && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Не удалось проверить обновления: ${_why(e)}')));
      } else if (!manual && attempt < 2) {
        Future.delayed(Duration(seconds: attempt == 0 ? 30 : 120), () {
          if (context.mounted) check(context, attempt: attempt + 1);
        });
      }
    } finally {
      _busy = false;
    }
  }

  static String _why(Object e) {
    final t = '$e';
    if (e is TlsException || t.contains('HandshakeException') || t.contains('CERTIFICATE')) {
      return 'проверьте дату и время на устройстве';
    }
    if (e is SocketException || t.contains('SocketException') || t.contains('Failed host lookup')) {
      return 'нет подключения к интернету';
    }
    if (e is TimeoutException) return 'GitHub не отвечает, попробуйте позже';
    return t;
  }

  static Future<String?> _pickAbi(CtRelease rel) async {
    final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
    for (final a in abis) {
      if (rel.files.containsKey(a)) return a;
    }
    return rel.files.keys.isEmpty ? null : rel.files.keys.first;
  }

  static Future<void> _downloadAndInstall(BuildContext context, CtRelease rel) async {
    if (Platform.isWindows) return _windowsUpdate(context, rel);
    final abi = await _pickAbi(rel);
    if (abi == null) throw 'нет сборки для этого устройства';
    final url = rel.files[abi]!;

    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final path = '${dir.path}/CloudTube-${rel.version}-$abi.apk';

    final progress = ValueNotifier<double?>(null);
    final cancel = CtCancel();
    if (!context.mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Загрузка ${rel.version}'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, p, __) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: p),
            const SizedBox(height: 12),
            Text(p == null ? 'Подключение…' : '${(p * 100).round()} %'),
          ]),
        ),
        actions: [TextButton(onPressed: () => cancel.cancel(), child: const Text('Отмена'))],
      ),
    );
    try {
      await ctDownloadFile(url, path, cancel: cancel, onProgress: (got, total) {
        final t = total > 0 ? total : (rel.sizes[abi] ?? 0);
        if (t > 0) progress.value = got / t;
      });
    } on CtCancelled {
      nav.pop();
      return;
    } catch (e) {
      nav.pop();
      rethrow;
    }
    nav.pop();
    if (!context.mounted) return;
    await install(context, path);
  }

  /// Разрешение «Установка из неизвестных источников» — один раз; потом системное окно установки.
  static Future<void> install(BuildContext context, String path) async {
    final can = await _channel.invokeMethod<bool>('canInstall') ?? false;
    if (!can) {
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Нужно разрешение'),
          content: const Text(
              'Разрешите CloudTube устанавливать приложения: включите переключатель на следующем экране '
              'и вернитесь назад — установка продолжится.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Открыть настройки')),
          ],
        ),
      );
      if (ok != true) return;
      await _channel.invokeMethod('openInstallSettings');
      // ждём, пока пользователь вернётся из настроек с включённым разрешением (до 2 минут)
      for (var i = 0; i < 240; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (await _channel.invokeMethod<bool>('canInstall') == true) break;
      }
      if (await _channel.invokeMethod<bool>('canInstall') != true) return;
    }
    await _channel.invokeMethod('install', {'path': path});
  }

  // ---------------- Windows: один файл CloudTube.exe, обновляет сам себя ----------------

  /// Сборка для Windows лежит в пре-релизе windows-preview: CloudTube.exe и версия в CloudTube-windows.json.
  static Future<CtRelease?> _fetchWindows() async {
    final r = await http.get(Uri.parse('https://api.github.com/repos/$kCtUpdateRepo/releases/tags/windows-preview'),
        headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw 'GitHub ответил ${r.statusCode}';
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    String? exe, json;
    var size = 0;
    for (final a in (j['assets'] as List? ?? [])) {
      final name = '${(a as Map)['name']}';
      if (name == 'CloudTube.exe') {
        exe = '${a['browser_download_url']}';
        size = (a['size'] as num?)?.toInt() ?? 0;
      }
      if (name == 'CloudTube-windows.json') json = '${a['browser_download_url']}';
    }
    if (exe == null || json == null) return null;
    final v = await http.get(Uri.parse(json)).timeout(const Duration(seconds: 15));
    if (v.statusCode != 200) throw 'GitHub ответил ${v.statusCode}';
    final raw = utf8.decode(v.bodyBytes).replaceFirst('\uFEFF', '');
    final version = '${(jsonDecode(raw) as Map)['version'] ?? ''}';
    if (version.isEmpty) return null;
    return CtRelease(version, 'Новая версия CloudTube для Windows.', {'win': exe}, {'win': size});
  }

  /// Остаток прошлого обновления (CloudTube.old.exe) — удалить, когда он уже не запущен.
  static Future<void> _cleanupWindows() async {
    try {
      final exe = File(Platform.resolvedExecutable);
      for (final f in exe.parent.listSync().whereType<File>()) {
        final n = f.uri.pathSegments.last.toLowerCase();
        if (n.endsWith('.old.exe') || n.endsWith('.new.exe')) await f.delete();
      }
    } catch (_) {}
  }

  /// Скачать новый CloudTube.exe рядом с текущим, подменить его и перезапуститься.
  /// Запущенный exe Windows удалить не даёт, а переименовать — даёт: текущий становится
  /// CloudTube.old.exe (его уберёт следующий запуск), новый встаёт на его место.
  static Future<void> _windowsUpdate(BuildContext context, CtRelease rel) async {
    final exe = File(Platform.resolvedExecutable);
    final dir = exe.parent.path;
    final name = exe.uri.pathSegments.last;
    final base = name.toLowerCase().endsWith('.exe') ? name.substring(0, name.length - 4) : name;
    final fresh = File('$dir${Platform.pathSeparator}$base.new.exe');
    final old = File('$dir${Platform.pathSeparator}$base.old.exe');

    final progress = ValueNotifier<double?>(null);
    var cancelled = false;
    if (!context.mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Загрузка ${rel.version}'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, p, __) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: p),
            const SizedBox(height: 12),
            Text(p == null ? 'Подключение…' : '${(p * 100).round()} %'),
          ]),
        ),
        actions: [TextButton(onPressed: () => cancelled = true, child: const Text('Отмена'))],
      ),
    );
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(rel.files['win']!)));
      if (res.statusCode != 200) throw 'GitHub ответил ${res.statusCode}';
      final total = res.contentLength ?? rel.sizes['win'] ?? 0;
      final sink = fresh.openWrite();
      var got = 0;
      try {
        await for (final chunk in res.stream) {
          if (cancelled) throw const _Cancelled();
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) progress.value = got / total;
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && got != total) throw 'файл скачался не полностью';
      // подмена файла и перезапуск
      if (await old.exists()) await old.delete();
      await exe.rename(old.path);
      try {
        await fresh.rename(exe.path);
      } catch (e) {
        await old.rename(exe.path); // вернуть как было
        rethrow;
      }
      await Process.start(exe.path, const [], mode: ProcessStartMode.detached);
      exit(0);
    } on _Cancelled {
      nav.pop();
      try {
        await fresh.delete();
      } catch (_) {}
    } on FileSystemException catch (e) {
      nav.pop();
      _log.warning('windows update: $e');
      // например, программа лежит в Program Files — туда без прав администратора не записать
      messenger.showSnackBar(const SnackBar(
          content: Text('Не удалось заменить файл программы. Переместите CloudTube.exe в обычную папку '
              '(например, «Документы») и повторите обновление.')));
    } catch (e) {
      nav.pop();
      rethrow;
    } finally {
      client.close();
    }
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
