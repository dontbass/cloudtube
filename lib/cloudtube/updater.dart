import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../globals.dart';
import '../settings/models/db/settings.dart';

final _log = Logger('CtUpdater');
const _channel = MethodChannel('cloudtube/update');
const _skipKey = 'ct-update-skip';

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
    final r = await http.get(Uri.parse('https://api.github.com/repos/$kCtUpdateRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw 'GitHub ответил ${r.statusCode}';
    return CtRelease.fromGitHub(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  /// Проверка обновлений. [manual] — пользователь нажал сам: сообщаем и «обновлений нет».
  static Future<void> check(BuildContext context, {bool manual = false}) async {
    if (!Platform.isAndroid || _busy) return;
    _busy = true;
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
      if (!manual && db.getSettings(_skipKey)?.value == rel.version) return;
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
                  db.saveSetting(SettingsValue(_skipKey, rel.version));
                  Navigator.pop(ctx, false);
                },
                child: const Text('Позже')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Обновить')),
          ],
        ),
      );
      if (go == true && context.mounted) await _downloadAndInstall(context, rel);
    } catch (e) {
      _log.warning('update check: $e');
      if (manual && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Не удалось проверить обновления: $e')));
      }
    } finally {
      _busy = false;
    }
  }

  static Future<String?> _pickAbi(CtRelease rel) async {
    final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
    for (final a in abis) {
      if (rel.files.containsKey(a)) return a;
    }
    return rel.files.keys.isEmpty ? null : rel.files.keys.first;
  }

  static Future<void> _downloadAndInstall(BuildContext context, CtRelease rel) async {
    final abi = await _pickAbi(rel);
    if (abi == null) throw 'нет сборки для этого устройства';
    final url = rel.files[abi]!;

    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final path = '${dir.path}/CloudTube-${rel.version}-$abi.apk';

    final progress = ValueNotifier<double?>(null);
    final cancel = CancelToken();
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
      await Dio().download(url, path,
          cancelToken: cancel, onReceiveProgress: (got, total) {
        final t = total > 0 ? total : (rel.sizes[abi] ?? 0);
        if (t > 0) progress.value = got / t;
      });
    } catch (e) {
      nav.pop();
      if (e is DioException && CancelToken.isCancel(e)) return;
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
}
