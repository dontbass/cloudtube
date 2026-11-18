import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloudtube/globals.dart';
import 'package:cloudtube/main.dart' show isTv;
import 'package:cloudtube/settings/models/db/server.dart';
import 'package:cloudtube/utils/states/thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Server? _ctSrv;
DateTime _ctSrvAt = DateTime(2000);
Future<Server?>? _ctSrvFut;

Future<Server?> _ctServer() {
  if (_ctSrv != null && DateTime.now().difference(_ctSrvAt) < const Duration(seconds: 15)) {
    return Future.value(_ctSrv);
  }
  return _ctSrvFut ??= db.getCurrentlySelectedServer().then<Server?>((s) {
    _ctSrv = s;
    _ctSrvAt = DateTime.now();
    _ctSrvFut = null;
    return s;
  }, onError: (_) {
    _ctSrvFut = null;
    return null;
  });
}

class Thumbnail extends StatelessWidget {
  final Widget? child;
  final double? height;
  final double? width;

  final List<String>? thumbnails;
  final BoxDecoration decoration;

  const Thumbnail(
      {super.key,
      this.child,
      this.thumbnails,
      required this.decoration,
      this.width,
      this.height});

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return FutureBuilder<Server?>(
        // сервер кэшируем: раньше каждая миниатюра при каждой перерисовке читала список серверов
        // из базы — при быстрой прокрутке плиток это и давало подтормаживание
        future: _ctServer(),
        initialData: _ctSrv,
        builder: (context, server) {
          return !server.hasData || server.data == null
              ? Container(
                  decoration: decoration,
                  width: width,
                  height: height,
                  child: child)
              : BlocProvider(
                  create: (context) =>
                      ThumbnailCubit(ThumbnailState(urls: thumbnails ?? [])),
                  child: BlocBuilder<ThumbnailCubit, ThumbnailState>(
                      builder: (context, state) {
                    if (state.selected == null) {
                      return _ErrorWidget(
                          decoration: decoration, width: width, height: height);
                    } else {
                      final cubit = context.read<ThumbnailCubit>();

                      final url = state.selected!.startsWith('/')
                          ? server.data!.url + state.selected!
                          : state.selected!;

                      return CachedNetworkImage(
                        key: ValueKey(url),
                        // ТВ: декодируем сразу в размер карточки, а не 640×480 — меньше работы и памяти
                        memCacheWidth: isTv ? 480 : null,
                        cacheKey: url,
                        httpHeaders: server.data?.headersForUrl(url),
                        errorListener: (value) => cubit.onThumbnailFailed(),
                        imageBuilder: (context, imageProvider) =>
                            AnimatedContainer(
                          height: height,
                          width: width,
                          decoration: decoration.copyWith(
                              image: DecorationImage(
                                  image: imageProvider, fit: BoxFit.cover)),
                          // duration: animationDuration,
                          duration: animationDuration ~/ 2,
                          curve: Curves.easeInOutQuad,
                          child: child,
                        ),
                        imageUrl: url,
                        placeholderFadeInDuration: animationDuration,
                        // ТВ: быстрое появление картинки и без крутилок на каждой карточке —
                        // десятки анимированных индикаторов при прокрутке заметно нагружали приставку
                        fadeInDuration: isTv ? const Duration(milliseconds: 120) : animationDuration,
                        fadeOutDuration: isTv ? const Duration(milliseconds: 80) : animationDuration,
                        errorWidget: (context, url, error) => _ErrorWidget(
                          decoration: decoration,
                          width: width,
                          height: height,
                        ),
                        progressIndicatorBuilder: (context, url, progress) =>
                            Container(
                          height: height,
                          width: width,
                          alignment: Alignment.center,
                          decoration: decoration.copyWith(
                              color: colors.secondaryContainer),
                          child: isTv
                              ? null
                              : const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1,
                                  )),
                        ),
                      );
                    }
                  }),
                );
        });
  }
}

class _ErrorWidget extends StatelessWidget {
  final double? height;
  final double? width;
  final BoxDecoration decoration;

  const _ErrorWidget({this.height, this.width, required this.decoration});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: height,
      width: width,
      alignment: Alignment.center,
      decoration: decoration.copyWith(color: colors.secondaryContainer),
      // duration: animationDuration,
      child: SizedBox(
          height: 20,
          width: 20,
          child: Icon(
            Icons.error_outline,
            color: colors.onSecondaryContainer.withValues(alpha: 0.5),
          )),
    );
  }
}
