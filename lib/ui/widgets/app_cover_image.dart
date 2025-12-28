import 'dart:io';

import 'package:flutter/material.dart';

/// Carátula unificada para toda la app.
///
/// - Soporta URL (http/https) y archivos locales.
/// - Muestra placeholder tipo "skeleton" en vez de spinner (más pro).
/// - Maneja errores sin romper layouts.
class AppCoverImage extends StatelessWidget {
  final String? pathOrUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final int? cacheWidth;
  final int? cacheHeight;

  const AppCoverImage({
    super.key,
    required this.pathOrUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.cacheWidth,
    this.cacheHeight,
  });

  Widget _placeholder(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      color: cs.surfaceVariant.withOpacity(0.55),
      child: Icon(Icons.album_outlined, color: cs.onSurfaceVariant.withOpacity(0.65)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final raw = (pathOrUrl ?? '').trim();
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cw = cacheWidth ?? ((width ?? 0) * dpr).round();
    final ch = cacheHeight ?? ((height ?? 0) * dpr).round();

    Widget child;
    if (raw.isEmpty) {
      child = _placeholder(context);
    } else if (raw.startsWith('http://') || raw.startsWith('https://')) {
      child = Image.network(
        raw,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cw > 0 ? cw : null,
        cacheHeight: ch > 0 ? ch : null,
        loadingBuilder: (context, w, progress) {
          if (progress == null) return w;
          return _placeholder(context);
        },
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    } else {
      child = Image.file(
        File(raw),
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cw > 0 ? cw : null,
        cacheHeight: ch > 0 ? ch : null,
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: child,
    );
  }
}
