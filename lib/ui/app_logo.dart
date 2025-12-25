import 'package:flutter/material.dart';

/// Logo pequeño de la app (para AppBar y headers).
///
/// Usa el mismo asset que el ícono del teléfono para mantener coherencia.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 26});

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

/// Leading para AppBar: logo clickeable.
Widget appLogoLeading({
  required VoidCallback onTap,
  String tooltip = 'Inicio',
}) {
  return IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    icon: const AppLogo(size: 26),
  );
}
