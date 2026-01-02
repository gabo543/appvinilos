import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';

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
