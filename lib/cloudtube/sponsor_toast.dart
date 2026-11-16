import 'dart:async';

import 'package:flutter/material.dart';

import '../globals.dart';
import '../settings/models/db/settings.dart';
import '../videos/models/sponsor_segment_types.dart';

/// Сообщение в кадре о пропущенном фрагменте SponsorBlock (как в SmartTube).
final ctSponsorToast = ValueNotifier<String?>(null);
Timer? _hide;

void ctShowSponsorToast(String text) {
  ctSponsorToast.value = text;
  _hide?.cancel();
  _hide = Timer(const Duration(seconds: 4), () => ctSponsorToast.value = null);
}

String ctSponsorLabel(SponsorSegmentType t) => switch (t) {
      SponsorSegmentType.sponsor => 'Спонсор',
      SponsorSegmentType.selfpromo => 'Самореклама',
      SponsorSegmentType.interaction => 'Призыв подписаться',
      SponsorSegmentType.intro => 'Вступление',
      SponsorSegmentType.outro => 'Концовка',
      SponsorSegmentType.preview => 'Анонс',
      SponsorSegmentType.musicOffTopic => 'Не музыка',
      SponsorSegmentType.filler => 'Отступление',
    };

/// По умолчанию (пока пользователь ничего не менял) пропускаем рекламу спонсора,
/// самопиар и призывы подписаться — как в SmartTube.
Future<void> ctSponsorDefaults() async {
  for (final t in const [SponsorSegmentType.sponsor, SponsorSegmentType.selfpromo, SponsorSegmentType.interaction]) {
    if (db.getSettings(t.settingsName()) == null) {
      await db.saveSetting(SettingsValue(t.settingsName(), 'true'));
    }
  }
}

/// Плашка внизу слева поверх видео.
class CtSponsorToast extends StatelessWidget {
  const CtSponsorToast({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: ctSponsorToast,
      builder: (context, text, _) => AnimatedOpacity(
        opacity: text == null ? 0 : 1,
        duration: const Duration(milliseconds: 250),
        child: text == null
            ? const SizedBox.shrink()
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(text, style: const TextStyle(color: Colors.white, fontSize: 16)),
                ]),
              ),
      ),
    );
  }
}
