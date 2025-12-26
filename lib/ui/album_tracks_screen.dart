import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../services/discography_service.dart';

class AlbumTracksScreen extends StatefulWidget {
  final AlbumItem album;
  final String artistName;
  final String? artistId;

  const AlbumTracksScreen({
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
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar canciones',
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          widget.album.cover250,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.album, size: 48),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.album.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.artistName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              'Año: $y',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (loadingInfo) const LinearProgressIndicator(),
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
                                Chip(label: Text('País: ${info!.country}')),
                              ...info!.genres.take(4).map((g) => Chip(label: Text(g))),
                            ],
                          ),
                          if ((info!.bio ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              info!.bio!,
                              maxLines: _bioExpanded ? 30 : 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () => setState(() => _bioExpanded = !_bioExpanded),
                                child: Text(_bioExpanded ? 'Ver menos' : 'Ver más'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (loading) const LinearProgressIndicator(),
                  if (!loading && msg != null)
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(msg!),
                    ),
                  if (!loading && tracks.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Canciones (${tracks.length})',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  const SizedBox(height: 6),
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
                    if (i.isOdd) return const Divider(height: 1);
                    final idx = i ~/ 2;
                    final t = tracks[idx];
                    return ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -2),
                      title: Text('${t.number}. ${t.title}'),
                      trailing: Text(t.length ?? ''),
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
