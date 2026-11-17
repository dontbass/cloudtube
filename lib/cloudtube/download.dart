import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'direct.dart' show ctDirectStreamHeaders;
import 'net.dart';

final _log = Logger('Загрузка');

/// Отмена загрузки.
class CtCancel {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

class CtCancelled implements Exception {
  @override
  String toString() => 'Загрузка отменена';
}

/// Скачать файл (вместо библиотеки dio).
///
/// Потоки YouTube (googlevideo) качаются частями по 10 МБ: целиком YouTube отдаёт файл
/// медленно (ограничивает скорость), а по частям — на полной скорости. Каждая часть при
/// обрыве повторяется до 3 раз. Заголовки для режима «без сервера» добавляются сами.
Future<void> ctDownloadFile(
  String url,
  String path, {
  Map<String, String>? headers,
  void Function(int got, int total)? onProgress,
  CtCancel? cancel,
}) async {
  final h = {...?headers, ...ctDirectStreamHeaders(url)};
  final chunked = Uri.tryParse(url)?.host.endsWith('googlevideo.com') ?? false;
  final file = File(path);
  await file.parent.create(recursive: true);
  final out = file.openWrite();
  var got = 0;
  var total = int.tryParse(Uri.tryParse(url)?.queryParameters['clen'] ?? '') ?? -1;
  try {
    if (!chunked) {
      await _stream(url, h, out, cancel, (n) {
        got += n;
        onProgress?.call(got, total);
      }, (t) => total = t);
    } else {
      const step = 10 * 1024 * 1024;
      while (total < 0 || got < total) {
        final end = got + step - 1;
        final start = got;
        var attempt = 0;
        while (true) {
          final before = got;
          try {
            final done = await _stream(url, {...h, 'Range': 'bytes=$got-$end'}, out, cancel, (n) {
              got += n;
              onProgress?.call(got, total);
            }, (t) => total = t);
            if (done) total = got; // сервер отдал всё целиком (без частей)
            break;
          } on CtCancelled {
            rethrow;
          } catch (e) {
            // часть оборвалась — продолжаем с того места, где остановились
            if (++attempt > 3) rethrow;
            _log.info('часть с $before: $e, повтор $attempt');
            await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
          }
        }
        if (total < 0 || got == start) break; // без прогресса — не крутимся вечно
      }
    }
    await out.flush();
    await out.close();
  } catch (e) {
    await out.close();
    if (await file.exists()) await file.delete();
    rethrow;
  }
}

/// Один запрос. Возвращает true, если сервер проигнорировал Range и отдал файл целиком.
Future<bool> _stream(String url, Map<String, String> headers, IOSink out, CtCancel? cancel,
    void Function(int) onBytes, void Function(int) onTotal) async {
  if (cancel?.isCancelled ?? false) throw CtCancelled();
  final req = http.Request('GET', Uri.parse(url))..headers.addAll(headers);
  final res = await ctHttp.send(req).timeout(const Duration(seconds: 20));
  if (res.statusCode != 200 && res.statusCode != 206) {
    throw HttpException('HTTP ${res.statusCode}', uri: req.url);
  }
  final range = res.headers['content-range']; // bytes a-b/total
  final t = int.tryParse(range?.split('/').last ?? '');
  if (t != null) {
    onTotal(t);
  } else if (res.statusCode == 200 && res.contentLength != null) {
    onTotal(res.contentLength!);
  }
  await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
    if (cancel?.isCancelled ?? false) throw CtCancelled(); // выход из цикла закрывает соединение
    out.add(chunk);
    onBytes(chunk.length);
  }
  return res.statusCode == 200 && headers.containsKey('Range');
}
