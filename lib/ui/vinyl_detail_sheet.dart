import 'dart:io';
import 'package:flutter/material.dart';
import '../services/discography_service.dart';

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
    final artista = (widget.vinyl['artista'] as String?) ?? '';
    final album = (widget.vinyl['album'] as String?) ?? '';
    final year = (widget.vinyl['year'] as String?)?.trim() ?? '';
    final genre = (widget.vinyl['genre'] as String?)?.trim() ?? '';
    final country = (widget.vinyl['country'] as String?)?.trim() ?? '';
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
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _pill('Año', year.isEmpty ? '—' : year),
                _pill('Género', genre.isEmpty ? '—' : genre),
                _pill('País', country.isEmpty ? '—' : country),
              ],
            ),

            const SizedBox(height: 10),

            if (bio.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12),
                ),
                child: Text(bio),
              ),

            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text('Canciones', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
                IconButton(onPressed: _loadTracks, icon: const Icon(Icons.refresh)),
              ],
            ),

            if (loadingTracks) const LinearProgressIndicator(),
            if (!loadingTracks && msg != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(msg!),
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

  Widget _pill(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Text('$k: $v', style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
