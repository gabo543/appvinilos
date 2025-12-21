import 'package:flutter/material.dart';
import '../services/discography_service.dart';

class AlbumTracksScreen extends StatefulWidget {
  final AlbumItem album;
  final String artistName;

  const AlbumTracksScreen({
    super.key,
    required this.album,
    required this.artistName,
  });

  @override
  State<AlbumTracksScreen> createState() => _AlbumTracksScreenState();
}

class _AlbumTracksScreenState extends State<AlbumTracksScreen> {
  bool loading = true;
  String? msg;
  List<TrackItem> tracks = [];

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
    });

    final list = await DiscographyService.getTracksFromReleaseGroup(widget.album.releaseGroupId);

    if (!mounted) return;

    setState(() {
      tracks = list;
      loading = false;
      msg = list.isEmpty ? 'No encontré canciones.' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final y = widget.album.year ?? '—';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album.title),
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
