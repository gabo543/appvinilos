import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../db/vinyl_db.dart';
import '../services/discography_service.dart';
import '../services/vinyl_add_service.dart';
import '../services/add_defaults_service.dart';
import '../services/backup_service.dart';
import '../l10n/app_strings.dart';
import '../utils/normalize.dart';
import 'widgets/app_cover_image.dart';
import 'widgets/track_preview_button.dart';

class AlbumTracksScreen extends StatefulWidget {
  final AlbumItem album;
  final String artistName;
  final String? artistId;

  AlbumTracksScreen({
    super.key,
    required this.album,
    required this.artistName,
    this.artistId,
  });

  @override
  State<AlbumTracksScreen> createState() => _AlbumTracksScreenState();
}

class _AlbumTracksScreenState extends State<AlbumTracksScreen> {
  bool loading = true;
  String? msg;
  List<TrackItem> tracks = [];

  // ❤️ canciones guardadas para este álbum (por trackKey)
  Set<String> _likedKeys = <String>{};

  bool loadingInfo = true;
  ArtistInfo? info;

  bool _bioExpanded = false;


  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      msg = null;
      tracks = [];
      loadingInfo = true;
      info = null;
    });

    try {
      final futTracks = DiscographyService.getTracksFromReleaseGroup(widget.album.releaseGroupId);
      final futInfo = (widget.artistId != null && widget.artistId!.trim().isNotEmpty)
          ? DiscographyService.getArtistInfoById(widget.artistId!, artistName: widget.artistName)
          : DiscographyService.getArtistInfo(widget.artistName);

      final results = await Future.wait([futTracks, futInfo]);
      final list = results[0] as List<TrackItem>;
      final ainfo = results[1] as ArtistInfo;

      if (!mounted) return;
      setState(() {
        tracks = list;
        info = ainfo;
        loading = false;
        loadingInfo = false;
        msg = list.isEmpty ? 'No encontré canciones.' : null;
      });

      // Carga estado de "me gusta" para este álbum
      await _loadLikedKeys();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        tracks = [];
        info = null;
        loading = false;
        loadingInfo = false;
        msg = 'Error cargando información.';
      });
    }
  }

  Future<void> _loadLikedKeys() async {
    try {
      final keys = await VinylDb.instance.getLikedTrackKeysForReleaseGroup(widget.album.releaseGroupId);
      if (!mounted) return;
      setState(() => _likedKeys = keys);
    } catch (_) {
      // silencioso
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr(text))),
    );
  }

  Future<String?> _askWishlistStatus() async {
    String picked = 'Por comprar';
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: Text(context.tr('Estado (wishlist)')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    value: 'Por comprar',
                    groupValue: picked,
                    title: Text(context.tr('Por comprar')),
                    onChanged: (v) => setStateDialog(() => picked = v ?? picked),
                  ),
                  RadioListTile<String>(
                    value: 'Buscando',
                    groupValue: picked,
                    title: Text(context.tr('Buscando')),
                    onChanged: (v) => setStateDialog(() => picked = v ?? picked),
                  ),
                  RadioListTile<String>(
                    value: 'Comprado',
                    groupValue: picked,
                    title: Text(context.tr('Comprado')),
                    onChanged: (v) => setStateDialog(() => picked = v ?? picked),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(context.tr('Cancelar')),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, picked),
                  child: Text(context.tr('Aceptar')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _maybeAskAddAlbumAfterFirstLike() async {
    // Si ya existe en vinilos o deseos, no preguntamos.
    final existsVinyl = await VinylDb.instance.existsExact(artista: widget.artistName, album: widget.album.title);
    final wish = await VinylDb.instance.findWishlistByExact(artista: widget.artistName, album: widget.album.title);
    if (existsVinyl || wish != null) return;

    if (!mounted) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('¿Dónde quieres agregar este álbum?'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.artistName} — ${widget.album.title}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'vinyls'),
                  icon: const Icon(Icons.library_add),
                  label: Text(context.tr('A mis vinilos')),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'wish'),
                  icon: const Icon(Icons.playlist_add),
                  label: Text(context.tr('A deseos')),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(context.tr('Ahora no')),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (choice == null) return;

    if (choice == 'vinyls') {
      // mini-loading
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Agregando a vinilos...'),
            ],
          ),
        ),
      );
      final cond = await AddDefaultsService.getLastCondition(fallback: 'VG+');
      final fmt = await AddDefaultsService.getLastFormat(fallback: 'LP');
      try {
        final prepared = await VinylAddService.prepareFromReleaseGroup(
          artist: widget.artistName,
          album: widget.album.title,
          releaseGroupId: widget.album.releaseGroupId,
          year: widget.album.year,
          artistId: widget.artistId,
        );
        final res = await VinylAddService.addPrepared(
          prepared,
          favorite: false,
          condition: cond,
          format: fmt,
        );
        await BackupService.autoSaveIfEnabled();
        if (mounted) Navigator.pop(context);
        _snack(res.message);
      } catch (_) {
        if (mounted) Navigator.pop(context);
        _snack('Error agregando');
      }
    } else if (choice == 'wish') {
      final st = await _askWishlistStatus();
      if (st == null) return;
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Agregando a deseos...'),
            ],
          ),
        ),
      );
      try {
        await VinylDb.instance.addToWishlist(
          artista: widget.artistName,
          album: widget.album.title,
          year: widget.album.year,
          cover250: widget.album.cover250,
          cover500: widget.album.cover500,
          artistId: widget.artistId,
          status: st,
        );
        await BackupService.autoSaveIfEnabled();
        if (mounted) Navigator.pop(context);
        _snack('Agregado a deseos ✅');
      } catch (_) {
        if (mounted) Navigator.pop(context);
        _snack('Error agregando');
      }
    }
  }

  Future<void> _toggleLike(TrackItem t) async {
    final key = normalizeKey(t.title);
    final rg = widget.album.releaseGroupId;
    if (rg.trim().isEmpty) return;

    if (_likedKeys.contains(key)) {
      await VinylDb.instance.removeLikedTrack(releaseGroupId: rg, trackTitle: t.title);
      if (!mounted) return;
      setState(() => _likedKeys = {..._likedKeys}..remove(key));
      _snack('Quitada de canciones');
      // Si el auto-backup está activo, respalda también cambios en canciones.
      try {
        await BackupService.autoSaveIfEnabled();
      } catch (_) {}
      return;
    }

    // ¿ya existe algún track guardado para este álbum? (si sí, NO preguntamos por vinilos/deseos)
    final alreadyAlbumInSongs = await VinylDb.instance.hasAnyLikedTrackForReleaseGroup(rg);

    await VinylDb.instance.addLikedTrack(
      artista: widget.artistName,
      album: widget.album.title,
      year: widget.album.year,
      releaseGroupId: rg,
      cover250: widget.album.cover250,
      cover500: widget.album.cover500,
      trackTitle: t.title,
      trackNo: t.number,
    );

    if (!mounted) return;
    setState(() => _likedKeys = {..._likedKeys}..add(key));
    _snack('Canción guardada ❤️');

    // Si el auto-backup está activo, respalda también cambios en canciones.
    try {
      await BackupService.autoSaveIfEnabled();
    } catch (_) {}

    // Solo en el primer "me gusta" del álbum mostramos la pregunta.
    if (!alreadyAlbumInSongs) {
      await _maybeAskAddAlbumAfterFirstLike();
    }
  }

  @override
  Widget build(BuildContext context) {
    final y = widget.album.year ?? '—';
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        // En esta pantalla el contenido (reseña + tracklist) es lo más importante.
        // Quitamos el logo y dejamos solo la flecha de volver para ganar espacio visual.
        toolbarHeight: kToolbarHeight,
        automaticallyImplyLeading: true,
        title: const SizedBox.shrink(),
        actions: [
          IconButton(
            onPressed: _load,
            icon: Icon(Icons.refresh),
            tooltip: context.tr('Recargar canciones'),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  Row(
                    children: [
                      AppCoverImage(
                        pathOrUrl: widget.album.cover250,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.album.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            SizedBox(height: 4),
                            Text(
                              widget.artistName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              AppStrings.labeled(context, 'Año', y),
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  if (loadingInfo) LinearProgressIndicator(),
                  if (!loadingInfo && info != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              if ((info!.country ?? '').trim().isNotEmpty)
                                Chip(label: Text(AppStrings.labeled(context, 'País', info!.country!))),
                              ...info!.genres.take(4).map((g) => Chip(label: Text(g))),
                            ],
                          ),
                          if ((info!.bio ?? '').trim().isNotEmpty) ...[
                            SizedBox(height: 8),
                            Text(
                              info!.bio!,
                              maxLines: _bioExpanded ? 30 : 2,
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
                        ],
                      ),
                    ),
                  SizedBox(height: 12),
                  if (loading) LinearProgressIndicator(),
                  if (!loading && msg != null)
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(context.tr(msg!)),
                    ),
                  if (!loading && tracks.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        AppStrings.tracksCount(context, tracks.length),
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  SizedBox(height: 6),
                ],
              ),
            ),
          ),
          if (!loading && tracks.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 14),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    // Intercalamos divisores: item, divider, item, divider...
                    if (i.isOdd) return Divider(height: 1);
                    final idx = i ~/ 2;
                    final t = tracks[idx];
                    final liked = _likedKeys.contains(normalizeKey(t.title));
                    final usedArtist = (t.artist ?? '').trim().isNotEmpty ? t.artist!.trim() : widget.artistName;
                    final previewKey = '$usedArtist||${widget.album.title}||${t.title}';
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity(vertical: -2),
                      title: Text('${t.number}. ${t.title}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TrackPreviewButton(
                            cacheKey: previewKey,
                            artist: usedArtist,
                            album: widget.album.title,
                            title: t.title,
                            durationMs: t.lengthMs,
                            trackNumber: t.number,
                          ),
                          IconButton(
                            icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
                            tooltip: liked ? context.tr('Quitar de canciones') : context.tr('Guardar en canciones'),
                            onPressed: () => _toggleLike(t),
                          ),
                          if ((t.length ?? '').trim().isNotEmpty)
                            Text(
                              t.length!,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                        ],
                      ),
                    );
                  },
                  childCount: math.max(0, tracks.length * 2 - 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}