import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
import '../services/add_defaults_service.dart';
import '../services/backup_service.dart';
import '../services/discography_service.dart';
import '../services/price_range_service.dart';
import '../services/vinyl_add_service.dart';
import '../l10n/app_strings.dart';
import 'widgets/track_preview_button.dart';

/// Ficha previa a agregar, usada desde el Escáner (código / carátula / escuchar).
///
/// Muestra carátula, info principal, reseña (bio) y tracklist.
/// Abajo tiene un botón "Agregar" que abre el flujo:
/// - Lista -> Condición + Formato -> Agregar
/// - Deseos -> Estado -> Agregar
class AddVinylPreviewScreen extends StatefulWidget {
  final PreparedVinylAdd prepared;
  AddVinylPreviewScreen({super.key, required this.prepared});

  @override
  State<AddVinylPreviewScreen> createState() => _AddVinylPreviewScreenState();
}

enum _AddDestination { collection, wishlist }

class _AddVinylPreviewScreenState extends State<AddVinylPreviewScreen> {
  bool _loadingTracks = false;
  String? _tracksMsg;
  List<TrackItem> _tracks = [];

  bool _loadingPrice = false;
  PriceRange? _priceRange;

  bool _bioExpanded = false;

  // Ediciones (releases) para elegir fallback de carátula / referencia.
  bool _loadingEditions = false;
  List<ReleaseEdition> _editions = const [];
  ReleaseEdition? _selectedEdition;

  // ID de colección sugerido (artistNo.albumNo) según el artista.
  bool _loadingNextCode = false;
  String? _nextCollectionCode;

  @override
  void initState() {
    super.initState();
    _loadTracks();
    _loadPrice();
    _loadNextCollectionCode();
    // Si venimos desde un flujo que ya trae releaseId (barcode),
    // mostramos "Edición: seleccionada" y, si el usuario abre "Ver ediciones",
    // intentaremos marcarla.
  }

  String _editionLabel() {
    final e = _selectedEdition;
    if (e != null) {
      final bits = <String>[];
      final y = (e.year ?? '').trim();
      if (y.isNotEmpty) bits.add(y);
      final c = (e.country ?? '').trim();
      if (c.isNotEmpty) bits.add(c);
      final s = (e.status ?? '').trim();
      if (s.isNotEmpty) bits.add(s);
      return bits.isEmpty ? context.tr('Edición seleccionada') : bits.join(' · ');
    }

    final rid = (widget.prepared.releaseId ?? '').trim();
    if (rid.isNotEmpty) return context.tr('Edición: seleccionada (barcode)');
    return context.tr('Edición: auto');
  }

  Future<void> _openEditionsPicker() async {
    final rgid = (widget.prepared.releaseGroupId ?? '').trim();
    if (rgid.isEmpty) {
      _snack('No hay ediciones disponibles para este álbum.');
      return;
    }

    if (_loadingEditions) return;

    // Cargar ediciones si aún no las tenemos.
    if (_editions.isEmpty) {
      setState(() => _loadingEditions = true);
      try {
        final list = await DiscographyService.getEditionsFromReleaseGroup(rgid);
        if (!mounted) return;
        setState(() {
          _editions = list;
          _loadingEditions = false;
          // Si veníamos con releaseId (barcode), intentamos marcarla.
          final rid = (widget.prepared.releaseId ?? '').trim();
          if (rid.isNotEmpty) {
            final hits = list.where((x) => x.id == rid).toList();
            _selectedEdition = hits.isEmpty ? null : hits.first;
          }
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _loadingEditions = false);
        _snack('Error cargando ediciones.');
        return;
      }
    }

    if (_editions.isEmpty) {
      _snack('No encontré ediciones.');
      return;
    }

    final chosen = await showModalBottomSheet<ReleaseEdition>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final year = (widget.prepared.year ?? '').trim();
        final currentId = (_selectedEdition?.id ?? (widget.prepared.releaseId ?? '')).trim();

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('Elige una edición'),
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  year.isEmpty
                      ? context.tr('El año guardado será el de la primera edición (si existe).')
                      : 'Año guardado: $year (1ra edición)',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _editions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final e = _editions[i];
                      final selected = e.id == currentId;

                      final meta = <String>[];
                      final y = (e.year ?? '').trim();
                      if (y.isNotEmpty) meta.add(y);
                      final c = (e.country ?? '').trim();
                      if (c.isNotEmpty) meta.add(c);
                      final s = (e.status ?? '').trim();
                      if (s.isNotEmpty) meta.add(s);
                      final b = (e.barcode ?? '').trim();
                      if (b.isNotEmpty) meta.add('EAN $b');

                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(ctx, e),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selected ? cs.primaryContainer.withOpacity(0.55) : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected ? cs.primary : cs.outlineVariant,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked,
                                  color: selected ? cs.primary : cs.onSurfaceVariant),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                                    ),
                                    const SizedBox(height: 2),
                                    if (meta.isNotEmpty)
                                      Text(
                                        meta.join(' · '),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(ctx).textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(context.tr('Cerrar')),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || chosen == null) return;

    // Aplicamos: solo afecta fallback de carátula (release). El año guardado no cambia.
    setState(() {
      _selectedEdition = chosen;
      widget.prepared.releaseId = chosen.id;
      widget.prepared.coverFallback250 = 'https://coverartarchive.org/release/${chosen.id}/front-250';
      widget.prepared.coverFallback500 = 'https://coverartarchive.org/release/${chosen.id}/front-500';
    });
  }

  Future<void> _loadNextCollectionCode() async {
    final artist = widget.prepared.artist.trim();
    if (artist.isEmpty) return;
    setState(() {
      _loadingNextCode = true;
      _nextCollectionCode = null;
    });
    try {
      final code = await VinylDb.instance.previewNextCollectionCode(artist);
      if (!mounted) return;
      setState(() {
        _nextCollectionCode = code;
        _loadingNextCode = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nextCollectionCode = null;
        _loadingNextCode = false;
      });
    }
  }

  String _fmtMoney(double v) {
    final r = v.round();
    if ((v - r).abs() < 0.001) return r.toString();
    return v.toStringAsFixed(2);
  }

  String _priceLabel() {
    if (_loadingPrice) return '€ …';
    final pr = _priceRange;
    if (pr == null) return '';

    final a = _fmtMoney(pr.min);
    final b = _fmtMoney(pr.max);

    if (a == b) return '€ $a';
    return '€ $a - $b';
  }

  Future<void> _loadPrice() async {
    setState(() {
      _loadingPrice = true;
      _priceRange = null;
    });

    try {
      final pr = await PriceRangeService.getRange(
        artist: widget.prepared.artist,
        album: widget.prepared.album,
        mbid: (widget.prepared.releaseGroupId ?? '').trim().isEmpty ? null : widget.prepared.releaseGroupId,
      );
      if (!mounted) return;
      setState(() {
        _priceRange = pr;
        _loadingPrice = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _priceRange = null;
        _loadingPrice = false;
      });
    }
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  String? _bestCover({bool prefer500 = true}) {
    final p = widget.prepared;
    if (prefer500) {
      final c = (p.selectedCover500 ?? '').trim();
      if (c.isNotEmpty) return c;
      final f = (p.coverFallback500 ?? '').trim();
      if (f.isNotEmpty) return f;
      final c250 = (p.selectedCover250 ?? '').trim();
      if (c250.isNotEmpty) return c250;
      final f250 = (p.coverFallback250 ?? '').trim();
      if (f250.isNotEmpty) return f250;
      return null;
    }
    final c250 = (p.selectedCover250 ?? '').trim();
    if (c250.isNotEmpty) return c250;
    final f250 = (p.coverFallback250 ?? '').trim();
    if (f250.isNotEmpty) return f250;
    final c = (p.selectedCover500 ?? '').trim();
    if (c.isNotEmpty) return c;
    final f = (p.coverFallback500 ?? '').trim();
    if (f.isNotEmpty) return f;
    return null;
  }

  Future<void> _loadTracks() async {
    final rgid = (widget.prepared.releaseGroupId ?? '').trim();
    if (rgid.isEmpty) {
      setState(() {
        _loadingTracks = false;
        _tracks = [];
        _tracksMsg = 'No hay tracklist disponible.';
      });
      return;
    }

    setState(() {
      _loadingTracks = true;
      _tracksMsg = null;
      _tracks = [];
    });

    try {
      final list = await DiscographyService.getTracksFromReleaseGroup(rgid);
      if (!mounted) return;
      setState(() {
        _tracks = list;
        _loadingTracks = false;
        _tracksMsg = list.isEmpty ? 'No encontré canciones.' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tracks = [];
        _loadingTracks = false;
        _tracksMsg = 'Error cargando canciones.';
      });
    }
  }

  Future<void> _onAddPressed() async {
    final dest = await _pickDestination();
    if (!mounted || dest == null) return;

    bool added = false;
    switch (dest) {
      case _AddDestination.collection:
        added = await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _CollectionAddSheet(prepared: widget.prepared),
            ) ??
            false;
        break;
      case _AddDestination.wishlist:
        added = await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _WishlistAddSheet(prepared: widget.prepared),
            ) ??
            false;
        break;
    }

    if (!mounted) return;
    if (added) {
      _snack('Listo ✅');
      Navigator.pop(context, true);
    }
  }

  Future<_AddDestination?> _pickDestination() async {
    return showModalBottomSheet<_AddDestination>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        _AddDestination selected = _AddDestination.collection;
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(context.tr('¿Dónde quieres agregarlo?'),
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 10),
                    RadioListTile<_AddDestination>(
                      value: _AddDestination.collection,
                      groupValue: selected,
                      title: Text(context.tr('Lista (mi colección)')),
                      secondary: Icon(Icons.library_music_outlined),
                      onChanged: (v) => setStateDialog(() => selected = v ?? selected),
                    ),
                    RadioListTile<_AddDestination>(
                      value: _AddDestination.wishlist,
                      groupValue: selected,
                      title: Text(context.tr('Deseos (wishlist)')),
                      secondary: Icon(Icons.favorite_border),
                      onChanged: (v) => setStateDialog(() => selected = v ?? selected),
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(context.tr('Cancelar')),
                          ),
                        ),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(ctx, selected),
                            child: Text(context.tr('Continuar')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final p = widget.prepared;

    final local = (p.localCoverPath ?? '').trim();
    final hasLocal = local.isNotEmpty && File(local).existsSync();

    // Si el usuario eligió una edición (o venimos por barcode), intentamos
    // mostrar primero la carátula del release (edición) y, si falla, caemos
    // a la del release-group.
    final releaseCover = hasLocal
        ? null
        : (((p.coverFallback500 ?? '').trim().isNotEmpty)
            ? p.coverFallback500!.trim()
            : (((p.coverFallback250 ?? '').trim().isNotEmpty) ? p.coverFallback250!.trim() : null));

    final groupCover = hasLocal ? null : _bestCover(prefer500: true);

    final preferRelease = (_selectedEdition != null) || (p.releaseId ?? '').trim().isNotEmpty;
    final coverPrimary = preferRelease ? (releaseCover ?? groupCover) : (groupCover ?? releaseCover);
    final coverSecondary = (coverPrimary == releaseCover) ? groupCover : releaseCover;
    final year = (p.year ?? '').trim();
    final genre = (p.genre ?? '').trim();
    final country = (p.country ?? '').trim();
    final bio = (p.bioShort ?? '').trim();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(context.tr('Disco')),
        actions: [
          IconButton(
            tooltip: context.tr('Recargar canciones'),
            onPressed: _loadTracks,
            icon: Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: context.tr('Actualizar precio'),
            onPressed: _loadPrice,
            icon: Icon(Icons.euro),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: FilledButton.icon(
          onPressed: _onAddPressed,
          icon: Icon(Icons.add),
          label: Text(context.tr('Agregar')),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: 112,
                          height: 112,
                          color: cs.surfaceContainerHighest,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (hasLocal)
                                Image.file(File(local), fit: BoxFit.cover)
                              else if (coverPrimary == null)
                                Icon(Icons.album, size: 46)
                              else
                                Image.network(
                                  coverPrimary!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) {
                                    final sec = coverSecondary;
                                    if (sec != null && sec != coverPrimary) {
                                      return Image.network(
                                        sec,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(Icons.album, size: 46),
                                      );
                                    }
                                    return Icon(Icons.album, size: 46);
                                  },
                                ),
                              if (hasLocal)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Material(
                                    color: cs.surface.withOpacity(0.85),
                                    borderRadius: BorderRadius.circular(999),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(999),
                                      onTap: () => setState(() => p.localCoverPath = null),
                                      child: Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: Icon(Icons.close, size: 18),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            SizedBox(height: 2),
                            Text(
                              p.album,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (year.isNotEmpty)
                                  Chip(
                                    label: Text(
                                      AppStrings.labeled(context, 'Año (1ra ed.)', year),
                                      style: TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (_loadingNextCode)
                                  Chip(
                                    label: Text(AppStrings.labeled(context, 'ID colección', '…'), style: TextStyle(fontWeight: FontWeight.w800)),
                                    visualDensity: VisualDensity.compact,
                                  )
                                else if ((_nextCollectionCode ?? '').trim().isNotEmpty)
                                  Chip(
                                    label: Text(
                                      AppStrings.labeled(context, 'ID colección', _nextCollectionCode!),
                                      style: TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (_priceLabel().trim().isNotEmpty)
                                  Chip(
                                    label: Text(_priceLabel(), style: TextStyle(fontWeight: FontWeight.w800)),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (genre.isNotEmpty)
                                  Chip(
                                    label: Text(genre, style: TextStyle(fontWeight: FontWeight.w800)),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (country.isNotEmpty)
                                  Chip(
                                    label: Text(AppStrings.labeled(context, 'País', country), style: TextStyle(fontWeight: FontWeight.w800)),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                            if ((p.releaseGroupId ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(Icons.layers_outlined, size: 18, color: cs.onSurfaceVariant),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _editionLabel(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _openEditionsPicker,
                                    child: Text(context.tr('Ver ediciones')),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),

                  // Selector de carátula (si hay más de una opción)
                  if (p.coverCandidates.length > 1) ...[
                    Text(context.tr('Carátulas'), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    SizedBox(height: 8),
                    SizedBox(
                      height: 58,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: p.coverCandidates.length,
                        separatorBuilder: (_, __) => SizedBox(width: 10),
                        itemBuilder: (_, i) {
                          final c = p.coverCandidates[i];
                          final selected = identical(p.selectedCover, c);
                          final url = (c.coverUrl250 ?? c.coverUrl500 ?? '').trim();
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setState(() => p.selectedCover = c),
                            child: Container(
                              width: 58,
                              height: 58,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected ? cs.primary : cs.outlineVariant,
                                  width: selected ? 2 : 1,
                                ),
                                color: cs.surfaceContainerHighest.withOpacity(selected ? 0.55 : 0.30),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: url.isEmpty
                                    ? Center(child: Icon(Icons.album, size: 20))
                                    : Image.network(
                                        url,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Center(child: Icon(Icons.album, size: 20)),
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(height: 12),
                  ],

                  // Reseña
                  if (bio.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.article_outlined, size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(context.tr('Reseña'),
                                  style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Text(
                            bio,
                            maxLines: _bioExpanded ? 30 : 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => setState(() => _bioExpanded = !_bioExpanded),
                              child: Text(_bioExpanded ? context.tr('Ver menos') : context.tr('Ver más')),

                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Tracklist header
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(context.tr('Canciones'),
                      style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (_loadingTracks) SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ),
          ),

          if (_tracksMsg != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              sliver: SliverToBoxAdapter(child: Text(_tracksMsg!)),
            ),

          if (_tracks.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    if (i.isOdd) return Divider(height: 1);
                    final idx = i ~/ 2;
                    final tr = _tracks[idx];
                    final artist = widget.prepared.artist;
                    final album = widget.prepared.album;
                    final previewKey = '$artist||$album||${tr.title}';
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity(vertical: -2),
                      title: Text('${tr.number}. ${tr.title}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TrackPreviewButton(
                            cacheKey: previewKey,
                            artist: artist,
                            album: album,
                            title: tr.title,
                          ),
                          if ((tr.length ?? '').trim().isNotEmpty)
                            Text(
                              tr.length!.trim(),
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                        ],
                      ),
                    );
                  },
                  childCount: math.max(0, _tracks.length * 2 - 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CollectionAddSheet extends StatefulWidget {
  final PreparedVinylAdd prepared;
  const _CollectionAddSheet({required this.prepared});

  @override
  State<_CollectionAddSheet> createState() => _CollectionAddSheetState();
}

class _CollectionAddSheetState extends State<_CollectionAddSheet> {
  late final TextEditingController _yearCtrl;
  bool _saving = false;

  bool _loadingNextCode = false;
  String? _nextCollectionCode;

  String _condition = 'VG+';
  String _format = 'LP';

  @override
  void initState() {
    super.initState();
    _yearCtrl = TextEditingController(text: widget.prepared.year ?? '');
    _loadDefaults();
    _loadNextCollectionCode();
  }

  Future<void> _loadNextCollectionCode() async {
    final artist = widget.prepared.artist.trim();
    if (artist.isEmpty) return;
    setState(() {
      _loadingNextCode = true;
      _nextCollectionCode = null;
    });
    try {
      final code = await VinylDb.instance.previewNextCollectionCode(artist);
      if (!mounted) return;
      setState(() {
        _nextCollectionCode = code;
        _loadingNextCode = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nextCollectionCode = null;
        _loadingNextCode = false;
      });
    }
  }

  Future<void> _loadDefaults() async {
    try {
      final c = await AddDefaultsService.getLastCondition(fallback: _condition);
      final f = await AddDefaultsService.getLastFormat(fallback: _format);
      if (!mounted) return;
      setState(() {
        _condition = c;
        _format = f;
      });
    } catch (_) {
      // ignore
    }
  }

  @override
  void dispose() {
    _yearCtrl.dispose();
    super.dispose();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _add() async {
    if (_saving) return;
    setState(() => _saving = true);

    final res = await VinylAddService.addPrepared(
      widget.prepared,
      overrideYear: _yearCtrl.text.trim().isEmpty ? null : _yearCtrl.text.trim(),
      favorite: false,
      condition: _condition,
      format: _format,
    );

    await BackupService.autoSaveIfEnabled();
    if (!mounted) return;
    setState(() => _saving = false);

    _snack(res.message);
    if (res.ok) {
      await AddDefaultsService.saveLast(condition: _condition, format: _format);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final p = widget.prepared;
    final cover = (p.selectedCover250 ?? p.coverFallback250 ?? '').trim();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 6,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(context.tr('Condición y formato'),
                  style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              if (_saving) SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 72,
                  height: 72,
                  color: cs.surfaceContainerHighest,
                  child: cover.isEmpty
                      ? Icon(Icons.album, size: 28)
                      : Image.network(
                          cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(Icons.album, size: 28),
                        ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.artist, style: TextStyle(fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
                    SizedBox(height: 2),
                    Text(p.album, style: TextStyle(fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (_loadingNextCode)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          AppStrings.labeled(context, 'ID colección', '…'),
                          style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      )
                    else if ((_nextCollectionCode ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          AppStrings.labeled(context, 'ID colección', _nextCollectionCode!),
                          style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    SizedBox(height: 10),
                    TextField(
                      controller: _yearCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: context.tr('Año'), isDense: true),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _condition,
                  decoration: InputDecoration(labelText: context.tr('Condición'), isDense: true),
                  items: [
                    DropdownMenuItem(value: 'M', child: Text(context.tr('M (Mint)'))),
                    DropdownMenuItem(value: 'NM', child: Text(context.tr('NM (Near Mint)'))),
                    DropdownMenuItem(value: 'VG+', child: Text(context.tr('VG+'))),
                    DropdownMenuItem(value: 'VG', child: Text(context.tr('VG'))),
                    DropdownMenuItem(value: 'G', child: Text('G')),
                  ],
                  onChanged: (v) => setState(() => _condition = v ?? _condition),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _format,
                  decoration: InputDecoration(labelText: context.tr('Formato'), isDense: true),
                  items: [
                    DropdownMenuItem(value: 'LP', child: Text(context.tr('LP'))),
                    DropdownMenuItem(value: 'EP', child: Text(context.tr('EP'))),
                    DropdownMenuItem(value: 'Single', child: Text(context.tr('Single'))),
                    DropdownMenuItem(value: '2xLP', child: Text(context.tr('2xLP'))),
                  ],
                  onChanged: (v) => setState(() => _format = v ?? _format),
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _saving ? null : _add,
            icon: Icon(Icons.check),
            label: Text(context.tr('Agregar a Lista')),
          ),
          SizedBox(height: 8),
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: Text(context.tr('Atrás')),
          ),
        ],
      ),
    );
  }
}

class _WishlistAddSheet extends StatefulWidget {
  final PreparedVinylAdd prepared;
  const _WishlistAddSheet({required this.prepared});

  @override
  State<_WishlistAddSheet> createState() => _WishlistAddSheetState();
}

class _WishlistAddSheetState extends State<_WishlistAddSheet> {
  bool _saving = false;
  String _status = 'Por comprar';

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _add() async {
    if (_saving) return;
    setState(() => _saving = true);

    final p = widget.prepared;
    final existing = await VinylDb.instance.findWishlistByExact(artista: p.artist, album: p.album);
    if (existing != null) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Ya existe en Deseos.');
      return;
    }

    final cover250 = (p.selectedCover250 ?? p.coverFallback250 ?? '').trim();
    final cover500 = (p.selectedCover500 ?? p.coverFallback500 ?? '').trim();

    await VinylDb.instance.addToWishlist(
      artista: p.artist,
      album: p.album,
      year: p.year,
      cover250: cover250.isEmpty ? null : cover250,
      cover500: cover500.isEmpty ? null : cover500,
      artistId: p.artistId,
      status: _status,
    );

    await BackupService.autoSaveIfEnabled();
    if (!mounted) return;
    setState(() => _saving = false);

    _snack('Agregado a Deseos ✅');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final p = widget.prepared;
    final cover = (p.selectedCover250 ?? p.coverFallback250 ?? '').trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(context.tr('Estado en Deseos'),
                  style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              if (_saving) SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 72,
                  height: 72,
                  color: cs.surfaceContainerHighest,
                  child: cover.isEmpty
                      ? Icon(Icons.album, size: 28)
                      : Image.network(
                          cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(Icons.album, size: 28),
                        ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.artist, style: TextStyle(fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
                    SizedBox(height: 2),
                    Text(p.album, style: TextStyle(fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
                    SizedBox(height: 6),
                    Text("${context.tr('Año')}: ${(p.year ?? '—')}", style: TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          RadioListTile<String>(
            value: 'Por comprar',
            groupValue: _status,
            title: Text(context.tr('Por comprar')),
            onChanged: _saving ? null : (v) => setState(() => _status = v ?? _status),
          ),
          RadioListTile<String>(
            value: 'Buscando',
            groupValue: _status,
            title: Text(context.tr('Buscando')),
            onChanged: _saving ? null : (v) => setState(() => _status = v ?? _status),
          ),
          RadioListTile<String>(
            value: 'Comprado',
            groupValue: _status,
            title: Text(context.tr('Comprado')),
            onChanged: _saving ? null : (v) => setState(() => _status = v ?? _status),
          ),
          SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _saving ? null : _add,
            icon: Icon(Icons.check),
            label: Text(context.tr('Agregar a Deseos')),
          ),
          SizedBox(height: 8),
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: Text(context.tr('Atrás')),
          ),
        ],
      ),
    );
  }
}
