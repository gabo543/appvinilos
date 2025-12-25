import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';

import '../services/backup_service.dart';
import '../services/app_theme_service.dart';
import '../services/view_mode_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Map<int, String> _themeLabels = {
    1: 'Obsidiana',
    2: 'Marfil',
    3: 'Grafito',
    4: 'Bronce',
    5: 'Lila',
    6: 'Verde Sala',
  };

  static String _labelIntensity(int v) {
    if (v <= 2) return 'Suave';
    if (v <= 5) return 'Normal';
    if (v <= 8) return 'Fuerte';
    return 'Máx';
  }

  static const List<String> _borderNames = <String>[
    'Blanco suave',
    'Gris frío',
    'Gris cálido',
    'Verde menta',
    'Verde salvia',
    'Rojo rosado',
    'Durazno',
    'Bronce',
    'Lila',
    'Azul hielo',
  ];

  static String _borderName(int v) {
    final i = v.clamp(1, 10) - 1;
    return _borderNames[i];
  }

  bool _auto = false;
  bool _grid = false;
  int _theme = 1;
  int _textIntensity = 6;
  int _bgLevel = 5;
  int _cardLevel = 5;
  int _borderStyle = 1;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await BackupService.isAutoEnabled();
    final g = await ViewModeService.isGridEnabled();
    final t = await AppThemeService.getTheme();
    final ti = await AppThemeService.getTextIntensity();
    final bg = await AppThemeService.getBgLevel();
    final cl = await AppThemeService.getCardLevel();
    final bs = await AppThemeService.getCardBorderStyle();
    if (!mounted) return;
    setState(() {
      _auto = v;
      _grid = g;
      _theme = t;
      _textIntensity = ti;
      _bgLevel = bg;
      _cardLevel = cl;
      _borderStyle = bs;
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

  Future<void> _exportarDescargas() async {
    try {
      final f = await BackupService.exportToDownloads();
      _snack('Exportado a Descargas ✅\n${f.path}');
    } catch (e) {
      _snack('No se pudo exportar: $e');
    }
  }

  Future<void> _importarDescargas() async {
    try {
      final f = await BackupService.importFromDownloads();
      _snack('Importado desde Descargas ✅\n${f.path}');
    } catch (e) {
      _snack('No se pudo importar: $e');
    }
  }


  Future<void> _compartirBackup() async {
    try {
      final f = await BackupService.getLocalBackupFile(ensureLatest: true);
      await Share.shareXFiles(
        [XFile(f.path)],
        text: 'Respaldo de mi colección (GaBoLP)',
        subject: 'Backup GaBoLP',
      );
    } catch (e) {
      _snack('No se pudo compartir: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeName = _themeLabels[_theme] ?? 'Obsidiana';
    final intensityName = _labelIntensity(_textIntensity);
    final borderName = _borderName(_borderStyle);
    final borderBase = AppThemeService.borderBaseColor(_borderStyle);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final previewBorder = borderBase.withOpacity(isDark ? 0.90 : 0.70);

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
                        leading: const Icon(Icons.download_for_offline_outlined),
                        title: const Text('Exportar a Descargas'),
                        subtitle: const Text('Copia el respaldo a /Download (para no perderlo al desinstalar).'),
                        onTap: _exportarDescargas,
                      ),
                      const Divider(height: 1),

                      ListTile(
                        leading: const Icon(Icons.file_download_outlined),
                        title: const Text('Importar desde Descargas'),
                        subtitle: const Text('Busca "vinyl_backup.json" o el último "GaBoLP_backup_*.json" en Descargas y lo carga (reemplaza tu lista).'),
                        onTap: _importarDescargas,
                      ),
                      const Divider(height: 1),

                      ListTile(
                        leading: const Icon(Icons.share_outlined),
                        title: const Text('Compartir backup'),
                        subtitle: const Text('Enviar a Google Drive / WhatsApp / correo.'),
                        onTap: _compartirBackup,
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

                // 🎨 Temas
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Diseño de la app', style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Text('Estilo:', style: TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(width: 8),
                            Text(themeName, style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 1, icon: Icon(Icons.graphic_eq)),
                            ButtonSegment(value: 2, icon: Icon(Icons.dashboard_customize_outlined)),
                            ButtonSegment(value: 3, icon: Icon(Icons.nightlight_round)),
                            ButtonSegment(value: 4, icon: Icon(Icons.palette_outlined)),
                            ButtonSegment(value: 5, icon: Icon(Icons.bubble_chart_outlined)),
                            ButtonSegment(value: 6, icon: Icon(Icons.flag_outlined)),
                          ],
                          selected: <int>{_theme},
                          showSelectedIcon: false,
                          onSelectionChanged: (s) {
                            final v = s.first;
                            setState(() => _theme = v);
                            AppThemeService.setTheme(v);
                          },
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Cambia el estilo visual sin afectar la lógica ni tus datos.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 🔤 Intensidad del texto
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Texto', style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Text('Intensidad:', style: TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(width: 8),
                            Text(intensityName, style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Slider(
                          value: _textIntensity.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: '$_textIntensity',
                          onChanged: (v) {
                            final iv = v.round();
                            setState(() => _textIntensity = iv);
                            AppThemeService.setTextIntensity(iv);
                          },
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ajusta el contraste del texto en toda la app.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 🧱 Fondo y cuadros
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Niveles visuales', style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Text('Fondo', style: TextStyle(fontWeight: FontWeight.w800)),
                            const Spacer(),
                            Text('Nivel $_bgLevel', style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                        Slider(
                          value: _bgLevel.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: '$_bgLevel',
                          onChanged: (v) {
                            final iv = v.round();
                            setState(() => _bgLevel = iv);
                            AppThemeService.setBgLevel(iv);
                          },
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Text('Cuadros', style: TextStyle(fontWeight: FontWeight.w800)),
                            const Spacer(),
                            Text('Nivel $_cardLevel', style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                        Slider(
                          value: _cardLevel.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: '$_cardLevel',
                          onChanged: (v) {
                            final iv = v.round();
                            setState(() => _cardLevel = iv);
                            AppThemeService.setCardLevel(iv);
                          },
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Ajusta el fondo y el estilo de los cuadros (cards) sin cambiar la lógica.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 🧩 Contorno de cards
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Borde de tarjetas', style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Text('Color:', style: TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(width: 8),
                            Text('$_borderStyle · $borderName', style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Slider(
                          value: _borderStyle.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: '$_borderStyle',
                          onChanged: (v) {
                            final iv = v.round();
                            setState(() => _borderStyle = iv);
                            AppThemeService.setCardBorderStyle(iv);
                          },
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: previewBorder, width: 1.2),
                            color: Theme.of(context).colorScheme.surface,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Vista previa',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Ajusta el color del contorno de los cuadros (cards) en toda la app.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
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
                        await BackupService.saveListNow();
                        _snack('Guardado automático: ACTIVADO ☁️');
                      } else {
                        _snack('Guardado automático: MANUAL ☁️');
                      }
                    },
                    secondary: Icon(_auto ? Icons.cloud_done : Icons.cloud_off),
                    title: const Text('Guardado automático'),
                    subtitle: Text(
                      _auto
                          ? 'Se respalda solo cuando agregas o borras vinilos.'
                          : 'Debes usar “Guardar lista” manualmente.',
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Card(
                  child: SwitchListTile(
                    value: _grid,
                    onChanged: (v) async {
                      setState(() => _grid = v);
                      ViewModeService.setGridEnabled(v);
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
