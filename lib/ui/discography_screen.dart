import 'dart:async';
import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
import '../services/backup_service.dart';
import '../services/discography_service.dart';
import '../services/vinyl_add_service.dart';
import 'album_tracks_screen.dart';

class DiscographyScreen extends StatefulWidget {
  const DiscographyScreen({super.key});

  @override
  State<DiscographyScreen> createState() => _DiscographyScreenState();
}

class _DiscographyScreenState extends State<DiscographyScreen> {
  final artistCtrl = TextEditingController();
  Timer? _debounce;

  bool searchingArtists = false;
  List<ArtistHit> artistResults = [];

  bool loadingAlbums = false;
  ArtistHit? pickedArtist;
  List<AlbumItem> albums = [];

  // ✅ Cache local para que los iconos cambien INMEDIATO
  final Map<String, bool> _exists = {};
  final Map<String, bool> _fav = {};
  final Map<String, int?> _vinylId = {};
  final Map<String, bool> _wish = {};
  final Map<String, bool> _busy = {}; // bloquea mientras guarda

  String _k(String artist, String album) => '$artist||$album';


Future<Map<String, String>?> _askConditionAndFormat() async {
  String condition = 'VG+';
  String format = 'LP';

  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) {
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
              onChanged: (v) => condition = v ?? condition,
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
              onChanged: (v) => format = v ?? format,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, {'condition': condition, 'format': format}),
            child: const Text('Aceptar'),
          ),
        ],
      );
    },
  );
}


Future<String?> _askWishlistStatus() async {
  String status = 'Por comprar';

  return showDialog<String>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            title: const Text('Lista de deseos'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  value: 'Por comprar',
                  groupValue: status,
                  title: const Text('Por comprar'),
                  onChanged: (v) => setSt(() => status = v ?? status),
                ),
                RadioListTile<String>(
                  value: 'En camino',
                  groupValue: status,
                  title: const Text('En camino'),
                  onChanged: (v) => setSt(() => status = v ?? status),
                ),
                RadioListTile<String>(
                  value: 'Comprado',
                  groupValue: status,
                  title: const Text('Comprado'),
                  onChanged: (v) => setSt(() => status = v ?? status),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, status),
                child: const Text('Aceptar'),
              ),
            ],
          );
        },
      );
    },
  );
}

      

Future<void> _addAlbumOptimistic({
  required String artistName,
  required AlbumSuggest album,
  required String condition,
  required String format,
}) async {
  final key = _k(artistName, album.title);
  if (_busy[key] == true) return;

  // Si ya existe, no permitimos agregar de nuevo.
  if (_exists[key] == true) return;

  setState(() {
    _busy[key] = true;
    _exists[key] = true; // deshabilita el botón al toque
  });

  try {
    final prepared = await VinylAddService.prepare(
      artist: artistName,
      album: album.title,
      artistId: pickedArtist?.id,
    );

    final res = await VinylAddService.addPrepared(
      prepared,
      favorite: false,
      condition: condition,
      format: format,
    );

    if (!res.ok) {
      if (!mounted) return;
      setState(() {
        _exists[key] = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message)),
      );
      return;
    }

    // refrescar caches con el ID real
    final row = await VinylDb.instance.findByExact(artista: artistName, album: album.title);
    if (row != null) {
      _vinylId[key] = row['id'] as int?;
      _fav[key] = (row['favorite'] == 1);
    }

    await BackupService.autoSaveIfEnabled();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Agregado a tu lista ✅')),
    );
  } catch (_) {
    if (!mounted) return;
    setState(() {
      _exists[key] = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Error agregando a tu lista.')),
    );
  } finally {
    if (!mounted) return;
    setState(() => _busy[key] = false);
  }
}

Future<void> _toggleFavoriteOptimistic(String artistName, AlbumItem al) async {
    final key = _k(artistName, al.title);
    if (_busy[key] == true) return;

    final exists = _exists[key] == true;
    final currentFav = _fav[key] == true;

    // ✅ Regla: para ser favorito, el álbum debe estar agregado a tu lista
    if (!exists) return;

    // ✅ A veces el id aún no está hidratado (primera vez que tocas ⭐).
    //    En vez de obligarte a tocar 2 veces, lo hidratamos y seguimos.
    var id = _vinylId[key];
    if (id == null) {
      await _hydrateIfNeeded(artistName, al);
      id = _vinylId[key];
      if (id == null) return;
    }

    // ✅ Optimista: cambia UI al tiro
    setState(() {
      _busy[key] = true;
      _fav[key] = !currentFav;
    });

    try {
      await VinylDb.instance.setFavorite(id: id, favorite: !currentFav);
      await BackupService.autoSaveIfEnabled();
    } catch (_) {
      if (!mounted) return;
      // revert
      setState(() => _fav[key] = currentFav);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error actualizando favorito.')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _busy[key] = false);
    }
  }

  Future<void> _toggleWishlistOptimistic(String artistName, AlbumItem al, {String? status}) async {
    final key = _k(artistName, al.title);
    if (_busy[key] == true) return;

    final exists = _exists[key] == true;
    final inWish = _wish[key] == true;

    // ✅ Regla:
    // - Si ya está en tu lista de vinilos => wishlist deshabilitada
    // - Si ya está en wishlist => deshabilitada (sin opción de desmarcar desde discografías)
    if (exists || inWish) return;

    // ✅ Optimista: cambia UI al tiro
    setState(() {
      _busy[key] = true;
      _wish[key] = true;
    });

    try {
      await VinylDb.instance.addToWishlist(
        artista: artistName,
        album: al.title,
        year: al.year,
        cover250: al.cover250,
        cover500: al.cover500,
        artistId: pickedArtist?.id,
      );
      await BackupService.autoSaveIfEnabled();
    } catch (_) {
      if (!mounted) return;
      // revert
      setState(() => _wish[key] = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error actualizando lista deseos.')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _busy[key] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final artistName = pickedArtist?.name ?? artistCtrl.text.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Discografías')),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              controller: artistCtrl,
              onChanged: _onArtistTextChanged,
              decoration: const InputDecoration(
                labelText: 'Buscar artista',
                border: OutlineInputBorder(),
              ),
            ),
            if (searchingArtists) const LinearProgressIndicator(),

            if (artistResults.isNotEmpty)
              ListView.builder(
                shrinkWrap: true,
                itemCount: artistResults.length,
                itemBuilder: (_, i) {
                  final a = artistResults[i];
                  return ListTile(
                    dense: true,
                    title: Text(a.name),
                    subtitle: ((a.country ?? '').trim().isEmpty)
                        ? null
                        : Text('País: ${(a.country ?? '').trim()}'),
                    onTap: () => _pickArtist(a),
                  );
                },
              ),

            const SizedBox(height: 10),

            Expanded(
              child: loadingAlbums
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: albums.length,
                      itemBuilder: (_, i) {
                        final al = albums[i];
                        final year = al.year ?? '—';
                        final key = _k(artistName, al.title);

                        // si no está cargado el estado, lo hidratamos (una vez)
                        if (!_exists.containsKey(key) && _busy[key] != true && artistName.isNotEmpty) {
                          _hydrateIfNeeded(artistName, al);
                        }

                        final exists = _exists[key] == true;
                        final fav = _fav[key] == true;
                        final inWish = _wish[key] == true;
                        final busy = _busy[key] == true;

                        return Card(
                          child: ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                al.cover250,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.album),
                              ),
                            ),
                            title: Text(al.title),

                            // ✅ SUBTITLE con Año a la izquierda + 3 iconos abajo a la derecha
                            subtitle: Row(
                              children: [
                                Expanded(child: Text('Año: $year')),

                                // iconos bien a la derecha
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 1) ➕ Agregar
                                    IconButton(
                                      iconSize: 20,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
	                                      icon: Icon(
	                                        // mismo icono "líneas" que la Lista de vinilos
	                                        Icons.format_list_bulleted,
	                                        // borde blanco cuando está disponible, gris cuando está deshabilitado
	                                        color: (exists || busy) ? Colors.grey : Colors.white,
	                                      ),
                                      tooltip: exists ? 'Ya está en tu lista' : 'Agregar LP',
                                      onPressed: (busy || exists)
                                          ? null
                                          : () async {
                                              final opts = await _askConditionAndFormat();
                                              if (!mounted || opts == null) return;
                                              await _addAlbumOptimistic(
                                                artistName,
                                                al,
                                                favorite: false,
                                                condition: opts['condition'],
                                                format: opts['format'],
                                              );
                                            },
                                    ),

                                    // 2) ⭐ Favoritos
                                    IconButton(
                                      iconSize: 20,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
	                                      icon: Icon(
	                                        fav ? Icons.star : Icons.star_border,
	                                        // borde blanco (no marcado) + relleno gris (marcado)
	                                        color: !exists ? Colors.grey : (fav ? Colors.grey : Colors.white),
	                                      ),
                                      tooltip: !exists
                                          ? 'Agrega el álbum para marcar favorito'
                                          : (fav ? 'Quitar de favoritos' : 'Agregar a favoritos'),
                                      onPressed: (busy || !exists) ? null : () => _toggleFavoriteOptimistic(artistName, al),
                                    ),

                                    // 3) 🛒 Lista de deseos
                                    IconButton(
                                      iconSize: 20,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
	                                      icon: Icon(
	                                        inWish ? Icons.shopping_cart : Icons.shopping_cart_outlined,
	                                        // borde blanco cuando está disponible, gris si está deshabilitado
	                                        color: (exists || inWish || busy) ? Colors.grey : Colors.white,
	                                      ),
                                      tooltip: exists
                                          ? 'Ya está en tu lista de vinilos'
                                          : (inWish ? 'Ya está en tu lista deseos' : 'Agregar a lista deseos'),
                                      onPressed: (busy || exists || inWish)
                                          ? null
                                          : () async {
                                              final st = await _askWishlistStatus();
                                              if (!mounted || st == null) return;
                                              await _toggleWishlistOptimistic(artistName, al, status: st);
                                            },
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AlbumTracksScreen(
                                    album: al,
                                    artistName: artistName,
                                  ),
                                ),
                              );
                            },
                          ),
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
