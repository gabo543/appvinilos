import 'package:flutter/material.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../services/vinyl_add_service.dart';
import 'add_vinyl_preview_screen.dart';
import '../l10n/app_strings.dart';

/// Ingreso manual de vinilos (sin escáner).
///
/// Flujo:
/// 1) Formulario (artista + álbum obligatorios; año/género opcionales)
/// 2) Abre la ficha [AddVinylPreviewScreen] para revisar y agregar a Lista/Deseos.
class ManualVinylEntryScreen extends StatefulWidget {
  ManualVinylEntryScreen({super.key});

  @override
  State<ManualVinylEntryScreen> createState() => _ManualVinylEntryScreenState();
}

class _ManualVinylEntryScreenState extends State<ManualVinylEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _artistCtrl = TextEditingController();
  final _albumCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _genreCtrl = TextEditingController();

  bool _loading = false;
  String? _localCoverPath;

  @override
  void dispose() {
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    _yearCtrl.dispose();
    _genreCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCoverFromGallery() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
      if (x == null) return;
      setState(() => _localCoverPath = x.path);
    } catch (_) {
      _snack('No pude abrir la galería.');
    }
  }

  Future<void> _pickCoverFromCamera() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 92);
      if (x == null) return;
      setState(() => _localCoverPath = x.path);
    } catch (_) {
      _snack('No pude abrir la cámara.');
    }
  }

  Future<void> _pickCoverFromFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        withData: false,
      );
      final path = res?.files.single.path;
      if (path == null || path.trim().isEmpty) return;
      setState(() => _localCoverPath = path);
    } catch (_) {
      _snack('No pude seleccionar el archivo.');
    }
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  bool get _hasLocalCover {
    final p = (_localCoverPath ?? '').trim();
    return p.isNotEmpty && File(p).existsSync();
  }

  void _clearCover() {
    setState(() => _localCoverPath = null);
  }

  PreparedVinylAdd _overrideFields(PreparedVinylAdd base) {
    final y = _yearCtrl.text.trim();
    final g = _genreCtrl.text.trim();
    return PreparedVinylAdd(
      artist: base.artist,
      album: base.album,
      coverCandidates: base.coverCandidates,
      selectedCover: base.selectedCover,
      localCoverPath: _localCoverPath,
      artistId: base.artistId,
      year: y.isEmpty ? base.year : y,
      genre: g.isEmpty ? base.genre : g,
      country: base.country,
      bioShort: base.bioShort,
      releaseGroupId: base.releaseGroupId,
      releaseId: base.releaseId,
      coverFallback250: base.coverFallback250,
      coverFallback500: base.coverFallback500,
    );
  }

  Future<void> _continue() async {
    FocusScope.of(context).unfocus();
    if (_loading) return;

    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);

    final artist = _artistCtrl.text.trim();
    final album = _albumCtrl.text.trim();
    final y = _yearCtrl.text.trim();
    final g = _genreCtrl.text.trim();

    PreparedVinylAdd prepared;
    try {
      // Ruta ideal: enriquecemos metadata (carátula, año/género si existen, bio, etc.)
      final base = await VinylAddService.prepare(artist: artist, album: album);
      prepared = _overrideFields(base);
    } catch (_) {
      // Ruta offline/robusta: dejamos lo mínimo y permitimos agregar igual.
      prepared = PreparedVinylAdd(
        artist: artist,
        album: album,
        coverCandidates: const [],
        selectedCover: null,
        localCoverPath: _localCoverPath,
        year: y.isEmpty ? null : y,
        genre: g.isEmpty ? null : g,
      );
      _snack('No pude cargar metadata. Puedes agregar igual.');
    }

    if (!mounted) return;
    setState(() => _loading = false);

    final added = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => AddVinylPreviewScreen(prepared: prepared)),
        ) ??
        false;

    if (!mounted) return;
    if (added) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final local = (_localCoverPath ?? '').trim();
    final hasLocal = local.isNotEmpty && File(local).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Agregar a mano')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.tr('Escribe los datos básicos. Luego podrás revisar la ficha y agregar a tu lista o a deseos.'),
                  style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 14),
                TextFormField(
                  controller: _artistCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.tr('Artista / Banda'),
                    hintText: context.tr('Ej: Pink Floyd'),
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'El artista es obligatorio.' : null,
                ),
                SizedBox(height: 10),
                TextFormField(
                  controller: _albumCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.tr('Álbum'),
                    hintText: context.tr('Ej: The Dark Side of the Moon'),
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'El álbum es obligatorio.' : null,
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _yearCtrl,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: context.tr('Año (opcional)'),
                          hintText: context.tr('Ej: 1973'),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _genreCtrl,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: context.tr('Género (opcional)'),
                          hintText: context.tr('Ej: Rock'),
                        ),
                      ),
                    ),
                  ],
                ),
                // Carátula manual (foto/archivo)
                Text(
                  context.tr('Carátula (opcional)'),
                  style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 96,
                        height: 96,
                        color: t.colorScheme.surfaceContainerHighest,
                        child: _hasLocalCover
                            ? Image.file(File(_localCoverPath!), fit: BoxFit.cover)
                            : Icon(Icons.album, size: 44),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _loading ? null : _pickCoverFromGallery,
                                icon: Icon(Icons.photo_library_outlined),
                                label: Text(context.tr('Foto')),
                              ),
                              OutlinedButton.icon(
                                onPressed: _loading ? null : _pickCoverFromCamera,
                                icon: Icon(Icons.photo_camera_outlined),
                                label: Text(context.tr('Cámara')),
                              ),
                              OutlinedButton.icon(
                                onPressed: _loading ? null : _pickCoverFromFile,
                                icon: Icon(Icons.folder_open_outlined),
                                label: Text(context.tr('Archivo')),
                              ),
                            ],
                          ),
                          if (_hasLocalCover) ...[
                            SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _loading ? null : _clearCover,
                                icon: Icon(Icons.close),
                                label: Text(context.tr('Quitar carátula')),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _loading ? null : _continue,
                  icon: _loading
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.arrow_forward),
                  label: Text(_loading ? 'Preparando…' : 'Continuar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}