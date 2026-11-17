import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> step(String name, Future<Object?> Function() f) async {
  final sw = Stopwatch()..start();
  try {
    final r = await f();
    print('OK  $name ${sw.elapsedMilliseconds}ms: $r');
  } catch (e, st) {
    print('ERR $name ${sw.elapsedMilliseconds}ms: $e');
    print(st.toString().split('\n').take(8).join('\n'));
  }
}

Future<void> main() async {
  final yt = YoutubeExplode();
  for (final id in ['UCUGfDbfRIx51kJGGHIFo8Rw', 'UC_x5XG1OV2P6uZZ5FSM9Ttw', 'UCBR8-60-B28hp2BmDPdntcQ']) {
    await step('get $id', () async {
      final c = await yt.channels.get(id);
      return '${c.title} subs=${c.subscribersCount} logo=${c.logoUrl.length} banner=${c.bannerUrl.length}';
    });
    await step('about $id', () async => (await yt.channels.getAboutPage(id)).description?.length);
    await step('uploads $id', () async => (await yt.channels.getUploadsFromPage(id)).length);
    await step('shorts $id', () async => (await yt.channels.getUploadsFromPage(id, videoType: VideoType.shorts)).length);
  }
  yt.close();
}
