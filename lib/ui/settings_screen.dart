import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';

import '../services/backup_service.dart';
import '../services/app_theme_service.dart';
import '../services/cover_cache_service.dart';
import '../services/export_service.dart';
import '../services/audio_recognition_service.dart';
import '../services/locale_service.dart';
import '../db/vinyl_db.dart';
import 'app_logo.dart';
import '../l10n/app_strings.dart';

class SettingsScreen extends StatefulWidget {
  SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Map<int, String> _themeLabels = {
    1: 'Obsidiana',
    2: 'Marfil',
    3: 'Grafito',
    4: 'Vinilo Retro',
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
  int _theme = 1;
  int _textIntensity = 6;
  int _bgLevel = 5;
  int _cardLevel = 5;
  int _borderStyle = 1;
  bool _loading = true;
  bool _downloadingCovers = false;
  int _coversDone = 0;
  int _coversTotal = 0;
  bool _audioConfigured = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await BackupService.isAutoEnabled();
    final t = await AppThemeService.getTheme();
    final ti = await AppThemeService.getTextIntensity();
    final bg = await AppThemeService.getBgLevel();
    final cl = await AppThemeService.getCardLevel();
    final bs = await AppThemeService.getCardBorderStyle();
    final token = await AudioRecognitionService.getToken();
    if (!mounted) return;
    setState(() {
      _auto = v;
      _theme = t;
      _textIntensity = ti;
      _bgLevel = bg;
      _cardLevel = cl;
      _borderStyle = bs;
      _audioConfigured = token != null;
      _loading = false;
    });
  }

  Future<void> _configAudio() async {
    final current = await AudioRecognitionService.getToken();
    final ctrl = TextEditingController(text: current ?? '');
    if (!mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(context.tr('Reconocimiento (Escuchar)')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Para reconocer canciones necesitas un token (AudD).\n\n'
                'Pega tu token aquí. Puedes dejarlo vacío para desactivar.',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: context.tr('Token AudD'),
                  hintText: context.tr('api_token…'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('Cancelar'))),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.tr('Guardar')),
            ),
          ],
        );
      },
    );

    if (saved != true) return;
    await AudioRecognitionService.setToken(ctrl.text);
    final t = await AudioRecognitionService.getToken();
    if (!mounted) return;
    setState(() => _audioConfigured = t != null);
    _snack(t == null ? 'Reconocimiento desactivado' : 'Token guardado ✅');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr(msg))),
    );
  }

  Future<void> _descargarCaratulas() async {
    if (_downloadingCovers) return;
    setState(() {
      _downloadingCovers = true;
      _coversDone = 0;
      _coversTotal = 0;
    });

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final t = _coversTotal <= 0 ? 'Preparando…' : '$_coversDone / $_coversTotal';
          final p = (_coversTotal <= 0) ? null : (_coversDone / _coversTotal).clamp(0.0, 1.0);
          return AlertDialog(
            title: Text(context.tr('Descargando carátulas')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (p == null) LinearProgressIndicator() else LinearProgressIndicator(value: p),
                SizedBox(height: 12),
                Text(t),
                SizedBox(height: 6),
                Text(context.tr('Esto deja tus carátulas guardadas para ver offline.'), style: TextStyle(fontSize: 14)),
              ],
            ),
          );
        },
      ),
    );

    try {
      final res = await CoverCacheService.downloadMissingCovers(
        onProgress: (d, tot) {
          if (!mounted) return;
          setState(() {
            _coversDone = d;
            _coversTotal = tot;
          });
        },
      );
      if (mounted) Navigator.of(context).pop();
      _snack(res.summary());
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _snack('No se pudo descargar carátulas: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _downloadingCovers = false;
      });
    }
  }

  Future<void> _duplicados() async {
    try {
      final groups = await VinylDb.instance.findDuplicateGroups(includeYear: true);
      if (!mounted) return;

      if (groups.isEmpty) {
        _snack('No hay duplicados ✅');
        return;
      }

      final doMerge = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(context.tr('Duplicados encontrados')),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: groups.length,
                itemBuilder: (_, i) {
                  final g = groups[i];
                  final first = g.first;
                  final artista = (first['artista'] ?? '').toString();
                  final album = (first['album'] ?? '').toString();
                  final year = (first['year'] ?? '').toString();
                  return ListTile(
                    dense: true,
                    title: Text('$artista — $album'),
                    subtitle: Text(year.isEmpty ? '${g.length} copias' : '$year · ${g.length} copias'),
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('Cerrar'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('Fusionar duplicados'))),
            ],
          );
        },
      );

      if (doMerge != true) return;
      final deleted = await VinylDb.instance.mergeDuplicates(includeYear: true);
      _snack('Listo ✅ Eliminados: $deleted');
    } catch (e) {
      _snack('Error en duplicados: $e');
    }
  }

  Future<void> _guardar() async {
    try {
      await BackupService.saveListNow();
      _snack('Backup guardado ✅');
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
      final saved = await BackupService.exportToDownloads();
      if (saved == null || saved.isEmpty) {
        _snack('Exportación cancelada.');
        return;
      }
      _snack('Exportado ✅\n$saved');
    } catch (e) {
      _snack('No se pudo exportar: $e');
    }
  }

  Future<void> _exportarCsvInventario() async {
    try {
      final saved = await ExportService.exportCsvInventory();
      if (saved == null || saved.isEmpty) {
        _snack('Exportación cancelada.');
        return;
      }
      _snack('CSV exportado ✅\n$saved');
    } catch (e) {
      _snack('No se pudo exportar CSV: $e');
    }
  }

  Future<void> _exportarPdfInventario() async {
    try {
      final saved = await ExportService.exportPdfInventory();
      if (saved == null || saved.isEmpty) {
        _snack('Exportación cancelada.');
        return;
      }
      _snack('PDF exportado ✅\n$saved');
    } catch (e) {
      _snack('No se pudo exportar PDF: $e');
    }
  }

  Future<void> _importarDescargas() async {
    try {
      final f = await BackupService.pickBackupFile();
      if (f == null) {
        _snack('Importación cancelada.');
        return;
      }
      final preview = await BackupService.peekBackupFile(f);

      if (!mounted) return;

      final mode = await showDialog<BackupImportMode>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.tr('Importar backup')),
          content: Text(
            '${preview.pretty()}\n\nArchivo:\n${f.path}\n\n'
            'Elige cómo importarlo:',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.tr('Cancelar')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, BackupImportMode.onlyMissing),
              child: Text(context.tr('Solo faltantes')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, BackupImportMode.merge),
              child: Text(context.tr('Fusionar (recomendado)')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, BackupImportMode.replace),
              child: Text(context.tr('Reemplazar todo')),
            ),
          ],
        ),
      );

      if (mode == null) return;

      final res = await BackupService.importFromFile(
        f,
        mode: mode,
        copyToLocal: true,
      );

      _snack('Importado ✅\n${res.summary()}');
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
    final t = Theme.of(context);
    final cs = t.colorScheme;

    final themeName = _themeLabels[_theme] ?? 'Obsidiana';
    final intensityName = _labelIntensity(_textIntensity);
    final borderName = _borderName(_borderStyle);
    final borderBase = AppThemeService.borderBaseColor(_borderStyle);
    final isDark = t.brightness == Brightness.dark;
    final previewBorder = borderBase.withOpacity(isDark ? 0.90 : 0.70);

    Widget sectionTitle(IconData icon, String title, {String? subtitle}) {
    final titleT = context.tr(title);
    final subtitleT = (subtitle == null) ? null : context.tr(subtitle!);
      return Padding(
        padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Icon(icon, size: 18, color: cs.onSurface.withOpacity(0.82)),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.2)),
                  if (subtitle != null) ...[
                    SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: t.textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.70), fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    const div = Divider(height: 1);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kAppBarToolbarHeight,
        leadingWidth: appBarLeadingWidthForLogoBack(logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        leading: appBarLeadingLogoBack(context, logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        // Más aire entre el leading (logo + back) y el título.
        title: appBarTitleTextScaled(context.tr('Ajustes'), padding: const EdgeInsets.only(left: 8)),
        titleSpacing: 12,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                sectionTitle(Icons.tune, 'General', subtitle: 'Opciones básicas y respaldo automático.'),
                Card(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ValueListenableBuilder<Locale>(
                        valueListenable: LocaleService.localeNotifier,
                        builder: (_, locale, __) {
                          final isEn = locale.languageCode == 'en';
                          return SwitchListTile(
                            value: isEn,
                            onChanged: (v) async {
                              await LocaleService.setCode(v ? 'en' : 'es');
                              if (!mounted) return;
                              setState(() {});
                            },
                            title: Text(context.tr('Idioma')),
                            subtitle: Text(context.tr('Cambiar idioma entre Español e Inglés.')),
                            secondary: const Icon(Icons.language),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
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
                        title: Text(context.tr('Guardado automático')),
                        subtitle: Text(
                          _auto
                              ? context.tr('Respalda solo cuando agregas o borras vinilos.')
                              : context.tr('Debes usar “Guardar backup” manualmente.'),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 14),

                sectionTitle(Icons.backup_outlined, 'Backup y exportación', subtitle: 'Guardar, importar y compartir tu colección.'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.save_alt),
                        title: Text(context.tr('Guardar backup')),
                        subtitle: Text(context.tr('Crea un respaldo completo (colección + deseos + ajustes).')),
                        onTap: _guardar,
                      ),
                      div,
                      ListTile(
                        leading: Icon(Icons.download_for_offline_outlined),
                        title: Text(context.tr('Exportar backup (Descargas)')),
                        subtitle: Text(context.tr('Guárdalo en Descargas para copiarlo o enviarlo.')),
                        onTap: _exportarDescargas,
                      ),
                      div,
                      ListTile(
                        leading: Icon(Icons.file_download_outlined),
                        title: Text(context.tr('Importar backup')),
                        subtitle: Text(context.tr('Selecciona un archivo para fusionar o reemplazar datos.')),
                        onTap: _importarDescargas,
                      ),
                      div,
                      ListTile(
                        leading: Icon(Icons.share_outlined),
                        title: Text(context.tr('Compartir backup')),
                        subtitle: Text(context.tr('Enviar a Drive / WhatsApp / correo.')),
                        onTap: _compartirBackup,
                      ),
                      div,
                      ListTile(
                        leading: Icon(Icons.table_chart_outlined),
                        title: Text(context.tr('Exportar inventario (CSV)')),
                        subtitle: Text(context.tr('Planilla para Excel / Google Sheets.')),
                        onTap: _exportarCsvInventario,
                      ),
                      div,
                      ListTile(
                        leading: Icon(Icons.picture_as_pdf_outlined),
                        title: Text(context.tr('Exportar inventario (PDF)')),
                        subtitle: Text(context.tr('Inventario listo para imprimir.')),
                        onTap: _exportarPdfInventario,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 14),

                sectionTitle(Icons.hearing_outlined, 'Escáner y audio', subtitle: 'Reconocimiento por micrófono y carátulas offline.'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.hearing_outlined),
                        title: Text(context.tr('Reconocimiento (Escuchar)')),
                        subtitle: Text(
                          _audioConfigured
                              ? 'Token configurado ✅'
                              : 'Configura token AudD para reconocer canciones.',
                        ),
                        onTap: _configAudio,
                      ),
                      div,
                      ListTile(
                        leading: Icon(Icons.cloud_download_outlined),
                        title: Text(context.tr('Descargar carátulas faltantes')),
                        subtitle: Text(context.tr('Guarda portadas para ver offline.')),
                        onTap: _downloadingCovers ? null : _descargarCaratulas,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 14),

                sectionTitle(Icons.library_music, 'Colección', subtitle: 'Mantenimiento y limpieza de tu lista.'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.content_copy_outlined),
                        title: Text(context.tr('Detectar / fusionar duplicados')),
                        subtitle: Text(context.tr('Encuentra repetidos por artista+álbum y los fusiona.')),
                        onTap: _duplicados,
                      ),
                      div,
                      ExpansionTile(
                        leading: Icon(Icons.warning_amber_outlined),
                        title: Text(context.tr('Avanzado')),
                        subtitle: Text(context.tr('Opciones que pueden reemplazar datos.')),
                        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        children: [
                          ListTile(
                            leading: Icon(Icons.upload_file),
                            title: Text(context.tr('Cargar backup local')),
                            subtitle: Text(context.tr('Reemplaza TODO por el último backup local.')),
                            onTap: _cargar,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 14),

                sectionTitle(Icons.palette_outlined, 'Apariencia', subtitle: 'Tema, contraste y bordes.'),
                Card(
                  child: ExpansionTile(
                    leading: Icon(Icons.palette_outlined),
                    title: Text(context.tr('Personalizar diseño')),
                    subtitle: Text('Tema: $themeName · Texto: $intensityName'),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    children: [
                      SizedBox(height: 10),
                      Text(context.tr('Tema'), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                      SizedBox(height: 8),
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
                      SizedBox(height: 6),
                      Text(context.tr('Cambia el estilo visual de la app.'), style: t.textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.70), fontWeight: FontWeight.w700)),
                      SizedBox(height: 16),

                      Text(context.tr('Texto'), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Text(context.tr('Intensidad:'), style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                          SizedBox(width: 8),
                          Text(intensityName, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900)),
                        ],
                      ),
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
                      Text(context.tr('Ajusta el contraste del texto.'), style: t.textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.70), fontWeight: FontWeight.w700)),
                      SizedBox(height: 14),

                      Text(context.tr('Niveles visuales'), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Text(context.tr('Fondo'), style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                          Spacer(),
                          Text('Nivel $_bgLevel', style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900)),
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
                      Row(
                        children: [
                          Text(context.tr('Cuadros'), style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                          Spacer(),
                          Text('Nivel $_cardLevel', style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900)),
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
                      Text(context.tr('Ajusta fondo y estilo de cards.'), style: t.textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.70), fontWeight: FontWeight.w700)),
                      SizedBox(height: 14),

                      Text(context.tr('Borde de tarjetas'), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Text(context.tr('Color:'), style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                          SizedBox(width: 8),
                          Text('$_borderStyle · $borderName', style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900)),
                        ],
                      ),
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
                      Container(
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: previewBorder, width: 1.2),
                          color: cs.surface,
                        ),
                        alignment: Alignment.center,
                        child: Text(context.tr('Vista previa'),
                          style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(context.tr('Cambia el contorno de los cuadros.'), style: t.textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.70), fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                SizedBox(height: 18),
              ],
            ),
    );
  }
}
