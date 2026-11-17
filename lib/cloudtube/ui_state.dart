import 'package:flutter/material.dart';

import 'theme.dart';

/// Общие состояния экранов CloudTube: ошибка с «Повторить» и пустой список.
/// Один вид на всех экранах — вместо бесконечного кружка или пустоты.
class CtErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool autofocus;

  const CtErrorView({super.key, this.message = 'Не удалось загрузить', this.onRetry, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    return CtEmptyView(
      icon: Icons.cloud_off_rounded,
      text: message,
      action: onRetry == null
          ? null
          : FilledButton.icon(
              autofocus: autofocus,
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Повторить')),
    );
  }
}

class CtEmptyView extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const CtEmptyView({super.key, required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: ctAccent(colors).withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 36, color: ctAccent(colors)),
          ),
          const SizedBox(height: 14),
          Text(text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colors.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

/// Сохраняет состояние вкладки (прокрутку, загруженные страницы) при переключении.
class CtKeepAlive extends StatefulWidget {
  final Widget child;

  const CtKeepAlive({super.key, required this.child});

  @override
  State<CtKeepAlive> createState() => _CtKeepAliveState();
}

class _CtKeepAliveState extends State<CtKeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
