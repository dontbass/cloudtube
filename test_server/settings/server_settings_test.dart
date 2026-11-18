import 'package:flutter_test/flutter_test.dart';
import 'package:cloudtube/app/states/app.dart';
import 'package:cloudtube/globals.dart';
import 'package:cloudtube/home/models/db/home_layout.dart';
import 'package:cloudtube/settings/models/db/server.dart';
import 'package:cloudtube/settings/states/server_settings.dart';
import 'package:cloudtube/utils/sembast_sqflite_database.dart';

import '../../test/globals.dart';
import '../../test/test_app_cubit.dart';

main() {
  // Setting a customer override that'll use an unmocked HTTP client
  late AppCubit app;
  setUp(() async {
    db = await SembastSqfDb.createInMemory();
    app = TestAppCubit(AppState(0, null, HomeLayout()));
    await app.initState();
  });

  tearDown(() async => await db.close());

  test('test server setting', () async {
    var server = ServerSettingsCubit(ServerSettingsState(server:Server(url: localInvidiousServer)), app);
    await server.useServer(true);

    await server.logInWithCookie("test", "test");
    expect(server.state.server.sidCookie != null, true);

    // test deleting the server from db
    expect((await db.getServers()).length, 1);
    await server.deleteServer();
    // we can't delete a server if there's only one
    expect((await db.getServers()).length, 1);

    await db.upsertServer(Server(url: 'https://anotherServer'));
    expect((await db.getServers()).length, 2);
    await server.deleteServer();
    expect((await db.getServers()).length, 1);
  });
}
