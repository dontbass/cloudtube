import 'dart:io';
import 'dart:typed_data';

import 'package:cloudtube/cloudtube/download.dart';
import 'package:cloudtube/cloudtube/net.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CtLru', () {
    test('вытесняет самые давние и обновляет порядок при чтении', () {
      final c = CtLru<String, int>(2);
      c['a'] = 1;
      c['b'] = 2;
      expect(c['a'], 1); // «a» стал свежим
      c['c'] = 3; // вытесняется «b»
      expect(c['b'], isNull);
      expect(c['a'], 1);
      expect(c['c'], 3);
      expect(c.length, 2);
    });

    test('время жизни записи', () async {
      final c = CtLru<String, int>(5, ttl: const Duration(milliseconds: 50));
      c['a'] = 1;
      expect(c['a'], 1);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(c['a'], isNull);
    });
  });

  test('крупный JSON разбирается так же, как мелкий', () async {
    final big = '[${List.filled(20000, '{"a":1,"b":"текст"}').join(',')}]';
    final r = await ctJsonDecode(big) as List;
    expect(r.length, 20000);
    expect((r.first as Map)['b'], 'текст');
    expect(await ctJsonDecode('{"x":2}'), {'x': 2});
  });

  group('ctDownloadFile', () {
    late HttpServer server;
    final data = Uint8List.fromList(List.generate(300000, (i) => i % 251));

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final range = req.headers.value('range');
        if (range != null) {
          final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
          final a = int.parse(m.group(1)!);
          final b = int.parse(m.group(2)!).clamp(0, data.length - 1);
          req.response.statusCode = 206;
          req.response.headers.set('content-range', 'bytes $a-$b/${data.length}');
          req.response.add(data.sublist(a, b + 1));
        } else {
          req.response.add(data);
        }
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('файл целиком, с прогрессом', () async {
      final dir = await Directory.systemTemp.createTemp('ct');
      final path = '${dir.path}/f.bin';
      var last = 0;
      await ctDownloadFile('http://127.0.0.1:${server.port}/f', path, onProgress: (g, t) => last = g);
      expect(await File(path).readAsBytes(), data);
      expect(last, data.length);
      await dir.delete(recursive: true);
    });

    test('отмена удаляет недокачанный файл', () async {
      final dir = await Directory.systemTemp.createTemp('ct');
      final path = '${dir.path}/f.bin';
      final cancel = CtCancel()..cancel();
      await expectLater(
          ctDownloadFile('http://127.0.0.1:${server.port}/f', path, cancel: cancel), throwsA(isA<CtCancelled>()));
      expect(await File(path).exists(), isFalse);
      await dir.delete(recursive: true);
    });
  });
}
