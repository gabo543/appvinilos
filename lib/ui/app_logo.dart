import 'package:flutter/material.dart';

/// Logo de la app (mismo asset que el ícono del teléfono) para AppBar y headers.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: Image.asset(
        'assets/icon/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

/// Ancho recomendado para `AppBar.leadingWidth` cuando usas [appBarLeadingLogoBack].
double appBarLeadingWidthForLogoBack({
  double logoSize = 36,
  double gap = 10,
}) {
  // padding izquierda (8) + logo + gap + botón (40) + colchón (6)
  return 8 + logoSize + gap + 40 + 6;
}

/// Leading del AppBar: logo primero (esquina izquierda), luego flecha volver.
/// - Si [onBack] es null: usa `Navigator.maybePop()` cuando se pueda.
Widget appBarLeadingLogoBack(
  BuildContext context, {
  VoidCallback? onBack,
  double logoSize = 36,
  double gap = 10,
}) {
  return Padding(
    padding: const EdgeInsets.only(left: 8),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: logoSize),
        SizedBox(width: gap),
        IconButton(
          tooltip: 'Volver',
          icon: const Icon(Icons.arrow_back),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: () async {
            if (onBack != null) {
              onBack();
              return;
            }
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              await nav.maybePop();
            }
          },
        ),
      ],
    ),
  );
}

/// (Legacy) Título de AppBar con logo a la izquierda + contenido (texto o widget).
Widget appBarTitleWithLogo({
  required Widget child,
  double logoSize = 36,
}) {
  return Row(
    children: [
      Padding(
        padding: const EdgeInsets.only(right: 10),
        child: AppLogo(size: logoSize),
      ),
      Expanded(child: child),
    ],
  );
}

/// (Legacy) Título de AppBar con logo + texto (con ellipsis).
Widget appBarTitleTextWithLogo(
  String title, {
  double logoSize = 36,
}) {
  return appBarTitleWithLogo(
    logoSize: logoSize,
    child: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}
