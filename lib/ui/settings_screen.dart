import 'package:flutter/material.dart';

import '../services/backup_service.dart';
import '../services/view_mode_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _auto = false;
  bool _grid = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await BackupService.isAutoEnabled();
    final g = await ViewModeService.isGridEnabled();
    setState(() {
      _auto = v;
      _grid = g;
      _loading = false;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _guardar() async {
    try {
      await BackupService.saveListNow();
      _snack('Lista guardada ✅');
    } catch (e) {
      _snack('Error al guardar: $e');
    }
  }

  Future<void> _cargar() async {
    try {
      await BackupService.loadList();
      _snack('Lista cargada ✅');
    } catch (e) {
      _snack('No se pudo cargar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.save_alt),
                        title: const Text('Guardar lista'),
                        subtitle: const Text('Crea/actualiza un respaldo local (JSON).'),
                        onTap: _guardar,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.upload_file),
                        title: const Text('Cargar lista'),
                        subtitle: const Text('Reemplaza tu lista por el último respaldo.'),
                        onTap: _cargar,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: SwitchListTile(
                    value: _auto,
                    onChanged: (v) async {
                      setState(() => _auto = v);
                      await BackupService.setAutoEnabled(v);
                      if (v) {
                        // En automático, hacemos un primer guardado inmediato.
                        await BackupService.saveListNow();
                        _snack('Guardado automático: ACTIVADO ☁️');
                      } else {
                        _snack('Guardado automático: MANUAL ☁️');
                      }
                    },
                    secondary: Icon(_auto ? Icons.cloud_done : Icons.cloud_off),
                    title: const Text('Guardado automático'),
                    subtitle: Text(_auto
                        ? 'Se respalda solo cuando agregas o borras vinilos.'
                        : 'Debes usar “Guardar lista” manualmente.'),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: SwitchListTile(
                    value: _grid,
                    onChanged: (v) async {
                      setState(() => _grid = v);
                      await ViewModeService.setGridEnabled(v);
                      _snack(v ? 'Vista: CUADRÍCULA ✅' : 'Vista: LISTA ✅');
                    },
                    secondary: Icon(_grid ? Icons.grid_view : Icons.view_list),
                    title: const Text('Vista de la lista'),
                    subtitle: Text(
                      _grid
                          ? 'Muestra tus vinilos en cuadrícula (tarjetas).'
                          : 'Muestra tus vinilos en lista vertical.',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
