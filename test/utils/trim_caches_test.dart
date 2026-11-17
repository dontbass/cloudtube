import 'package:sembast/sembast.dart';
import 'package:clipious/utils/sembast_sqflite_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('уборка базы оставляет самые свежие записи', () async {
    final d = await SembastSqfDb.createInMemory();
    // 3010 позиций просмотра: самые старые — с меньшим временем
    for (var i = 0; i < 3010; i++) {
      await d.progressStore.record('v$i').put(d.db, {'progress': 0.5, 'videoId': 'v$i', 't': i});
    }
    // старые записи без времени (из прошлых версий) считаются самыми старыми
    await d.progressStore.record('old').put(d.db, {'progress': 0.1, 'videoId': 'old'});
    await d.trimCaches();
    final left = await d.progressStore.find(d.db);
    expect(left.length, 3000);
    final keys = left.map((r) => r.key).toSet();
    expect(keys.contains('old'), isFalse);
    expect(keys.contains('v0'), isFalse);
    expect(keys.contains('v3009'), isTrue);
    expect(d.getVideoProgress('v3009'), 0.5);
    await d.close();
  });
}
