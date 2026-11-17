import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Сеть CloudTube — один клиент на всё приложение.
///
/// Раньше у сервиса, YouTube-адаптера, комментариев и входа было по своему клиенту — у каждого
/// свой пул соединений, и TLS-рукопожатие с одними и теми же хостами повторялось. Общий клиент
/// держит соединения открытыми (keep-alive) и переиспользует их между запросами.
final http.Client ctHttp = IOClient(HttpClient()
  ..idleTimeout = const Duration(seconds: 60)
  ..connectionTimeout = const Duration(seconds: 12)
  ..maxConnectionsPerHost = 8);

/// Ответы больше этого размера разбираются в фоновом изоляте — крупный JSON (видео, поиск,
/// лента) не подтормаживает интерфейс.
const _bgThreshold = 48 * 1024;

/// Разбор JSON: мелкие ответы — сразу, крупные — в отдельном изоляте (результат передаётся
/// без копирования).
Future<Object?> ctJsonDecode(String body) =>
    body.length < _bgThreshold ? Future.value(jsonDecode(body)) : Isolate.run(() => jsonDecode(body));

/// То же из байтов ответа (UTF-8).
Future<Object?> ctJsonDecodeBytes(List<int> bytes) => bytes.length < _bgThreshold
    ? Future.value(jsonDecode(utf8.decode(bytes)))
    : Isolate.run(() => jsonDecode(utf8.decode(bytes)));

/// Ограниченный кэш «последних использованных» с временем жизни записи.
/// Заменяет разрозненные Map-кэши, которые росли без предела.
class CtLru<K, V> {
  final int capacity;
  final Duration? ttl;
  final _map = <K, (DateTime, V)>{};

  CtLru(this.capacity, {this.ttl});

  V? operator [](K key) {
    final e = _map.remove(key);
    if (e == null) return null;
    if (ttl != null && DateTime.now().difference(e.$1) > ttl!) return null;
    _map[key] = e; // в конец — недавно использован
    return e.$2;
  }

  void operator []=(K key, V value) {
    _map.remove(key);
    _map[key] = (DateTime.now(), value);
    while (_map.length > capacity) {
      _map.remove(_map.keys.first);
    }
  }

  V? remove(K key) => _map.remove(key)?.$2;

  void clear() => _map.clear();

  int get length => _map.length;
}
