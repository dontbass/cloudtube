import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;

import 'package:path_provider/path_provider.dart';

/// Windows / Linux / macOS — настольная сборка CloudTube.
bool get ctDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Папка данных приложения: на ПК — %APPDATA%\…\CloudTube (а не «Документы»), на телефоне — как раньше.
Future<Directory> ctDataDir() async {
  try {
    return ctDesktop ? await getApplicationSupportDirectory() : await getApplicationDocumentsDirectory();
  } catch (_) {
    return Directory.current;
  }
}

/// Запасной TLS-контекст для ПК (если системное хранилище не удалось дополнить).
SecurityContext? ctDesktopContext;

/// Путь к файлу корневых сертификатов на ПК (для mpv: tls-ca-file).
String? ctCaFile;

/// Windows может не иметь в своём хранилище корневой сертификат Let's Encrypt (ISRG Root X1):
/// он подгружается системой «по требованию», а Dart читает хранилище как есть —
/// отсюда CERTIFICATE_VERIFY_FAILED. Добавляем к системным корням набор Mozilla (как в браузерах).
Future<void> ctInitDesktopCerts() async {
  if (!ctDesktop) return;
  try {
    final data = await rootBundle.load('assets/certs/cacert.pem');
    final bytes = data.buffer.asUint8List();
    try {
      SecurityContext.defaultContext.setTrustedCertificatesBytes(bytes);
    } catch (_) {
      // не удалось дополнить системное хранилище — используем отдельный контекст только с набором Mozilla
      ctDesktopContext = SecurityContext(withTrustedRoots: false)..setTrustedCertificatesBytes(bytes);
    }
    final dir = await ctDataDir();
    await dir.create(recursive: true);
    final f = File('${dir.path}${Platform.pathSeparator}cacert.pem');
    await f.writeAsBytes(bytes, flush: true);
    ctCaFile = f.path;
  } catch (_) {}
}
