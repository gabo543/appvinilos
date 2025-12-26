import 'dart:io';
import 'package:flutter/material.dart';
import '../services/discography_service.dart';
import '../db/vinyl_db.dart';

class VinylDetailSheet extends StatefulWidget {
  final Map<String, dynamic> vinyl;
  const VinylDetailSheet({super.key, required this.vinyl});

  @override
  State<VinylDetailSheet> createState() => _VinylDetailSheetState();
}

class _VinylDetailSheetState extends State<VinylDetailSheet> {
  bool loadingTracks = false;
  List<TrackItem> tracks = [];
  String? msg;

  Future<void> _editMeta() async {
    final id = int.tryParse((widget.vinyl['id'] ?? '').toString()) ?? 0;
    if (id <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No puedo editar: falta ID.')));
      return;
    }

    final year0 = (widget.vinyl['year'] as String?)?.trim() ?? '';
    final cond0 = (widget.vinyl['condition'] as String?)?.trim() ?? '';
    final fmt0 = (widget.vinyl['format'] as String?)?.trim() ?? '';

    final yearCtrl = TextEditingController(text: year0);
    String condition = cond0;
    String format = fmt0;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            return AlertDialog(
              title: const Text('Editar vinilo'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: yearCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Año (opcional)'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: condition.isEmpty ? null : condition,
                      decoration: const InputDecoration(labelText: 'Condición'),
                      items: const [
                        DropdownMenuItem(value: 'Mint (M)', child: Text('Mint (M)')),
                        DropdownMenuItem(value: 'Near Mint (NM)', child: Text('Near Mint (NM)')),
                        DropdownMenuItem(value: 'Very Good Plus (VG+)', child: Text('Very Good Plus (VG+)')),
                        DropdownMenuItem(value: 'Very Good (VG)', child: Text('Very Good (VG)')),
                        DropdownMenuItem(value: 'Good (G)', child: Text('Good (G)')),
                        DropdownMenuItem(value: 'Poor (P)', child: Text('Poor (P)')),
                      ],
                      onChanged: (v) => setD(() => condition = v ?? ''),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: format.isEmpty ? null : format,
                      decoration: const InputDecoration(labelText: 'Formato'),
                      items: const [
                        DropdownMenuItem(value: 'LP', child: Text('LP')),
                        DropdownMenuItem(value: 'EP', child: Text('EP')),
                        DropdownMenuItem(value: 'Single', child: Text('Single')),
                        DropdownMenuItem(value: 'Boxset', child: Text('Boxset')),
                      ],
                      onChanged: (v) => setD(() => format = v ?? ''),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
              ],
            );
          },
        );
      },
    );

    if (saved != true) return;

    try {
      final y = yearCtrl.text.trim();
      await VinylDb.instance.updateVinylMeta(
        id: id,
        year: y,
        condition: condition,
        format: format,
      );

      // Actualiza el mapa local para reflejar cambios sin recargar.
      widget.vinyl['year'] = y;
      widget.vinyl['condition'] = condition;
      widget.vinyl['format'] = format;
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Actualizado ✅')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    final mbid = (widget.vinyl['mbid'] as String?)?.trim() ?? '';
    if (mbid.isEmpty) {
      setState(() => msg = 'No hay ID (MBID) guardado para este LP, no puedo buscar canciones.');
      return;
    }

    setState(() {
      loadingTracks = true;
      msg = null;
      tracks = [];
    });

    final list = await DiscographyService.getTracksFromReleaseGroup(mbid);

    if (!mounted) return;

    setState(() {
      tracks = list;
      loadingTracks = false;
      if (list.isEmpty) msg = 'No encontré canciones para este disco.';
    });
  }

  Widget _cover() {
    final cp = (widget.vinyl['coverPath'] as String?)?.trim() ?? '';

if (cp.startsWith('http://') || cp.startsWith('https://')) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: Image.network(
      cp,
      width: 120,
      height: 120,
      fit: BoxFit.cover,
      cacheWidth: 360,
      cacheHeight: 360,
      errorBuilder: (_, __, ___) => const SizedBox(
        width: 120,
        height: 120,
        child: Center(child: Icon(Icons.album, size: 52)),
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const SizedBox(
          width: 120,
          height: 120,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
    ),
  );
}
    if (cp.isNotEmpty) {
      final f = File(cp);
      if (f.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(f, width: 120, height: 120, fit: BoxFit.cover),
        );
      }
    }
    return const SizedBox(
      width: 120,
      height: 120,
      child: Center(child: Icon(Icons.album, size: 52)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final fg = dark ? Colors.white : Colors.black;
    final sub = dark ? const Color(0xFFBDBDBD) : Colors.black54;
    final artista = (widget.vinyl['artista'] as String?) ?? '';
    final album = (widget.vinyl['album'] as String?) ?? '';
    final aNo = int.tryParse((widget.vinyl['artistNo'] ?? '').toString()) ?? 0;
    final alNo = int.tryParse((widget.vinyl['albumNo'] ?? '').toString()) ?? 0;
    final code = (aNo > 0 && alNo > 0)
        ? '$aNo.$alNo'
        : ((widget.vinyl['numero'] ?? '').toString().trim().isEmpty
            ? '—'
            : (widget.vinyl['numero'] ?? '').toString());
    final year = (widget.vinyl['year'] as String?)?.trim() ?? '';
    final genre = (widget.vinyl['genre'] as String?)?.trim() ?? '';
    final country = (widget.vinyl['country'] as String?)?.trim() ?? '';
    final condition = (widget.vinyl['condition'] as String?)?.trim() ?? '';
    final format = (widget.vinyl['format'] as String?)?.trim() ?? '';
    final wishlistStatus = (widget.vinyl['status'] as String?)?.trim() ?? '';
    final bio = (widget.vinyl['artistBio'] as String?)?.trim() ?? '';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _cover(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$artista\n$album',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: fg),
                  ),
                ),
                IconButton(
                  tooltip: 'Editar',
                  onPressed: _editMeta,
                  icon: Icon(Icons.edit, color: fg),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: fg),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _pill(context, 'Orden', code),
                _pill(context, 'Año', year.isEmpty ? '—' : year),
                _pill(context, 'Género', genre.isEmpty ? '—' : genre),
                _pill(context, 'País', country.isEmpty ? '—' : country),
                if (condition.isNotEmpty) _pill(context, 'Condición', condition),
                if (format.isNotEmpty) _pill(context, 'Formato', format),
                if (wishlistStatus.isNotEmpty) _pill(context, 'Wishlist', wishlistStatus),
              ],
            ),

            const SizedBox(height: 10),

            if (bio.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: dark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: dark ? Colors.white12 : Colors.black12),
                ),
                child: Text(bio, style: TextStyle(color: fg)),
              ),

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('Canciones', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: fg)),
                ),
                IconButton(onPressed: _loadTracks, icon: Icon(Icons.refresh, color: fg)),
              ],
            ),

            if (loadingTracks) const LinearProgressIndicator(),
            if (!loadingTracks && msg != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(msg!, style: TextStyle(color: sub)),
              ),

            if (!loadingTracks && tracks.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  itemCount: tracks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final t = tracks[i];
                    return ListTile(
                      dense: true,
                      title: Text('${t.number}. ${t.title}', style: TextStyle(color: fg)),
                      trailing: Text(t.length ?? '', style: TextStyle(color: sub)),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, String k, String v) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final fg = dark ? Colors.white : Colors.black;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: dark ? Colors.white12 : Colors.black12),
      ),
      child: Text('$k: $v', style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
    );
  }
}
