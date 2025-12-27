import 'package:flutter/material.dart';

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

  @override
  void dispose() {
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    _yearCtrl.dispose();
    _genreCtrl.dispose();
    super.dispose();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  PreparedVinylAdd _overrideFields(PreparedVinylAdd base) {
    final y = _yearCtrl.text.trim();
    final g = _genreCtrl.text.trim();
    return PreparedVinylAdd(
      artist: base.artist,
      album: base.album,
      coverCandidates: base.coverCandidates,
      selectedCover: base.selectedCover,
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

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(\'Agregar a mano\')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.tr(\'Escribe los datos básicos. Luego podrás revisar la ficha y agregar a tu lista o a deseos.\'),
                  style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 14),
                TextFormField(
                  controller: _artistCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.tr(\'Artista / Banda\'),
                    hintText: context.tr(\'Ej: Pink Floyd\'),
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'El artista es obligatorio.' : null,
                ),
                SizedBox(height: 10),
                TextFormField(
                  controller: _albumCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.tr(\'Álbum\'),
                    hintText: context.tr(\'Ej: The Dark Side of the Moon\'),
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
                          labelText: context.tr(\'Año (opcional)\'),
                          hintText: context.tr(\'Ej: 1973\'),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _genreCtrl,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: context.tr(\'Género (opcional)\'),
                          hintText: context.tr(\'Ej: Rock\'),
                        ),
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