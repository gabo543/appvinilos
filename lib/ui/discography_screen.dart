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

  @override
  void dispose() {
    _debounce?.cancel();
    artistCtrl.dispose();
    super.dispose();
  }

  void _onArtistTextChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        artistResults = [];
        searchingArtists = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => searchingArtists = true);
      final hits = await DiscographyService.searchArtists(q);
      if (!mounted) return;
      setState(() {
        artistResults = hits;
        searchingArtists = false;
      });
    });
  }

  Future<void> _pickArtist(ArtistHit a) async {
    FocusScope.of(context).unfocus();

    setState(() {
      pickedArtist = a;
      artistCtrl.text = a.name;
      artistResults = [];
      albums = [];
      loadingAlbums = true;

      // limpia caches al cambiar artista
      _exists.clear();
      _fav.clear();
      _vinylId.clear();
      _wish.clear();
      _busy.clear();
    });

    final list = await DiscographyService.getDiscographyByArtistId(a.id);

    if (!mounted) return;

    setState(() {
      albums = list;
      loadingAlbums = false;
    });
  }

  Future<void> _hydrateIfNeeded(String artistName, AlbumItem al) async {
    final key = _k(artistName, al.title);
    if (_exists.containsKey(key) || _busy[key] == true) return;

    _busy[key] = true;
    try {
      final r = await Future.wait([
        VinylDb.instance.findByExact(artista: artistName, album: al.title),
        VinylDb.instance.findWishlistByExact(artista: artistName, album: al.title),
      ]);

      final vinyl = r[0] as Map<String, dynamic>?;
      final wish = r[1] as Map<String, dynamic>?;

      _exists[key] = vinyl != null;
      _vinylId[key] = vinyl?['id'] as int?;
      _fav[key] = (vinyl != null) ? ((vinyl['favorite'] ?? 0) == 1) : false;
      _wish[key] = (wish != null);
    } finally {
      _busy[key] = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _addAlbumOptimistic(String artistName, AlbumItem al, {required bool favorite}) async {
    final key = _k(artistName, al.title);
    if (_busy[key] == true) return;

    // ✅ Optimista: cambia UI al tiro
    setState(() {
      _busy[key] = true;
      _exists[key] = true;
      _fav[key] = favorite;
    });

    try {
      final prepared = await VinylAddService.prepare(
        artist: artistName,
        album: al.title,
        artistId: pickedArtist?.id,
      );

      final res = await VinylAddService.addPrepared(prepared, favorite: favorite);
      await BackupService.autoSaveIfEnabled();

      if (!mounted) return;

      if (!res.ok) {
        // ❌ falló -> revertimos
        setState(() {
          _exists.remove(key);
          _vinylId.remove(key);
          _fav.remove(key);
        });
      } else {
        // ✅ refrescamos id real desde DB
        final row = await VinylDb.instance.findByExact(artista: artistName, album: al.title);
        if (!mounted) return;
        setState(() {
          _vinylId[key] = row?['id'] as int?;
          _exists[key] = row != null;
          _fav[key] = row != null ? ((row['favorite'] ?? 0) == 1) : favorite;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
    } catch (_) {
      if (!mounted) return;
      // revert
      setState(() {
        _exists.remove(key);
        _vinylId.remove(key);
        _fav.remove(key);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error guardando. Intenta de nuevo.')),
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

  Future<void> _toggleWishlistOptimistic(String artistName, AlbumItem al) async {
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
                                        Icons.add_circle_outline,
                                        color: (exists || busy) ? Colors.grey : Colors.black,
                                      ),
                                      tooltip: exists ? 'Ya está en tu lista' : 'Agregar LP',
                                      onPressed: (busy || exists)
                                          ? null
                                          : () => _addAlbumOptimistic(artistName, al, favorite: false),
                                    ),

                                    // 2) ⭐ Favoritos
                                    IconButton(
                                      iconSize: 20,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                                      icon: Icon(
                                        fav ? Icons.star : Icons.star_border,
                                        color: !exists ? Colors.grey : (fav ? Colors.grey : Colors.black),
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
                                        color: (exists || inWish || busy) ? Colors.grey : Colors.black,
                                      ),
                                      tooltip: exists
                                          ? 'Ya está en tu lista de vinilos'
                                          : (inWish ? 'Ya está en tu lista deseos' : 'Agregar a lista deseos'),
                                      onPressed: (busy || exists || inWish)
                                          ? null
                                          : () => _toggleWishlistOptimistic(artistName, al),
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
