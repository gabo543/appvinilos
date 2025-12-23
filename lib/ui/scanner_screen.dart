import 'package:flutter/material.dart';

/// Pantalla placeholder (scanner aún no implementado).
/// Si más adelante agregas un lector de códigos de barra/QR, esta es la pantalla
/// donde se integrará.
///
/// Nota: se mantiene sin dependencias externas para evitar errores de build.
class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear')),
      body: const Center(
        child: Text('Scanner: próximamente'),
      ),
    );
  }
}
