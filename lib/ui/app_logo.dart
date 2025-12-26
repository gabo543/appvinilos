import 'package:flutter/material.dart';

// Tamaños de branding (ajustables en un solo lugar)
const double kLogoScale = 4.0;
const double kAppBarLogoSize = 34 * kLogoScale; // antes 34
// Logo en el card principal del Home. Un poco más grande para que se luzca,
// sin cambiar el layout del card.
const double kHomeHeaderLogoSize = 30 * kLogoScale; // antes 26
const double kAppBarGapLogoBack = 12;
const double kAppBarToolbarHeight = kAppBarLogoSize + 20; // colchón
const double kBackIconSize = 30;


/// Logo de la app (mismo asset que el ícono del teléfono) para AppBar y headers.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = kAppBarLogoSize});

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
  double logoSize = kAppBarLogoSize,
  double gap = kAppBarGapLogoBack,
}) {
  // padding izquierda (8) + logo + gap + botón (40) + colchón (6)
  return 8 + logoSize + gap + 40 + 6;
}

/// Leading del AppBar: logo primero (esquina izquierda), luego flecha volver.
/// - Si [onBack] es null: usa `Navigator.maybePop()` cuando se pueda.
Widget appBarLeadingLogoBack(
  BuildContext context, {
  VoidCallback? onBack,
  double logoSize = kAppBarLogoSize,
  double gap = kAppBarGapLogoBack,
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
          icon: const Icon(Icons.arrow_back, size: kBackIconSize),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
  double logoSize = kAppBarLogoSize,
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
  double logoSize = kAppBarLogoSize,
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
