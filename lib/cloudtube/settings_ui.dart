import 'package:flutter/material.dart';

import 'theme.dart';

/// Свои экраны настроек в стиле CloudTube вместо библиотеки settings_ui из Clipious.
/// Те же имена и параметры (SettingsList, SettingsSection, SettingsTile…), поэтому экраны
/// перешли на новый вид без переписывания логики. Оформление: группы-карточки со скруглением,
/// иконка в круге акцентного цвета, переключатели CloudTube.

/// Цвета для мест, где экраны настроек рисуют текст сами.
class SettingsThemeData {
  final Color? settingsSectionBackground;
  final Color? settingsListBackground;
  final Color? titleTextColor;
  final Color? dividerColor;
  final Color? tileDescriptionTextColor;
  final Color? settingsTileTextColor;
  final Color? leadingIconsColor;
  final Color? tileHighlightColor;

  const SettingsThemeData({
    this.settingsSectionBackground,
    this.settingsListBackground,
    this.titleTextColor,
    this.dividerColor,
    this.tileDescriptionTextColor,
    this.settingsTileTextColor,
    this.leadingIconsColor,
    this.tileHighlightColor,
  });
}

class SettingsList extends StatelessWidget {
  final List<Widget> sections;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const SettingsList({
    super.key,
    required this.sections,
    this.shrinkWrap = false,
    this.physics,
    SettingsThemeData? lightTheme,
    SettingsThemeData? darkTheme,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // на широком экране (планшет, магнитола) не растягиваем строки на всю ширину
      final side = c.maxWidth > 860 ? (c.maxWidth - 820) / 2 : 16.0;
      return ListView(
        shrinkWrap: shrinkWrap,
        physics: physics,
        padding: EdgeInsets.fromLTRB(side, 4, side, 24),
        children: sections,
      );
    });
  }
}

class SettingsSection extends StatelessWidget {
  final Widget? title;
  final List<Widget> tiles;

  const SettingsSection({super.key, this.title, required this.tiles, EdgeInsetsDirectional? margin});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final items = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) items.add(Divider(height: 1, indent: 72, endIndent: 16, color: ctAlpha(colors.outlineVariant, 0.5)));
      items.add(tiles[i]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
          child: DefaultTextStyle.merge(
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: ctAccent(colors), letterSpacing: .2),
            child: title!,
          ),
        )
      else
        const SizedBox(height: 12),
      Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items),
      ),
    ]);
  }
}

class CustomSettingsTile extends StatelessWidget {
  final Widget child;

  const CustomSettingsTile({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}

enum _Kind { simple, navigation, toggle }

class SettingsTile extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? description;
  final Widget? value;
  final Widget? trailing;
  final void Function(BuildContext context)? onPressed;
  final void Function(bool value)? onToggle;
  final bool? initialValue;
  final bool enabled;
  final _Kind _kind;

  const SettingsTile({
    super.key,
    this.leading,
    required this.title,
    this.description,
    this.value,
    this.trailing,
    this.onPressed,
    this.enabled = true,
  })  : onToggle = null,
        initialValue = null,
        _kind = _Kind.simple;

  const SettingsTile.navigation({
    super.key,
    this.leading,
    required this.title,
    this.description,
    this.value,
    this.trailing,
    this.onPressed,
    this.enabled = true,
  })  : onToggle = null,
        initialValue = null,
        _kind = _Kind.navigation;

  const SettingsTile.switchTile({
    super.key,
    this.leading,
    required this.title,
    this.description,
    this.trailing,
    required this.initialValue,
    required this.onToggle,
    this.onPressed,
    this.enabled = true,
    Color? activeSwitchColor,
  })  : value = null,
        _kind = _Kind.toggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accent = ctAccent(colors);
    final toggle = _kind == _Kind.toggle;

    void tap() {
      if (!enabled) return;
      if (toggle) {
        onToggle?.call(!(initialValue ?? false));
      } else {
        onPressed?.call(context);
      }
    }

    final clickable = enabled && (toggle ? onToggle != null : onPressed != null);
    Widget? end = trailing;
    if (toggle) {
      end = Switch(value: initialValue ?? false, onChanged: enabled && onToggle != null ? onToggle : null);
    } else if (end == null && (_kind == _Kind.navigation || onPressed != null)) {
      end = Icon(Icons.chevron_right, color: colors.onSurfaceVariant);
    }

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: clickable ? tap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            child: Row(children: [
              if (leading != null) ...[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.13), shape: BoxShape.circle),
                  child: IconTheme.merge(data: IconThemeData(color: accent, size: 22), child: Center(child: leading!)),
                ),
                const SizedBox(width: 14),
              ] else
                const SizedBox(width: 4),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle.merge(
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 16),
                        child: title),
                    if (value != null) ...[
                      const SizedBox(height: 2),
                      DefaultTextStyle.merge(
                          style: text.bodyMedium?.copyWith(color: accent, fontWeight: FontWeight.w500),
                          child: value!),
                    ],
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      DefaultTextStyle.merge(
                          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                          child: description!),
                    ],
                  ],
                ),
              ),
              if (end != null) ...[const SizedBox(width: 8), end],
            ]),
          ),
        ),
      ),
    );
  }
}
