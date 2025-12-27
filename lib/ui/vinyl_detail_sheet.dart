import 'dart:io';
import 'package:flutter/material.dart';
import '../services/discography_service.dart';
import '../services/price_range_service.dart';
import '../db/vinyl_db.dart';
import '../l10n/app_strings.dart';

class VinylDetailSheet extends StatefulWidget {
  final Map<String, dynamic> vinyl;
  VinylDetailSheet({super.key, required this.vinyl});

  @override
  State<VinylDetailSheet> createState() => _VinylDetailSheetState();
}

class _VinylDetailSheetState extends State<VinylDetailSheet> {
  bool loadingTracks = false;
  List<TrackItem> tracks = [];
  String? msg;

  bool loadingPrice = false;
  PriceRange? priceRange;

  Future<void> _editMeta() async {
    final id = int.tryParse((widget.vinyl['id'] ?? '').toString()) ?? 0;
    if (id <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('No puedo editar: falta ID.'))));
      return;
    }

    final artista0 = (widget.vinyl['artista'] as String?)?.trim() ?? '';
    final album0 = (widget.vinyl['album'] as String?)?.trim() ?? '';
    final year0 = (widget.vinyl['year'] as String?)?.trim() ?? '';
    final cond0 = (widget.vinyl['condition'] as String?)?.trim() ?? 'VG+';
    final fmt0 = (widget.vinyl['format'] as String?)?.trim() ?? 'LP';

    final artistaCtrl = TextEditingController(text: artista0);
    final albumCtrl = TextEditingController(text: album0);
    final yearCtrl = TextEditingController(text: year0);
    String condition = cond0.isEmpty ? 'VG+' : cond0;
    String format = fmt0.isEmpty ? 'LP' : fmt0;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            return AlertDialog(
              title: Text(context.tr('Editar vinilo')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: artistaCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: context.tr('Artista')),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: albumCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: context.tr('Álbum')),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: yearCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: context.tr('Año (opcional)')),
                    ),
                    SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: condition,
                      decoration: InputDecoration(labelText: context.tr('Condición')),
                      items: const [
                        DropdownMenuItem(value: 'M', child: Text(context.tr('M (Mint)'))),
                        DropdownMenuItem(value: 'NM', child: Text(context.tr('NM (Near Mint)'))),
                        DropdownMenuItem(value: 'VG+', child: Text(context.tr('VG+'))),
                        DropdownMenuItem(value: 'VG', child: Text(context.tr('VG'))),
                        DropdownMenuItem(value: 'G', child: Text('G')),
                      ],
                      onChanged: (v) => setD(() => condition = v ?? condition),
                    ),
                    SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: format,
                      decoration: InputDecoration(labelText: context.tr('Formato')),
                      items: const [
                        DropdownMenuItem(value: 'LP', child: Text(context.tr('LP'))),
                        DropdownMenuItem(value: 'EP', child: Text(context.tr('EP'))),
                        DropdownMenuItem(value: 'Single', child: Text(context.tr('Single'))),
                        DropdownMenuItem(value: '2xLP', child: Text(context.tr('2xLP'))),
                      ],
                      onChanged: (v) => setD(() => format = v ?? format),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('Cancelar'))),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('Guardar'))),
              ],
            );
          },
        );
      },
    );

    // Limpia controllers
    final newArtist = artistaCtrl.text.trim();
    final newAlbum = albumCtrl.text.trim();
    final newYear = yearCtrl.text.trim();
    artistaCtrl.dispose();
    albumCtrl.dispose();
    yearCtrl.dispose();

    if (saved != true) return;

    try {
      await VinylDb.instance.updateVinylDetails(
        id: id,
        artista: newArtist,
        album: newAlbum,
        year: newYear,
        condition: condition,
        format: format,
      );

      // Actualiza el mapa local para reflejar cambios sin recargar.
      widget.vinyl['artista'] = newArtist;
      widget.vinyl['album'] = newAlbum;
      widget.vinyl['year'] = newYear;
      widget.vinyl['condition'] = condition;
      widget.vinyl['format'] = format;
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Actualizado ✅'))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _loadTracks();
    _loadPrice();
  }

  String _fmtMoney(double v) {
    final r = v.round();
    if ((v - r).abs() < 0.001) return r.toString();
    return v.toStringAsFixed(2);
  }

  String _priceLabel() {
    if (loadingPrice) return '€ …';
    final pr = priceRange;
    if (pr == null) return '€ —';
    return '€ ${_fmtMoney(pr.min)} - ${_fmtMoney(pr.max)}';
  }

  Future<void> _loadPrice() async {
    final artista = (widget.vinyl['artista'] as String?)?.trim() ?? '';
    final album = (widget.vinyl['album'] as String?)?.trim() ?? '';
    final mbid = (widget.vinyl['mbid'] as String?)?.trim() ?? '';
    if (artista.isEmpty || album.isEmpty) return;
    setState(() {
      loadingPrice = true;
      priceRange = null;
    });
    try {
      final pr = await PriceRangeService.getRange(artist: artista, album: album, mbid: mbid.isEmpty ? null : mbid);
      if (!mounted) return;
      setState(() {
        priceRange = pr;
        loadingPrice = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        priceRange = null;
        loadingPrice = false;
      });
    }
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
      errorBuilder: (_, __, ___) => SizedBox(
        width: 120,
        height: 120,
        child: Center(child: Icon(Icons.album, size: 52)),
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return SizedBox(
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
    return SizedBox(
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
    final sub = dark ? Color(0xFFBDBDBD) : Colors.black54;
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
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$artista\n$album',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: fg),
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Editar'),
                  onPressed: _editMeta,
                  icon: Icon(Icons.edit, color: fg),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: fg),
                ),
              ],
            ),
            SizedBox(height: 10),

            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _pill(context, 'Orden', code),
                _pill(context, 'Año', year.isEmpty ? '—' : year),
                _pill(context, 'Precio', _priceLabel()),
                _pill(context, 'Género', genre.isEmpty ? '—' : genre),
                _pill(context, 'País', country.isEmpty ? '—' : country),
                if (condition.isNotEmpty) _pill(context, 'Condición', condition),
                if (format.isNotEmpty) _pill(context, 'Formato', format),
                if (wishlistStatus.isNotEmpty) _pill(context, 'Wishlist', wishlistStatus),
              ],
            ),

            SizedBox(height: 10),

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

            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(context.tr('Canciones'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: fg)),
                ),
                IconButton(onPressed: _loadTracks, icon: Icon(Icons.refresh, color: fg)),
              ],
            ),

            if (loadingTracks) LinearProgressIndicator(),
            if (!loadingTracks && msg != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(msg!, style: TextStyle(color: sub)),
              ),

            if (!loadingTracks && tracks.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  itemCount: tracks.length,
                  separatorBuilder: (_, __) => Divider(height: 1),
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