import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';

// Tamaños de branding.
// - Home mantiene su header grande.
// - Resto de pantallas: logo del AppBar al doble (pedido).
// Para que el título no se corte, usamos un título con FittedBox(scaleDown).
const double kAppBarLogoSize = 68; // logo grande en AppBar
const double kHomeHeaderLogoSize = 144; // mantener look grande del Home
const double kAppBarGapLogoBack = 12;
const double kAppBarToolbarHeight = kAppBarLogoSize + 26; // alto extra para el logo grande
const double kBackIconSize = 30;

/// Logo de la app (mismo asset que el ícono del teléfono) para AppBar y headers.
class AppLogo extends StatelessWidget {
  final double size;
  AppLogo({super.key, this.size = kAppBarLogoSize});

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
          tooltip: context.tr(\'Volver\'),
          icon: Icon(Icons.arrow_back, size: kBackIconSize),
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: 48, minHeight: 48),
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

/// Título para AppBar que **no se corta**.
/// - Usa FittedBox(scaleDown) para que el texto se vea completo incluso con logo grande.
Widget appBarTitleTextScaled(
  String title, {
  EdgeInsets padding = const EdgeInsets.only(left: 10),
  TextStyle? style,
}) {
  return Padding(
    padding: padding,
    child: Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        alignment: Alignment.centerLeft,
        fit: BoxFit.scaleDown,
        child: Text(title, maxLines: 1, style: style),
      ),
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

/// (Legacy) Título de AppBar con logo + texto.
Widget appBarTitleTextWithLogo(
  String title, {
  double logoSize = kAppBarLogoSize,
}) {
  return appBarTitleWithLogo(
    logoSize: logoSize,
    child: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.visible,
    ),
  );
}