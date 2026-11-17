import 'package:clipious/cloudtube/tv_link.dart';
import 'package:clipious/cloudtube/connect.dart';
import 'package:clipious/cloudtube/direct.dart';
import 'package:clipious/cloudtube/updater.dart';
import 'package:clipious/cloudtube/tv_scale.dart';
import 'package:clipious/settings/models/db/settings.dart';
import 'package:clipious/cloudtube/theme.dart';
import 'package:auto_route/auto_route.dart';
import 'package:clipious/app/states/app.dart';
import 'package:clipious/extensions.dart';
import 'package:clipious/router.dart';
import 'package:clipious/utils.dart';
import 'package:clipious/utils/views/tv/components/tv_button.dart';
import 'package:clipious/utils/views/tv/components/tv_overscan.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clipious/l10n/generated/app_localizations.dart';
import 'package:locale_names/locale_names.dart';
import 'package:logging/logging.dart';

import '../../../../globals.dart';
import '../../../states/settings.dart';

var log = Logger('TvSettings');

@RoutePage()
class TVSettingsScreen extends StatelessWidget {
  const TVSettingsScreen({super.key});

  openSelectCountry(BuildContext context) {
    AppLocalizations locals = AppLocalizations.of(context)!;
    var cubit = context.read<SettingsCubit>();
    var countryNames = countryCodes.map((e) => e.name).toList();
    countryNames.sort();
    AutoRouter.of(context).push(TvSelectFromListRoute(
      title: locals.selectBrowsingCountry,
      options: countryNames,
      selected: cubit.state.country.name,
      onSelect: cubit.selectCountry,
    ));
  }

  List<String> getCategories(BuildContext context) {
    var locals = AppLocalizations.of(context)!;
    return [
      locals.popular,
      locals.trending,
      locals.subscriptions,
      locals.playlists
    ];
  }

  openManageServers(BuildContext context) {
    AutoRouter.of(context).push(const TvSettingsManageServersRoute());
  }

  openSponsorBlockSettings(BuildContext context) {
    AutoRouter.of(context).push(const TvSponsorBlockSettingsRoute());
  }

  openDearrowSettings(BuildContext context) {
    AutoRouter.of(context).push(const TvDearrowSettingsRoute());
  }

  openSearchHistorySettings(BuildContext context) {
    AutoRouter.of(context).push(const TvSearchHistorySettingsRoute());
  }

  openAppLayout(BuildContext context) {
    AutoRouter.of(context).push(const TvAppLayoutSettingsRoute());
  }

  showSelectLanguage(BuildContext context) {
    var localsList = AppLocalizations.supportedLocales;
    var localsStrings =
        localsList.map((e) => e.nativeDisplayLanguageScript).toList();
    var locals = AppLocalizations.of(context)!;
    var cubit = context.read<SettingsCubit>();

    List<String>? localeString = cubit.state.locale?.split('_');
    Locale? selected = localeString != null
        ? Locale.fromSubtags(
            languageCode: localeString[0],
            scriptCode: localeString.length >= 2 ? localeString[1] : null)
        : null;

    AutoRouter.of(context).push(TvSelectFromListRoute(
      title: locals.appLanguage,
      options: [locals.followSystem, ...localsStrings],
      selected: selected?.nativeDisplayLanguageScript ?? locals.followSystem,
      onSelect: (String selected) {
        if (selected == locals.followSystem) {
          cubit.setLocale(localsList, localsStrings, null);
        } else {
          cubit.setLocale(localsList, localsStrings, selected);
        }
      },
    ));
  }

  selectTheme(BuildContext context) {
    var locals = AppLocalizations.of(context)!;
    var cubit = context.read<SettingsCubit>();
    AutoRouter.of(context).push(TvSelectFromListRoute(
      title: locals.themeBrightness,
      options:
          ThemeMode.values.map((e) => cubit.getThemeLabel(locals, e)).toList(),
      selected: cubit.getThemeLabel(locals, cubit.state.themeMode),
      onSelect: (String selected) {
        ThemeMode? theme = ThemeMode.values.firstWhereOrNull(
            (element) => cubit.getThemeLabel(locals, element) == selected);
        cubit.setThemeMode(theme);
      },
    ));
  }

  showCustomRydUrl(BuildContext context) {
    var locals = AppLocalizations.of(context)!;
    var cubit = context.read<SettingsCubit>();
    final controller =
        TextEditingController(text: cubit.state.returnYoutubeDislikeUrl);

    FocusNode focusNode = FocusNode();
    showTvDialog(
      title: 'URL',
      context: context,
      actions: [
        TvButton(
          onPressed: (context) {
            Navigator.pop(context);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16),
            child: Text(locals.cancel),
          ),
        ),
        TvButton(
          onPressed: (context) async {
            String newUrl = controller.text.trim();

            if (newUrl.isNotEmpty &&
                !newUrl.startsWith("http://") &&
                !newUrl.startsWith("https://")) {
              showTvAlertdialog(context, locals.error,
                  [Text(locals.customizeAppLayoutExplanation)]);
              return;
            }

            newUrl = newUrl.trim();
            if (newUrl.isNotEmpty && !newUrl.endsWith("/")) {
              newUrl += "/";
            }

            cubit.setReturnYoutubeDislikeUrl(newUrl);
            Navigator.of(context).pop();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16),
            child: Text(locals.save),
          ),
        ),
      ],
      builder: (BuildContext context) => [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                autofocus: true,
                focusNode: focusNode,
                textInputAction: TextInputAction.next,
                controller: controller,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [],
              ),
            ],
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations locals = AppLocalizations.of(context)!;

    TextTheme textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: TvOverscan(
        child: BlocBuilder<SettingsCubit, SettingsState>(
            builder: (context, state) {
          var cubit = context.read<SettingsCubit>();
          return DefaultTextStyle(
            style: textTheme.bodyLarge!,
            child: CtTvTileScope(child: ListView(
              children: ctTvTiles([
                SettingsTitle(title: locals.browsing),
                SettingsTile(
                  title: locals.customizeAppLayout,
                  leading: const Icon(Icons.dashboard_customize_outlined),
                  description:
                      state.appLayout.map((e) => e.getLabel(locals)).join(", "),
                  onSelected: (context) => openAppLayout(context),
                ),
                SettingsTile(
                  title: locals.country,
                  leading: const Icon(Icons.public),
                  description: state.country.name,
                  onSelected: (context) => openSelectCountry(context),
                ),
                SettingsTile(
                  title: locals.appLanguage,
                  leading: const Icon(Icons.translate),
                  description:
                      cubit.getLocaleDisplayName() ?? locals.followSystem,
                  onSelected: (context) => showSelectLanguage(context),
                ),
                SettingsTile(
                  title: 'Return YouTube Dislike',
                  leading: const Icon(Icons.thumb_down_alt_outlined),
                  description: locals.returnYoutubeDislikeDescription,
                  onSelected: (context) => cubit.toggleReturnYoutubeDislike(
                      !state.useReturnYoutubeDislike),
                  trailing: Switch(
                      onChanged: (value) {},
                      value: state.useReturnYoutubeDislike),
                ),
                SettingsTile(
                  title: locals.rydCustomInstance,
                  leading: const Icon(Icons.dns_outlined),
                  description:
                      '${state.returnYoutubeDislikeUrl.isNotEmpty ? '${locals.currentServer(state.returnYoutubeDislikeUrl)}\n' : ''}${locals.rydCustomInstanceDescription}',
                  enabled: state.useReturnYoutubeDislike,
                  onSelected: (context) => showCustomRydUrl(context),
                ),
                SettingsTile(
                  title: locals.searchHistory,
                  leading: const Icon(Icons.manage_search),
                  description: locals.searchHistoryDescription,
                  onSelected: openSearchHistorySettings,
                ),
                SettingsTile(
                  title: 'DeArrow',
                  leading: const Icon(Icons.auto_fix_high),
                  description: state.dearrow
                      ? locals.enabled
                      : locals.deArrowSettingDescription,
                  onSelected: openDearrowSettings,
                ),
                SettingsTile(
                  title: locals.videoFilters,
                  leading: const Icon(Icons.filter_alt_outlined),
                  description: locals.videoFiltersSettingTileDescriptions,
                  onSelected: (context) => AutoRouter.of(context)
                      .push(const TvFilterListSettingsRoute()),
                ),
                SettingsTitle(title: locals.servers),
                BlocBuilder<AppCubit, AppState>(
                    buildWhen: (previous, current) =>
                        previous.server != current.server,
                    builder: (context, app) {
                      return SettingsTile(
                          title: locals.manageServers,
                  leading: const Icon(Icons.dns),
                          description: app.server != null
                              ? locals.currentServer(app.server!.url)
                              : "",
                          onSelected: openManageServers);
                    }),
                SettingsTitle(title: locals.videoPlayer),
                SettingsTile(
                  title: 'Автовоспроизведение',
                  leading: const Icon(Icons.playlist_play),
                  description: 'После ролика — следующий из рекомендаций',
                  onSelected: (context) => cubit.setPlayRecommendedNext(!state.playRecommendedNext),
                  trailing: Switch(onChanged: (value) {}, value: state.playRecommendedNext),
                ),
                SettingsTile(
                  title: locals.useDash,
                  leading: const Icon(Icons.high_quality_outlined),
                  description: locals.useDashDescription,
                  onSelected: (context) => cubit.toggleDash(!state.useDash),
                  trailing: Switch(onChanged: (value) {}, value: state.useDash),
                ),
                SettingsTile(
                  title: locals.useProxy,
                  leading: const Icon(Icons.shield_outlined),
                  description: locals.useProxyDescription,
                  onSelected: (context) => cubit.toggleProxy(!state.useProxy),
                  trailing:
                      Switch(onChanged: (value) {}, value: state.useProxy),
                ),
                AdjustmentSettingTile(
                  title: locals.skipStep,
                  leading: const Icon(Icons.forward_10),
                  value: state.skipStep.floor(),
                  description: locals.skipStepDescription,
                  possibleValues: skipSteps,
                  onNewValue: cubit.setSkipStep,
                ),
                SettingsTile(
                  title: locals.exponentialSkip,
                  leading: const Icon(Icons.fast_forward),
                  description: locals.exponentialSkipDescription,
                  onSelected: (context) =>
                      cubit.setSkipExponentially(!state.skipExponentially),
                  trailing: Switch(
                      onChanged: (value) {}, value: state.skipExponentially),
                ),
                AdjustmentSettingTile(
                  title: locals.subtitleFontSize,
                  leading: const Icon(Icons.format_size),
                  value: state.subtitleSize.floor(),
                  step: 1,
                  description: locals.subtitleFontSizeDescription,
                  onNewValue: cubit.setSubtitleSize,
                ),
                SettingsTile(
                  title: locals.subtitlesBackground,
                  leading: const Icon(Icons.subtitles_outlined),
                  description: locals.subtitlesBackgroundDescription,
                  onSelected: (context) =>
                      cubit.setSubtitlesBackground(!state.subtitlesBackground),
                  trailing: Switch(
                      onChanged: (value) {}, value: state.subtitlesBackground),
                ),
                SettingsTile(
                  title: locals.rememberSubtitleLanguage,
                  leading: const Icon(Icons.closed_caption_outlined),
                  description: locals.rememberSubtitleLanguageDescription,
                  onSelected: (context) =>
                      cubit.toggleRememberSubtitles(!state.rememberSubtitles),
                  trailing: Switch(
                      onChanged: (value) {}, value: state.rememberSubtitles),
                ),
                SettingsTile(
                  title: locals.rememberPlaybackSpeed,
                  leading: const Icon(Icons.speed),
                  description: locals.rememberPlaybackSpeedDescription,
                  onSelected: (context) => cubit.toggleRememberPlaybackSpeed(
                      !state.rememberPlayBackSpeed),
                  trailing: Switch(
                      onChanged: (value) {},
                      value: state.rememberPlayBackSpeed),
                ),
                SettingsTile(
                  title: 'SponsorBlock',
                  leading: const Icon(Icons.block),
                  description: locals.sponsorBlockDescription,
                  onSelected: openSponsorBlockSettings,
                ),
                SettingsTitle(title: locals.appearance),
                SettingsTile(
                  title: locals.themeBrightness,
                  leading: const Icon(Icons.brightness_6_outlined),
                  description: cubit.getThemeLabel(locals, state.themeMode),
                  onSelected: (context) => selectTheme(context),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: ctTvScale,
                  builder: (context, scale, _) => SettingsTile(
                    title: 'Масштаб интерфейса',
                    description: '${(scale * 100).round()} % — нажмите, чтобы изменить',
                    leading: const Icon(Icons.aspect_ratio),
                    onSelected: (context) {
                      final i = ctTvScales.indexWhere((v) => (v - scale).abs() < 0.01);
                      ctSetTvScale(ctTvScales[(i + 1) % ctTvScales.length]);
                    },
                  ),
                ),
                SettingsTile(
                  title: 'Режим работы',
                  description: ctDirectActive
                      ? 'Без сервера — YouTube напрямую. Нажмите, чтобы подключить свой сервер с телефона'
                      : 'Свой сервер. Нажмите, чтобы смотреть без сервера (YouTube напрямую)',
                  leading: const Icon(Icons.swap_horiz),
                  onSelected: (context) async {
                    if (ctDirectActive) {
                      await Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const CtTvLinkScreen()));
                    } else {
                      await ctConnectDirect(context.read<AppCubit>());
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Включён режим без сервера — YouTube напрямую')));
                      }
                    }
                  },
                ),
                SettingsTile(
                  title: 'Проверить обновления',
                  leading: const Icon(Icons.system_update),
                  onSelected: (context) => CtUpdater.check(context, manual: true),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: ctSoftTheme,
                  builder: (context, soft, _) {
                    final cur = CtTheme.of(Theme.of(context).brightness == Brightness.dark, soft);
                    return SettingsTile(
                      title: 'Тема CloudTube',
                      description: '${cur.label} — нажмите, чтобы переключить: ${cur.next.label}',
                      leading: Icon(cur.icon),
                      onSelected: (context) async {
                        final next = cur.next;
                        ctSoftTheme.value = next.isSoft;
                        await db.saveSetting(SettingsValue(ctSoftThemeKey, '${next.isSoft}'));
                        await cubit.setThemeMode(next.isDark ? ThemeMode.dark : ThemeMode.light);
                      },
                    );
                  },
                ),
                SettingsTile(
                  title: locals.blackBackground,
                  leading: const Icon(Icons.dark_mode_outlined),
                  description: locals.blackBackgroundDescription,
                  onSelected: (context) =>
                      cubit.toggleBlackBackground(!state.blackBackground),
                  trailing: Switch(
                      onChanged: (value) {}, value: state.blackBackground),
                ),
                SettingsTile(
                  title: locals.forceTvUi,
                  leading: const Icon(Icons.tv),
                  description: locals.forceTvUiExplanation,
                  onSelected: (context) => cubit.setForceTvUi(!state.forceTvUi),
                  trailing:
                      Switch(onChanged: (value) {}, value: state.forceTvUi),
                ),
                SettingsTitle(title: locals.about),
                SettingsTile(
                  title: '${locals.name}: ${state.packageInfo.appName}',
                  leading: const Icon(Icons.info_outline),
                  description:
                      '${locals.package}: ${state.packageInfo.packageName}',
                  onSelected: (context) {},
                ),
                SettingsTile(
                  title: '${locals.version}: ${state.packageInfo.version}',
                  leading: const Icon(Icons.new_releases_outlined),
                  description:
                      '${locals.build}: ${state.packageInfo.buildNumber}',
                  onSelected: (context) {},
                )
              ]),
            )),
          );
        }),
      ),
    );
  }
}

class SettingsTitle extends StatelessWidget {
  final String title;

  const SettingsTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    var textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(
        left: 16.0,
        top: 20,
        bottom: 4,
      ),
      child: Text(
        title,
        style: textTheme.titleMedium?.copyWith(color: colors.onSurfaceVariant, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class AdjustmentSettingTile extends StatelessWidget {
  final String title;
  final int value;
  final int? step;
  final List<int>? possibleValues;
  final String? description;
  final Function(int) onNewValue;
  final Widget? leading;

  const AdjustmentSettingTile(
      {super.key,
      this.leading,
      required this.onNewValue,
      required this.title,
      this.description,
      required this.value,
      this.possibleValues,
      this.step})
      : assert(step == null || possibleValues == null,
            'Can\' have both step and possible values');

  KeyEventResult onKeyEvent(FocusNode node, KeyEvent event, BuildContext ctx) {
    if (event is KeyUpEvent) {
      log.fine('onTvSelect, ${event.logicalKey}, $event');
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (step != null) {
          onNewValue(value - step!);
        } else if (possibleValues != null) {
          int index = possibleValues!.indexOf(value);
          if (index > 0) {
            onNewValue(possibleValues![index - 1]);
          }
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (step != null) {
          onNewValue(value + step!);
        } else if (possibleValues != null) {
          int index = possibleValues!.indexOf(value);
          if (index < possibleValues!.length - 1) {
            onNewValue(possibleValues![index + 1]);
          }
        }
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    TextTheme textTheme = Theme.of(context).textTheme;
    if (CtTvTileScope.active(context)) {
      // в сетке плиток стрелки двигают фокус, поэтому значение меняется кнопкой ОК (по кругу)
      return SettingsTile(
        title: title,
        description: 'Сейчас: ${value.floor()} — ОК, чтобы изменить',
        leading: leading,
        onSelected: (_) {
          if (possibleValues != null && possibleValues!.isNotEmpty) {
            final i = possibleValues!.indexOf(value);
            onNewValue(possibleValues![(i + 1) % possibleValues!.length]);
          } else {
            final st = step ?? 1;
            onNewValue(value + st > 40 ? 10 : value + st);
          }
        },
      );
    }
    return SettingsTile(
      title: title,
      description: description,
      leading: leading,
      onKeyEvent: onKeyEvent,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 8.0),
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.chevron_left),
            ),
          ),
          Text(
            value.floor().toString(),
            style: textTheme.bodyLarge,
          ),
          const Padding(
            padding: EdgeInsets.only(left: 8.0),
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.chevron_right),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  final bool? autofocus;
  final String title;
  final bool? enabled;
  final String? description;
  final Function(BuildContext context)? onSelected;
  final Widget? trailing;
  final Widget? leading;
  final KeyEventResult Function(FocusNode, KeyEvent, BuildContext)? onKeyEvent;

  const SettingsTile(
      {super.key,
      required this.title,
      this.description,
      this.onSelected,
      this.trailing,
      this.autofocus,
      this.leading,
      this.enabled,
      this.onKeyEvent});

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    TextTheme textTheme = Theme.of(context).textTheme;
    if (CtTvTileScope.active(context)) return _tile(context, colors, textTheme);
    return Focus(
        canRequestFocus: enabled,
        autofocus: autofocus ?? false,
        onKeyEvent: (node, event) => onKeyEvent != null
            ? onKeyEvent!(node, event, context)
            : onTvSelect(event, context,
                onSelected != null ? onSelected! : (context) {}),
        child: Builder(builder: (ctx) {
          final FocusNode focusNode = Focus.of(ctx);
          final bool hasFocus = focusNode.hasFocus;
          return ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            enabled: enabled ?? true,
            leading: leading,
            trailing: trailing,
            selectedTileColor: ctAccent(colors).withValues(alpha: 0.12),
            selected: hasFocus,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                    color: hasFocus ? ctAccent(colors) : Colors.transparent, width: 3)),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleMedium!.copyWith(
                      fontWeight: FontWeight.w600,
                      color: enabled ?? true
                          ? colors.primary
                          : colors.primary.withValues(alpha: 0.5)),
                ),
                description != null
                    ? Text(
                        description ?? '',
                        style: textTheme.bodySmall!
                            .copyWith(color: colors.onSurfaceVariant),
                      )
                    : const SizedBox.shrink()
              ],
            ),
          );
        }));
  }

  /// Плитка: скруглённая карточка с иконкой, названием и коротким описанием.
  Widget _tile(BuildContext context, ColorScheme colors, TextTheme textTheme) {
    final on = enabled ?? true;
    return Focus(
        canRequestFocus: enabled,
        autofocus: autofocus ?? false,
        onKeyEvent: (node, event) => onKeyEvent != null
            ? onKeyEvent!(node, event, context)
            : onTvSelect(event, context, onSelected != null ? onSelected! : (context) {}),
        child: Builder(builder: (ctx) {
          final hasFocus = Focus.of(ctx).hasFocus;
          final accent = ctAccent(colors);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 214,
            height: 74,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: hasFocus ? accent.withValues(alpha: 0.16) : colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: hasFocus ? accent : Colors.transparent, width: 2),
            ),
            child: Opacity(
              opacity: on ? 1 : 0.45,
              child: Row(children: [
                IconTheme(
                  data: IconThemeData(size: 22, color: hasFocus ? accent : colors.primary),
                  child: leading ?? const Icon(Icons.tune),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium!.copyWith(
                                fontWeight: FontWeight.w700, color: colors.onSurface, height: 1.15)),
                        if ((description ?? '').isNotEmpty)
                          Text(description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall!
                                  .copyWith(color: colors.onSurfaceVariant, height: 1.15)),
                      ]),
                ),
                if (trailing != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 64, maxHeight: 26),
                        child: FittedBox(child: trailing)),
                  ),
              ]),
            ),
          );
        }));
  }
}

/// Внутри — пункты настроек рисуются плитками (а не строками).
class CtTvTileScope extends InheritedWidget {
  const CtTvTileScope({super.key, required super.child});

  static bool active(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CtTvTileScope>() != null;

  @override
  bool updateShouldNotify(CtTvTileScope oldWidget) => false;
}

/// Заголовки разделов — как есть, пункты между ними — сеткой плиток.
List<Widget> ctTvTiles(List<Widget> children) {
  final out = <Widget>[];
  var cur = <Widget>[];
  void flush() {
    if (cur.isEmpty) return;
    out.add(Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Wrap(spacing: 10, runSpacing: 10, children: cur),
    ));
    cur = <Widget>[];
  }

  for (final w in children) {
    if (w is SettingsTitle) {
      flush();
      out.add(w);
    } else {
      cur.add(w);
    }
  }
  flush();
  return out;
}
