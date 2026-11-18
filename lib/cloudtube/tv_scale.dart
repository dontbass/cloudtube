import 'package:flutter/material.dart';

import 'prefs.dart';


/// Масштаб интерфейса на телевизоре (1.0 — как в Clipious; меньше — мельче и больше помещается).
final ctTvScale = ValueNotifier<double>(0.8);

void ctLoadTvScale() {
  ctTvScale.value = CtPrefs.tvScale.value;
}


/// Без сервера: потолок качества видео (как профиль в SmartTube). На ТВ по умолчанию 4K,
/// на телефоне — 1080p (экран меньше, экономия трафика и батареи). Меняется выбором качества
/// в плеере и запоминается — отдельно для ТВ и телефона.
int ctTvQualityCap = 2160;
bool _ctTv = false;

void ctLoadQuality({required bool tv}) {
  _ctTv = tv;
  ctTvQualityCap = (tv ? CtPrefs.tvQuality : CtPrefs.phoneQuality).value;
}

Future<void> ctSetTvQuality(int h) async {
  ctTvQualityCap = h;
  await (_ctTv ? CtPrefs.tvQuality : CtPrefs.phoneQuality).set(h);
}

Future<void> ctSetTvScale(double v) async {
  ctTvScale.value = v;
  await CtPrefs.tvScale.set(v);
}

const ctTvScales = [1.0, 0.9, 0.8, 0.7, 0.6];

/// Рисуем весь интерфейс на «большем» логическом экране и уменьшаем до реального —
/// так плитки, меню и шрифты становятся пропорционально мельче, фокус и нажатия работают как прежде.
class CtTvScale extends StatelessWidget {
  final Widget child;

  const CtTvScale({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: ctTvScale,
      builder: (context, scale, _) {
        if (scale >= 0.999) return child;
        final mq = MediaQuery.of(context);
        final size = mq.size / scale;
        return MediaQuery(
          data: mq.copyWith(
            size: size,
            devicePixelRatio: mq.devicePixelRatio * scale,
            padding: mq.padding / scale,
            viewPadding: mq.viewPadding / scale,
            viewInsets: mq.viewInsets / scale,
          ),
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox(width: size.width, height: size.height, child: child),
          ),
        );
      },
    );
  }
}
