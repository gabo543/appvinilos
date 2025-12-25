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
  bool _grid = false;

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

  /// Badge de estado para Wishlist (se ve bien tanto en tema claro como oscuro).
  Widget _statusChip(BuildContext context, String status) {
    final s = status.trim().toLowerCase();
    final scheme = Theme.of(context).colorScheme;

    Color bg;
    Color fg;
    IconData icon;

    if (s.contains('busc')) {
      // Buscando
      bg = scheme.secondaryContainer;
      fg = scheme.onSecondaryContainer;
      icon = Icons.search;
    } else if (s.contains('compr')) {
      // Por comprar / Comprar
      bg = scheme.tertiaryContainer;
      fg = scheme.onTertiaryContainer;
      icon = Icons.shopping_cart_outlined;
    } else if (s.contains('esper') || s.contains('pend') || s.contains('en lista')) {
      // En espera / Pendiente
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
      icon = Icons.hourglass_bottom;
    } else {
      bg = scheme.surfaceVariant;
      fg = scheme.onSurfaceVariant;
      icon = Icons.bookmark_border;
    }

    final textStyle = (Theme.of(context).textTheme.labelMedium ?? const TextStyle())
        .copyWith(color: fg, fontWeight: FontWeight.w800);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(status, style: textStyle),
        ],
      ),
    );
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

  
  Widget _metaPill(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = text.trim().isEmpty ? '—' : text.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(isDark ? 0.35 : 0.65),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(isDark ? 0.55 : 0.35)),
      ),
      child: Text(
        t,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
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

  Widget _leadingCover(Map<String, dynamic> w, {double size = 56}) {
    final cover = ((size >= 120 ? (w['cover500'] as String?) : null) ?? (w['cover250'] as String?))?.trim() ?? '';

    if (cover.startsWith('http://') || cover.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          cover,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }

    if (cover.isNotEmpty && File(cover).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(cover),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }

    return _placeholder();
  }

  Widget _wishListCard(Map<String, dynamic> w) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final artista = (w['artista'] ?? '').toString().trim();
    final album = (w['album'] ?? '').toString().trim();
    final year = (w['year'] ?? '').toString().trim();
    final status = (w['status'] ?? '').toString().trim();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(isDark ? 0.55 : 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openDetail(w),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                height: 92,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: cs.surfaceVariant.withOpacity(isDark ? 0.30 : 0.60),
                    child: _leadingCover(w, size: 92),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, right: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _metaPill(context, year),
                          if (status.isNotEmpty) _statusChip(context, status),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        artista.isEmpty ? '—' : artista,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        album.isEmpty ? '—' : album,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Agregar a vinilos',
                    icon: Icon(Icons.playlist_add, color: cs.onSurfaceVariant, size: 22),
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      final opts = await _askConditionAndFormat();
                      if (!mounted || opts == null) return;

                      final a = (w['artista'] ?? '').toString().trim();
                      final al = (w['album'] ?? '').toString().trim();
                      if (a.isEmpty || al.isEmpty) return;

                      try {
                        await VinylDb.instance.insertVinyl(
                          artista: a,
                          album: al,
                          condition: opts['condition'],
                          format: opts['format'],
                          year: (w['year'] ?? '').toString().trim().isEmpty ? null : w['year'].toString().trim(),
                          coverPath: (w['cover250'] ?? '').toString(),
                        );
                        final id = w['id'];
                        if (id is int) {
                          await VinylDb.instance.removeWishlistById(id);
                        }
                        await BackupService.autoSaveIfEnabled();
                        _snack('Agregado a tu lista de vinilos');
                        _reload();
                      } catch (_) {
                        _snack('No se pudo agregar');
                      }
                    },
                  ),
                  IconButton(
                    tooltip: 'Eliminar',
                    icon: Icon(Icons.delete_outline, color: cs.onSurfaceVariant, size: 22),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _removeItem(w),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wishGridCard(Map<String, dynamic> w) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final artista = (w['artista'] ?? '').toString().trim();
    final album = (w['album'] ?? '').toString().trim();
    final year = (w['year'] ?? '').toString().trim();
    final status = (w['status'] ?? '').toString().trim();

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(isDark ? 0.55 : 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openDetail(w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      color: cs.surfaceVariant.withOpacity(isDark ? 0.30 : 0.60),
                      child: _leadingCover(w, size: 220),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artista.isEmpty ? '—' : artista,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    album.isEmpty ? '—' : album,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _metaPill(context, year),
                      const SizedBox(width: 8),
                      if (status.isNotEmpty)
                        Expanded(child: Align(alignment: Alignment.centerLeft, child: _statusChip(context, status))),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Agregar a vinilos',
                        icon: Icon(Icons.playlist_add, color: cs.onSurfaceVariant, size: 20),
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          final opts = await _askConditionAndFormat();
                          if (!mounted || opts == null) return;

                          final a = (w['artista'] ?? '').toString().trim();
                          final al = (w['album'] ?? '').toString().trim();
                          if (a.isEmpty || al.isEmpty) return;

                          try {
                            await VinylDb.instance.insertVinyl(
                              artista: a,
                              album: al,
                              condition: opts['condition'],
                              format: opts['format'],
                              year: (w['year'] ?? '').toString().trim().isEmpty ? null : w['year'].toString().trim(),
                              coverPath: (w['cover250'] ?? '').toString(),
                            );
                            final id = w['id'];
                            if (id is int) {
                              await VinylDb.instance.removeWishlistById(id);
                            }
                            await BackupService.autoSaveIfEnabled();
                            _snack('Agregado a tu lista de vinilos');
                            _reload();
                          } catch (_) {
                            _snack('No se pudo agregar');
                          }
                        },
                      ),
                      IconButton(
                        tooltip: 'Eliminar',
                        icon: Icon(Icons.delete_outline, color: cs.onSurfaceVariant, size: 20),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _removeItem(w),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
        actions: [
          IconButton(
            tooltip: _grid ? 'Vista lista' : 'Vista grid',
            icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _grid = !_grid),
          ),
        ],
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

          return _grid
              ? GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _wishGridCard(items[i]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _wishListCard(items[i]),
                );
        },
      ),
    );
  }
}
