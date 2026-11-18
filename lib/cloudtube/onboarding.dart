import 'package:flutter/material.dart';

import 'logo.dart';
import 'theme.dart';
import 'prefs.dart';

/// Ключи элементов, которые подсвечивает обучающий тур.
class CtTourKeys {
  static final navBar = GlobalKey(debugLabel: 'ct-tour-nav');
  static final theme = GlobalKey(debugLabel: 'ct-tour-theme');
  static final search = GlobalKey(debugLabel: 'ct-tour-search');
}


class CtOnboarding {
  static bool _running = false;

  /// Первый запуск: короткий гид, затем тур по интерфейсу. Один раз.
  static Future<void> maybeStart(BuildContext context) async {
    if (_running || CtPrefs.onboardingDone.value) return;
    await start(context);
  }

  /// Запуск вручную («Профиль» → «Обучающий тур»).
  static Future<void> start(BuildContext context, {bool introToo = true}) async {
    if (_running) return;
    _running = true;
    try {
      var tour = true;
      if (introToo) {
        tour = await Navigator.of(context).push<bool>(MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => const _IntroScreen(),
            )) ??
            false;
      }
      await CtPrefs.onboardingDone.set(true);
      if (tour && context.mounted) {
        await Future.delayed(const Duration(milliseconds: 350));
        if (context.mounted) await CtTour.run(context, _steps());
      }
    } finally {
      _running = false;
    }
  }

  static List<CtTourStep> _steps() => [
        CtTourStep.navSlot(0, 4, 'Главная', 'Подборка видео. Вкладки сверху — музыка, новости, спорт, игры и другие разделы.'),
        CtTourStep.navSlot(1, 4, 'Shorts', 'Короткие вертикальные ролики. Листайте вверх и вниз, комментарии — справа.'),
        CtTourStep.navSlot(2, 4, 'Подписки', 'Новые видео каналов, на которые вы подписаны.'),
        CtTourStep.navSlot(3, 4, 'Профиль',
            'Вход в аккаунт, история, плейлисты, загрузки, обновления приложения и мастер «Свой сервер».'),
        CtTourStep(CtTourKeys.theme, 'Тема в одно касание',
            'Светлая → Пергамент → Сумерки → Тёмная. Нажимайте, пока не понравится.'),
        CtTourStep(CtTourKeys.search, 'Поиск', 'Видео, каналы и плейлисты.'),
      ];
}

class CtTourStep {
  final GlobalKey key;
  final String title;
  final String text;

  /// часть элемента по горизонтали: [slot] из [slots] (для пунктов нижнего меню)
  final int? slot;
  final int slots;

  CtTourStep(this.key, this.title, this.text)
      : slot = null,
        slots = 1;

  CtTourStep.navSlot(int this.slot, this.slots, this.title, this.text) : key = CtTourKeys.navBar;

  Rect? rect() {
    final ro = key.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) return null;
    var r = ro.localToGlobal(Offset.zero) & ro.size;
    if (slot != null) {
      final w = r.width / slots;
      r = Rect.fromLTWH(r.left + w * slot!, r.top, w, r.height);
    }
    return r.inflate(6);
  }
}

/// Тур с подсветкой элементов: затемнение с «окном» вокруг элемента и подсказкой.
class CtTour {
  static Future<void> run(BuildContext context, List<CtTourStep> steps) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    final visible = steps.where((s) => s.rect() != null).toList();
    if (visible.isEmpty) return;
    var i = 0;
    late OverlayEntry entry;
    final done = ValueNotifier(false);
    entry = OverlayEntry(
      builder: (ctx) => _TourLayer(
        step: visible[i],
        index: i,
        count: visible.length,
        onNext: () {
          if (i < visible.length - 1) {
            i++;
            entry.markNeedsBuild();
          } else {
            done.value = true;
          }
        },
        onSkip: () => done.value = true,
      ),
    );
    overlay.insert(entry);
    while (!done.value) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    entry.remove();
  }
}

class _TourLayer extends StatelessWidget {
  final CtTourStep step;
  final int index, count;
  final VoidCallback onNext, onSkip;

  const _TourLayer(
      {required this.step, required this.index, required this.count, required this.onNext, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final r = step.rect() ?? Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0);
    final colors = Theme.of(context).colorScheme;
    final below = r.center.dy < size.height / 2;
    const bubbleW = 300.0;
    final left = (r.center.dx - bubbleW / 2).clamp(12.0, size.width - bubbleW - 12);
    return Material(
      type: MaterialType.transparency,
      child: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onNext,
            child: CustomPaint(painter: _HolePainter(r, Colors.black.withValues(alpha: 0.72))),
          ),
        ),
        Positioned.fromRect(
          rect: r,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: ctAccent(colors), width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        Positioned(
          left: left,
          width: bubbleW,
          top: below ? r.bottom + 14 : null,
          bottom: below ? null : size.height - r.top + 14,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [BoxShadow(blurRadius: 24, color: Colors.black54)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(step.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(step.text, style: TextStyle(fontSize: 15, color: colors.onSurfaceVariant, height: 1.3)),
              const SizedBox(height: 6),
              Row(children: [
                Text('${index + 1} из $count', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
                const Spacer(),
                if (index < count - 1) TextButton(onPressed: onSkip, child: const Text('Пропустить')),
                FilledButton(onPressed: onNext, child: Text(index < count - 1 ? 'Далее' : 'Понятно')),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _HolePainter extends CustomPainter {
  final Rect hole;
  final Color color;

  _HolePainter(this.hole, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Path()..addRect(Offset.zero & size);
    final h = Path()..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(16)));
    canvas.drawPath(Path.combine(PathOperation.difference, bg, h), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HolePainter old) => old.hole != hole || old.color != color;
}

// ---------------- Гид первого запуска ----------------
class _Slide {
  final IconData icon;
  final String title, text;

  const _Slide(this.icon, this.title, this.text);
}

const _slides = [
  _Slide(Icons.play_circle_outline, 'Добро пожаловать',
      'CloudTube — видео в привычном виде, но без рекламы и слежки. Всё идёт через ваш сервер Invidious.'),
  _Slide(Icons.swipe_vertical_outlined, 'Shorts и комментарии',
      'Короткие ролики листаются свайпом. Комментарии, описание и рекомендации — как вы привыкли.'),
  _Slide(Icons.account_circle_outlined, 'Ваш аккаунт',
      'Войдите в аккаунт Invidious во вкладке «Профиль» — появятся подписки, история и плейлисты. На телевизоре можно войти с телефона по QR-коду.'),
  _Slide(Icons.dns_outlined, 'Свой сервер',
      'Нет сервера? «Профиль» → «Развернуть свой сервер»: нужен VPS и домен, остальное приложение сделает само.'),
];

class _IntroScreen extends StatefulWidget {
  const _IntroScreen();

  @override
  State<_IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<_IntroScreen> {
  final _pc = PageController();
  int _i = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final last = _i == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(children: [
              const CtLogo(),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Пропустить')),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: _slides.length,
              onPageChanged: (i) => setState(() => _i = i),
              itemBuilder: (_, i) {
                final s = _slides[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: CtColors.logoRed.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(s.icon, size: 72, color: CtColors.logoRed),
                    ),
                    const SizedBox(height: 32),
                    Text(s.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    Text(s.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, height: 1.4, color: colors.onSurfaceVariant)),
                  ]),
                );
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < _slides.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                width: i == _i ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _i ? CtColors.logoRed : colors.outline,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () => last
                    ? Navigator.pop(context, true)
                    : _pc.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
                child: Text(last ? 'Показать, где что' : 'Далее', style: const TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
