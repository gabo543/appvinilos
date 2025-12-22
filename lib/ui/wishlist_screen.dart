import 'dart:io';
import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
import '../services/backup_service.dart';
import '../services/discography_service.dart';
import 'album_tracks_screen.dart';
import 'vinyl_detail_sheet.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = VinylDb.instance.getWishlist();
  }

  void _reload() {
    setState(() {
      _future = VinylDb.instance.getWishlist();
    });
  }

  

Future<Map<String, String>?> _askConditionAndFormat() async {
  String condition = 'VG+';
  String format = 'LP';

  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            title: const Text('Agregar a tu lista'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: condition,
                  decoration: const InputDecoration(labelText: 'Condición'),
                  items: const [
                    DropdownMenuItem(value: 'M', child: Text('M (Mint)')),
                    DropdownMenuItem(value: 'NM', child: Text('NM (Near Mint)')),
                    DropdownMenuItem(value: 'VG+', child: Text('VG+ (Very Good +)')),
                    DropdownMenuItem(value: 'VG', child: Text('VG (Very Good)')),
                    DropdownMenuItem(value: 'G', child: Text('G (Good)')),
                    DropdownMenuItem(value: 'P', child: Text('P (Poor)')),
                  ],
                  onChanged: (v) => setSt(() => condition = v ?? condition),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: format,
                  decoration: const InputDecoration(labelText: 'Formato'),
                  items: const [
                    DropdownMenuItem(value: 'LP', child: Text('LP')),
                    DropdownMenuItem(value: 'EP', child: Text('EP')),
                    DropdownMenuItem(value: 'Single', child: Text('Single')),
                    DropdownMenuItem(value: 'Box Set', child: Text('Box Set')),
                  ],
                  onChanged: (v) => setSt(() => format = v ?? format),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, {'condition': condition, 'format': format}),
                child: const Text('Aceptar'),
              ),
            ],
          );
        },
      );
    },
  );
}
void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _removeItem(Map<String, dynamic> w) async {
    final id = w['id'];
    if (id is! int) return;

    await VinylDb.instance.removeWishlistById(id);
    await BackupService.autoSaveIfEnabled();

    _snack('Eliminado de la lista de deseos');
    _reload();
  }

  Widget _placeholder() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.library_music, color: Colors.black45),
    );
  }

  Widget _leadingCover(Map<String, dynamic> w) {
    final cover250 = (w['cover250'] as String?)?.trim() ?? '';

    if (cover250.startsWith('http://') || cover250.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          cover250,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }

    if (cover250.isNotEmpty && File(cover250).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(cover250),
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }

    return _placeholder();
  }

  Future<void> _openDetail(Map<String, dynamic> w) async {
    final artistName = (w['artista'] ?? '').toString().trim();
    final albumTitle = (w['album'] ?? '').toString().trim();
    final year = (w['year'] ?? '').toString().trim();
              final status = (w['status'] ?? '').toString().trim();
    final cover250 = (w['cover250'] ?? '').toString().trim();
    final cover500 = (w['cover500'] ?? '').toString().trim();
    final artistId = (w['artistId'] ?? '').toString().trim();

    // ✅ Si tenemos artistId, intentamos abrir igual que Discografías (con canciones)
    if (artistId.isNotEmpty && artistName.isNotEmpty && albumTitle.isNotEmpty) {
      try {
        final discog = await DiscographyService.getDiscographyByArtistId(artistId);
        AlbumItem? match;
        for (final a in discog) {
          if (a.title.trim().toLowerCase() == albumTitle.toLowerCase()) {
            match = a;
            break;
          }
        }
        if (match != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AlbumTracksScreen(album: match!, artistName: artistName),
            ),
          );
          return;
        }
      } catch (_) {
        // fallback abajo
      }
    }

    // Fallback: mostramos detalle básico (sin tracks)
    final cover = cover500.isNotEmpty ? cover500 : cover250;
    final vinylLike = <String, dynamic>{
      'mbid': '',
      'coverPath': cover,
      'artista': artistName,
      'album': albumTitle,
      'year': year,
      'genre': '',
      'country': '',
      'artistBio': '',
    };

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VinylDetailSheet(vinyl: vinylLike),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lista de deseos'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error cargando wishlist: ${snap.error}'),
              ),
            );
          }

          final items = snap.data ?? const [];

          if (items.isEmpty) {
            return const Center(child: Text('Tu lista de deseos está vacía'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final w = items[i];
              final artista = (w['artista'] ?? '').toString().trim();
              final album = (w['album'] ?? '').toString().trim();
              final year = (w['year'] ?? '').toString().trim();
              final status = (w['status'] ?? '').toString().trim();

              return ListTile(
                onTap: () => _openDetail(w),
                leading: _leadingCover(w),
                title: Text(
                  album.isEmpty ? '—' : album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        if (artista.isNotEmpty) artista,
                        if (year.isNotEmpty) year,
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (status.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Agregar a tu lista de vinilos',
                      icon: const Icon(Icons.format_list_bulleted),
                      onPressed: () async {
                        final opts = await _askConditionAndFormat();
                        if (!mounted || opts == null) return;
                        final artista = (w['artista'] ?? '').toString().trim();
                        final album = (w['album'] ?? '').toString().trim();
                        if (artista.isEmpty || album.isEmpty) return;
                        try {
                          await VinylDb.instance.insertVinyl(
                            artista: artista,
                            album: album,
                            condition: opts['condition'],
                            format: opts['format'],
                            year: (w['year'] ?? '').toString().trim().isEmpty ? null : w['year'].toString().trim(),
                            coverPath: (w['cover250'] ?? '').toString(),
                          );
                          await VinylDb.instance.removeWishlistById(w['id']);
                          await BackupService.autoSaveIfEnabled();
                          _snack('Agregado a tu lista de vinilos');
                          _reload();
                        } catch (_) {
                          _snack('No se pudo agregar');
                        }
                      },
                    ),
                    IconButton(
                      tooltip: 'Eliminar de la lista de deseos',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _removeItem(w),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
