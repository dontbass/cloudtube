import 'dart:convert';
import 'dart:io';

import 'package:clipious/cloudtube/direct.dart';
import 'package:clipious/cloudtube/yt_account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

Future<void> _t(String name, Future<Object?> Function() f) async {
  final sw = Stopwatch()..start();
  try {
    final r = await f().timeout(const Duration(seconds: 40));
    stdout.writeln('PROBE OK   ${sw.elapsedMilliseconds} ms  $name  ${r ?? ''}');
  } catch (e) {
    final s = '$e'.replaceAll('\n', ' ');
    stdout.writeln('PROBE FAIL ${sw.elapsedMilliseconds} ms  $name  ${s.length > 400 ? s.substring(0, 400) : s}');
  }
}

void main() {
  test('probe', () async {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((r) => stdout.writeln('LOG ${r.loggerName}: ${r.message}'.split('\n').first));
    ctDirectActive = true;
    final client = CtHttpClient(http.Client());
    for (var p = 1; p <= 7; p++) {
      await _t('ct:shorts page $p', () async {
        final r = await client.get(Uri.parse('$kCtDirectUrl/api/v1/search?q=ct:shorts&page=$p'));
        if (r.statusCode != 200) return 'HTTP ${r.statusCode} ${r.body}';
        final l = jsonDecode(r.body) as List;
        return 'n=${l.length} ${l.take(3).map((e) => '${e['videoId']}/${e['lengthSeconds']}/${e['title']}').join(' | ')}';
      });
    }
    await _t('startLogin (с правом на комментарии)', () async => (await CtYtAccount.startLogin()).userCode);
  }, skip: Platform.environment['CT_PROBE'] != '1', timeout: const Timeout(Duration(minutes: 10)));
}
