import 'dart:io';

import 'package:cloudtube/cloudtube/platform.dart';
import 'package:cloudtube/globals.dart';
import 'package:cloudtube/settings/models/db/settings.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context ?? ctDesktopContext)
      ..userAgent =
          'CloudTube/${packageInfo?.version ?? '0.0.0'} (${packageInfo?.packageName ?? ''})'
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        // if true, it will allow all certs, if false it will throw error on a bad cert
        return db.getSettings(skipSslVerificationSettingName)?.value == 'true';
      };
  }
}
