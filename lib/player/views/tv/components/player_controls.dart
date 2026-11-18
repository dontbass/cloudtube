import '../../../../cloudtube/sponsor_toast.dart';
import '../../../../cloudtube/tv_channels.dart';
import '../../../../cloudtube/up_next.dart';
import '../../../../cloudtube/tv_mouse.dart';
import 'package:flutter/gestures.dart';
import '../../../../cloudtube/theme.dart';
import 'package:cloudtube/player/states/tv_player_controls.dart';
import 'package:cloudtube/player/views/tv/components/player_settings.dart';
import 'package:cloudtube/utils/views/components/thumbnail.dart';
import 'package:cloudtube/utils/views/tv/components/tv_button.dart';
import 'package:cloudtube/utils/views/tv/components/tv_horizontal_item_list.dart';
import 'package:cloudtube/utils/views/tv/components/tv_overscan.dart';
import 'package:cloudtube/videos/models/video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloudtube/l10n/generated/app_localizations.dart';

import '../../../../globals.dart';
import '../../../../utils.dart';
import '../../../../utils/models/image_object.dart';
import '../../../../utils/models/paginated_list.dart';
import '../../../states/player.dart';

class TvPlayerControls extends StatelessWidget {
  const TvPlayerControls({super.key});

  onVideoQueueSelected(
      BuildContext context, TvPlayerControlsCubit cubit, Video video) {
    cubit.playFromQueue(video);
  }

  @override
  Widget build(BuildContext context) {
    TextTheme textTheme = Theme.of(context).textTheme;
    var locals = AppLocalizations.of(context)!;
    var player = context.read<PlayerCubit>();
    return BlocProvider(
      create: (context) =>
          TvPlayerControlsCubit(const TvPlayerControlsState(), player),
      child: BlocBuilder<TvPlayerControlsCubit, TvPlayerControlsState>(
        builder: (context, playerState) {
          var cubit = context.read<TvPlayerControlsCubit>();
          var currentlyPlaying = context
              .select((PlayerCubit value) => value.state.currentlyPlaying);
          final ctAuthorId = currentlyPlaying?.authorId ?? '';
          var videos =
              context.select((PlayerCubit value) => value.state.videos);
          var isPlaying =
              context.select((PlayerCubit value) => value.state.isPlaying);
          var position =
              context.select((PlayerCubit value) => value.state.position);

          return BlocListener<PlayerCubit, PlayerState>(
            listenWhen: (previous, current) =>
                previous.mediaEvent != current.mediaEvent,
            listener: (BuildContext context, state) {
              cubit.onStreamEvent(state.mediaEvent);
            },
            child: Focus(
              autofocus: true,
              onKeyEvent: (node, event) =>
                  cubit.handleRemoteEvents(node, event),
              // мышь: движение показывает панель, колесо — перемотка ±10 с
              child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerHover: (_) => cubit.ctMouseMoved(),
              onPointerSignal: (e) {
                if (e is PointerScrollEvent && e.scrollDelta.dy != 0) cubit.ctMouseWheel(e.scrollDelta.dy > 0);
              },
              child: Stack(
                children: [
                  // SponsorBlock: «Пропущен фрагмент …» поверх видео
                  const Positioned(left: 56, bottom: 120, child: CtSponsorToast()),
                  // «Далее: …» за 10 секунд до конца
                  const Positioned(right: 56, bottom: 120, child: CtUpNextCard()),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedOpacity(
                      opacity: playerState.controlsOpacity,
                      duration: animationDuration,
                      child: Container(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                              Colors.black.withValues(alpha: 1),
                              Colors.black.withValues(alpha: 0),
                              Colors.black.withValues(alpha: 1)
                            ])),
                      ),
                    ),
                  ),
                  Positioned(
                      child: TvOverscan(
                    child: playerState.showSettings
                        ? const TvPlayerSettings()
                        : const SizedBox.shrink(),
                  )),
                  Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: playerState.showSettings
                          ? const SizedBox.shrink()
                          : AnimatedOpacity(
                              opacity: playerState.controlsOpacity,
                              duration: animationDuration,
                              child: TvOverscan(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      currentlyPlaying?.title ?? '',
                                      style: textTheme.headlineLarge
                                          ?.copyWith(color: Colors.white),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 16.0),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // нет картинки канала (без сервера она приходит не всегда) —
                                          // буква канала вместо значка ошибки «!»
                                          if ((currentlyPlaying?.authorThumbnails ?? const []).isEmpty)
                                            CircleAvatar(
                                              radius: 20,
                                              backgroundColor: Colors.white24,
                                              child: Text(
                                                (currentlyPlaying?.author ?? '?').characters.firstOrNull?.toUpperCase() ?? '?',
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                              ),
                                            )
                                          else
                                          Thumbnail(
                                            thumbnails: ImageObject
                                                .getThumbnailUrlsByPreferredOrder(
                                                    currentlyPlaying
                                                        ?.authorThumbnails),
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(20)),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                left: 8.0, right: 20),
                                            child: Text(
                                              currentlyPlaying?.author ?? '',
                                              style: textTheme.headlineSmall
                                                  ?.copyWith(
                                                      color: Colors.white),
                                            ),
                                          )
                                        ],
                                      ),
                                    ),
                                    // качество и сколько осталось
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10.0),
                                      child: ValueListenableBuilder<String?>(
                                        valueListenable: ctNowQuality,
                                        builder: (context, q, _) {
                                          final len = currentlyPlaying?.lengthSeconds ?? 0;
                                          final left = len - position.inSeconds;
                                          final parts = [
                                            if (q != null) q,
                                            if (len > 0 && left > 0 && currentlyPlaying?.liveNow != true)
                                              'осталось ${_ctFmt(left)}',
                                          ];
                                          return Text(parts.join('  ·  '),
                                              style: textTheme.titleMedium?.copyWith(color: Colors.white70));
                                        },
                                      ),
                                    )
                                  ],
                                ),
                              ),
                            )),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedOpacity(
                      opacity: playerState.controlsOpacity,
                      duration: animationDuration,
                      child: TvOverscan(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            playerState.displayControls
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0, vertical: 16),
                                    child: FocusScope(
                                      child: Row(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                right: 16.0),
                                            child: TvButton(
                                              onPressed: (context) =>
                                                  player.togglePlaying(),
                                              unfocusedColor:
                                                  Colors.transparent,
                                              autofocus: true,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(8.0),
                                                child: Icon(
                                                  isPlaying
                                                      ? Icons.pause
                                                      : Icons.play_arrow,
                                                  size: 50,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Visibility(
                                            visible: videos.length > 1,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 16.0),
                                              child: TvButton(
                                                onPressed: (context) =>
                                                    player.playPrevious(),
                                                unfocusedColor:
                                                    Colors.transparent,
                                                child: const Padding(
                                                  padding: EdgeInsets.all(8.0),
                                                  child: Icon(
                                                    Icons.skip_previous,
                                                    size: 50,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                right: 16.0),
                                            child: TvButton(
                                              unfocusedColor:
                                                  Colors.transparent,
                                              onPressed: (context) =>
                                                  cubit.fastRewind(),
                                              child: const Padding(
                                                padding: EdgeInsets.all(8.0),
                                                child: Icon(
                                                  Icons.fast_rewind,
                                                  size: 50,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                right: 16.0),
                                            child: TvButton(
                                              onPressed: (context) =>
                                                  cubit.fastForward(),
                                              unfocusedColor:
                                                  Colors.transparent,
                                              child: const Padding(
                                                padding: EdgeInsets.all(8.0),
                                                child: Icon(
                                                  Icons.fast_forward,
                                                  size: 50,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Visibility(
                                            // и когда очередь кончилась — следующим пойдёт рекомендация
                                            visible: videos.length > 1 || player.ctHasNext,
                                            child: TvButton(
                                              onPressed: (context) =>
                                                  player.playNext(),
                                              unfocusedColor:
                                                  Colors.transparent,
                                              child: const Padding(
                                                padding: EdgeInsets.all(8.0),
                                                child: Icon(
                                                  Icons.skip_next,
                                                  size: 50,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Expanded(child: Container()),
                                          // канал автора и подписка — прямо из плеера
                                          if (ctAuthorId.isNotEmpty) ...[
                                            Padding(
                                              padding: const EdgeInsets.only(right: 16.0),
                                              child: CtTvChip(
                                                icon: const Icon(Icons.account_circle_outlined, size: 26),
                                                label: 'Канал',
                                                onPressed: (ctx) {
                                                  player.pause();
                                                  ctOpenTvChannel(ctx, ctAuthorId);
                                                },
                                              ),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.only(right: 16.0),
                                              child: CtTvSubscribeChip(
                                                  key: ValueKey('sub-$ctAuthorId'), channelId: ctAuthorId),
                                            ),
                                          ],
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                right: 16.0),
                                            child: TvButton(
                                              onPressed: (context) =>
                                                  cubit.displayQueue(),
                                              unfocusedColor:
                                                  Colors.transparent,
                                              child: const Padding(
                                                padding: EdgeInsets.all(8.0),
                                                child: Icon(
                                                  Icons.video_library,
                                                  size: 30,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                right: 16.0),
                                            child: TvButton(
                                              onPressed: (context) =>
                                                  cubit.displaySettings(),
                                              unfocusedColor:
                                                  Colors.transparent,
                                              child: const Padding(
                                                padding: EdgeInsets.all(8.0),
                                                child: Icon(
                                                  Icons.settings,
                                                  size: 30,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                (currentlyPlaying?.liveNow ?? false)
                                    ? Container(
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius:
                                              BorderRadius.circular(30),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8.0, vertical: 2),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.podcasts,
                                                size: 15,
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    left: 8.0),
                                                child: Text(
                                                  locals.streamIsLive,
                                                  style: textTheme.bodyLarge,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : Expanded(
                                        // полоса перемотки: при перемотке стрелками — толще, с меткой
                                        child: ValueListenableBuilder<Duration?>(
                                          valueListenable: cubit.ctSeek,
                                          builder: (context, seek, _) {
                                            final total = player.duration.inMilliseconds;
                                            final f = seek != null && total > 0
                                                ? (seek.inMilliseconds / total).clamp(0.0, 1.0)
                                                : player.progress;
                                            if (f < 0) return const SizedBox.shrink();
                                            final accent = ctAccent(Theme.of(context).colorScheme);
                                            final h = seek != null ? 12.0 : 8.0;
                                            return LayoutBuilder(builder: (context, c) {
                                              // мышь: клик по полосе — перейти в это место, можно тянуть
                                              void at(Offset local, {bool commit = false}) => cubit.ctMouseSeek(
                                                  (local.dx / c.maxWidth).clamp(0.0, 1.0),
                                                  commit: commit);
                                              return Listener(
                                                behavior: HitTestBehavior.opaque,
                                                onPointerDown: (e) {
                                                  ctMouseSkipClick = true;
                                                  at(e.localPosition);
                                                },
                                                onPointerMove: (e) => at(e.localPosition),
                                                onPointerUp: (e) => at(e.localPosition, commit: true),
                                                child: MouseRegion(
                                                cursor: SystemMouseCursors.click,
                                                child: SizedBox(
                                                height: 28,
                                                child: Stack(
                                                  alignment: Alignment.centerLeft,
                                                  clipBehavior: Clip.none,
                                                  children: [
                                                    Container(
                                                      height: h,
                                                      decoration: BoxDecoration(
                                                          color: Colors.white.withValues(alpha: 0.25),
                                                          borderRadius: BorderRadius.circular(6)),
                                                    ),
                                                    // сколько уже просмотрено (реальная позиция)
                                                    if (seek != null && player.progress > 0)
                                                      Container(
                                                        width: c.maxWidth * player.progress.clamp(0.0, 1.0),
                                                        height: h,
                                                        decoration: BoxDecoration(
                                                            color: Colors.white.withValues(alpha: 0.45),
                                                            borderRadius: BorderRadius.circular(6)),
                                                      ),
                                                    Container(
                                                      width: c.maxWidth * f,
                                                      height: h,
                                                      decoration: BoxDecoration(
                                                          color: seek != null ? accent : Colors.white,
                                                          borderRadius: BorderRadius.circular(6)),
                                                    ),
                                                    if (seek != null)
                                                      Positioned(
                                                        left: (c.maxWidth * f - 12).clamp(0.0, c.maxWidth - 24),
                                                        child: Container(
                                                          width: 24,
                                                          height: 24,
                                                          decoration: BoxDecoration(
                                                              color: Colors.white,
                                                              shape: BoxShape.circle,
                                                              border: Border.all(color: accent, width: 4)),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              )));
                                            });
                                          },
                                        )),
                                if (!(currentlyPlaying?.liveNow ?? false))
                                  Padding(
                                    padding: const EdgeInsets.only(left: 16.0),
                                    child: ValueListenableBuilder<Duration?>(
                                      valueListenable: cubit.ctSeek,
                                      builder: (context, seek, _) => Text(
                                        '${prettyDurationCustom(seek ?? position)} / ${prettyDurationCustom(player.duration)}',
                                        style: textTheme.titleLarge
                                            ?.copyWith(color: seek != null ? const Color(0xFF8AB4F8) : Colors.white),
                                      ),
                                    ),
                                  )
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                      left: 0,
                      bottom: 50,
                      right: 0,
                      child: AnimatedSwitcher(
                          duration: animationDuration,
                          child: playerState.showQueue
                              ? TvOverscan(
                                  child: FocusScope(
                                  autofocus: true,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        locals.videoQueue,
                                        style: textTheme.titleLarge,
                                      ),
                                      TvHorizontalVideoList(
                                          onSelect: (ctx, video) =>
                                              onVideoQueueSelected(
                                                  ctx, cubit, video),
                                          paginatedVideoList:
                                              FixedItemList(videos)),
                                    ],
                                  ),
                                ))
                              : const SizedBox.shrink()))
                ],
              )),
            ),
          );
        },
      ),
    );
  }
}

String _ctFmt(int s) {
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}
