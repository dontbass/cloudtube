import 'dart:io';

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
