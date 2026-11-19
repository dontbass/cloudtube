import 'package:cloudtube/cloudtube/yt_account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int ago(String s) => DateTime.now().millisecondsSinceEpoch ~/ 1000 - CtTvPage.ctApproxPublished(s);

  test('время из ленты аккаунта YouTube', () {
    expect(ago('2 часа назад'), closeTo(7200, 5));
    expect(ago('Трансляция закончилась 3 часа назад'), closeTo(3 * 3600, 5));
    expect(ago('5 дней назад'), closeTo(5 * 86400, 5));
    expect(ago('1 день назад'), closeTo(86400, 5));
    expect(ago('2 недели назад'), closeTo(14 * 86400, 5));
    expect(ago('3 days ago'), closeTo(3 * 86400, 5));
    expect(ago('15 минут назад'), closeTo(900, 5));
    expect(CtTvPage.ctApproxPublished('Премьера'), 0);
    expect(CtTvPage.ctApproxPublished(''), 0);
  });
}
