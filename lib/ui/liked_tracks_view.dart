import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
import '../services/discography_service.dart';
import 'album_tracks_screen.dart';
import 'vinyl_detail_sheet.dart';

/// Vista "Canciones" dentro de Vinilos.
///
/// Guarda canciones favoritas con contexto (Artista/Álbum/Año)
/// y muestra si el álbum está en "Mis vinilos" o en "Deseos".
class LikedTracksView extends StatefulWidget {
  const LikedTracksView({super.key});

  @override
  State<LikedTracksView> createState() => _LikedTracksViewState();
}

class _LikedTracksViewState extends State<LikedTracksView> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = VinylDb.instance.getLikedTracksWithStatus();
  }

  Future<void> _reload() async {
    setState(() {
      _future = VinylDb.instance.getLikedTracksWithStatus();
    });
  }

  Future<void> _showVinylDetailSheet(Map<String, dynamic> v) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.90,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            child: VinylDetailSheet(vinyl: v, showPrices: false),
          ),
        ),
      ),
    );
  }

  Future<void> _openFromLikedRow(Map<String, dynamic> r) async {
    final track = (r['trackTitle'] ?? '').toString().trim();
    final artist = (r['artista'] ?? '').toString().trim();
    final album = (r['album'] ?? '').toString().trim();
    final year = (r['year'] ?? '').toString().trim();
    final rg = (r['releaseGroupId'] ?? '').toString().trim();
    final cover250 = (r['cover250'] ?? '').toString().trim();
    final cover500 = (r['cover500'] ?? '').toString().trim();

    if (artist.isEmpty || album.isEmpty) return;

    // Si el álbum está en "Mis vinilos", abrimos el detalle de tu colección.
    try {
      final v = await VinylDb.instance.findByExact(artista: artist, album: album);
      if (v != null && mounted) {
        await _showVinylDetailSheet(v);
        return;
      }
    } catch (_) {
      // ignore
    }

    // Fallback: abrimos la vista de tracks por release-group (Discografía).
    if (rg.isNotEmpty && mounted) {
      final albumItem = AlbumItem(
        releaseGroupId: rg,
        title: album,
        year: year.isEmpty ? null : year,
        cover250: cover250,
        cover500: cover500,
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AlbumTracksScreen(
            album: albumItem,
            artistName: artist,
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No pude abrir el álbum para "$track".')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _Empty(
            icon: Icons.error_outline,
            title: 'Error',
            subtitle: 'No pude cargar tus canciones. Cierra y vuelve a abrir la app.',
            onReload: _reload,
          );
        }

        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return _Empty(
            icon: Icons.favorite_border,
            title: 'Sin canciones todavía',
            subtitle: 'Abre Discografía → entra a un álbum → toca el ❤️ en una canción.',
            onReload: _reload,
          );
        }

        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = items[i];
              final id = (r['id'] is int) ? (r['id'] as int) : int.tryParse('${r['id']}') ?? 0;

              final track = (r['trackTitle'] ?? '').toString();
              final artist = (r['artista'] ?? '').toString();
              final album = (r['album'] ?? '').toString();
              final year = (r['year'] ?? '').toString().trim();

              final inVinyls = _asBool(r['inVinyls']);
              final inWishlist = _asBool(r['inWishlist']);
              final releaseGroupId = (r['releaseGroupId'] ?? '').toString().trim();
              final cover250 = (r['cover250'] ?? '').toString().trim();
              final cover500 = (r['cover500'] ?? '').toString().trim();

              return ListTile(
                leading: const Icon(Icons.favorite, size: 22),
                title: Text(track, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    artist,
                    album,
                    if (year.isNotEmpty) 'Año $year',
                  ].where((e) => e.trim().isNotEmpty).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () async {
                  // 1) Si el álbum existe en Mis Vinilos, abrimos el detalle del vinilo.
                  final v = await VinylDb.instance.findByExact(artista: artist, album: album);
                  if (v != null) {
                    await _showVinylDetailSheet(v);
                    return;
                  }

                  // 2) Si tenemos releaseGroupId, abrimos el álbum (tracklist) desde Discografía.
                  if (releaseGroupId.isNotEmpty && artist.isNotEmpty && album.isNotEmpty) {
                    final a = AlbumItem(
                      releaseGroupId: releaseGroupId,
                      title: album,
                      year: year.isEmpty ? null : year,
                      cover250: cover250,
                      cover500: cover500.isNotEmpty ? cover500 : cover250,
                    );
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AlbumTracksScreen(album: a, artistName: artist),
                      ),
                    );
                    return;
                  }

                  // 3) Fallback: nada que abrir.
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No puedo abrir este álbum.')),
                  );
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (inVinyls)
                      Tooltip(
                        message: 'En Vinilos',
                        child: Icon(Icons.library_music, size: 20),
                      ),
                    if (inWishlist) ...[
                      if (inVinyls) const SizedBox(width: 10),
                      Tooltip(
                        message: 'En Deseos',
                        child: Icon(Icons.shopping_cart, size: 20),
                      ),
                    ],
                    const SizedBox(width: 10),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Quitar canción',
                      onPressed: id <= 0
                          ? null
                          : () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Quitar canción'),
                                  content: Text('¿Eliminar "$track" de tu lista de canciones?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancelar'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Eliminar'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok != true) return;
                              await VinylDb.instance.removeLikedTrackById(id);
                              await _reload();
                            },
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  bool _asBool(dynamic v) {
    if (v is int) return v != 0;
    final s = (v ?? '').toString().toLowerCase().trim();
    return s == '1' || s == 'true' || s == 'yes';
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onReload;

  const _Empty({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onReload,
              icon: const Icon(Icons.refresh),
              label: const Text('Recargar'),
            ),
          ],
        ),
      ),
    );
  }
}