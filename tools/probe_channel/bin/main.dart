import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main() async {
  final yt = YoutubeExplode();
  for (final id in ['UC_x5XG1OV2P6uZZ5FSM9Ttw', 'UCBR8-60-B28hp2BmDPdntcQ', 'UCsAw3WynQJMm7tMy093y37A']) {
    try {
      final l = await yt.channels.getUploadsFromPage(id);
      print('== $id: ${l.length}');
      for (final v in l.take(5)) {
        print('  ${v.id} | ${v.title} | ${v.duration} | views=${v.engagement.viewCount} | ${v.uploadDateRaw}');
      }
      final n = await l.nextPage();
      print('  page2: ${n?.length} first=${n?.firstOrNull?.title}');
    } catch (e, st) {
      print('ERR $id $e\n${st.toString().split('\n').take(5).join('\n')}');
    }
  }
  yt.close();
}
