import 'package:flutter/material.dart';
import '../services/discography_service.dart';
import 'app_logo.dart';

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
        leadingWidth: appBarLeadingWidthForLogoBack(logoSize: 34),
        leading: appBarLeadingLogoBack(context, logoSize: 34),
        title: Text(widget.album.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        titleSpacing: 0,
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar canciones',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
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
                  child: Text(
                    '${widget.artistName}\nAño: $y',
                    style: const TextStyle(fontWeight: FontWeight.w800),
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
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
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
              Expanded(
                child: ListView.separated(
                  itemCount: tracks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final t = tracks[i];
                    return ListTile(
                      dense: true,
                      title: Text('${t.number}. ${t.title}'),
                      trailing: Text(t.length ?? ''),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
