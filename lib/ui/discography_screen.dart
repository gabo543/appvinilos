import 'dart:async';

import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
import '../services/backup_service.dart';
import '../services/discography_service.dart';
import '../services/vinyl_add_service.dart';
import 'vinyl_detail_sheet.dart';

class DiscographyScreen extends StatefulWidget {
  const DiscographyScreen({super.key});

  @override
  State<DiscographyScreen> createState() => _DiscographyScreenState();
}

class _DiscographyScreenState extends State<DiscographyScreen> {
  final TextEditingController artistCtrl = TextEditingController();
  Timer? _debounce;

  bool searchingArtists = false;
  List<ArtistHit> artistResults = [];
  ArtistHit? pickedArtist;

  bool loadingAlbums = false;
  List<AlbumItem> albums = [];

  // caches por (artist||album)
  final Map<String, bool> _exists = {};
  final Map<String, int> _vinylId = {};
  final Map<String, bool> _fav = {};
  final Map<String, bool> _wish = {};
  final Map<String, bool> _busy = {};

  String _k(String artist, String album) => '${artist.trim()}||${album.trim()}';

  @override
  void dispose() {
    _debounce?.cancel();
    artistCtrl.dispose();
    super.dispose();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Widget _coverPlaceholder() {
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

  Widget _leadingCover(AlbumItem al) {
    final url = (al.cover250 ?? '').trim();
    if (url.isEmpty) return _coverPlaceholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _coverPlaceholder(),
      ),
    );
  }

  Future<void> _openDetail(String artistName, AlbumItem al) async {
    // intentamos obtener info del artista para enriquecer el sheet
    String country = '';
    String genre = '';
    String bio = '';

    final artistId = pickedArtist?.id ?? '';
    if (artistId.trim().isNotEmpty) {
      try {
        final info = await DiscographyService.getArtistInfoById(artistId.trim(), artistName: artistName);
        country = (info.country ?? '').trim();
        genre = info.genres.isNotEmpty ? info.genres.join(', ') : '';
        bio = (info.bio ?? '').trim();
      } catch (_) {}
    }

    final cover = (al.cover500 ?? '').trim().isNotEmpty
        ? (al.cover500 ?? '').trim()
        : (al.cover250 ?? '').trim();

    final vinylLike = <String, dynamic>{
      // IMPORTANTE: en discografía tenemos release-group id
      'mbid': (al.releaseGroupId ?? '').trim(),
      'coverPath': cover,
      'artista': artistName,
      'album': al.title,
      'year': (al.year ?? '').trim(),
      'genre': genre,
      'country': country,
      'artistBio': bio,
    };

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VinylDetailSheet(vinyl: vinylLike),
    );
  }

  void _onArtistTextChanged(String _) {
    _debounce?.cancel();
    final q = artistCtrl.text.trim();
    if (q.isEmpty) {
      setState(() {
        searchingArtists = false;
        artistResults = [];
        pickedArtist = null;
        albums = [];
        loadingAlbums = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 250), () async {
      setState(() => searchingArtists = true);
      try {
        final hits = await DiscographyService.searchArtists(q);
        if (!mounted) return;
        setState(() {
          artistResults = hits;
          searchingArtists = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          searchingArtists = false;
          artistResults = [];
        });
      }
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

      // limpiezas cache (para evitar estados viejos)
      _exists.clear();
      _vinylId.clear();
      _fav.clear();
      _wish.clear();
      _busy.clear();
    });

    try {
      final list = await DiscographyService.getDiscographyByArtistId(a.id);
      if (!mounted) return;
      setState(() {
        albums = list;
        loadingAlbums = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        albums = [];
        loadingAlbums = false;
      });
      _snack('Error cargando discografía');
    }
  }

  Future<void> _hydrateIfNeeded(String artistName, AlbumItem al) async {
    final key = _k(artistName, al.title);
    if (_busy[key] == true) return;
    if (_exists.containsKey(key) && _fav.containsKey(key) && _wish.containsKey(key) && _vinylId.containsKey(key)) {
      return;
    }

    _busy[key] = true;
    try {
      final row = await VinylDb.instance.findByExact(artista: artistName, album: al.title);
      _exists[key] = row != null;
      _vinylId[key] = (row?['id'] is int) ? row!['id'] as int : 0;
      _fav[key] = (row?['favorite'] ?? 0) == 1;

      final w = await VinylDb.instance.findWishlistByExact(artista: artistName, album: al.title);
      _wish[key] = w != null;
    } finally {
      _busy[key] = false;
      if (mounted) setState(() {});
    }
  }

  Future<Map<String, String>?> _askConditionAndFormat() async {
    // Evita que el buscador (u otro TextField) quede con foco y el teclado
    // aparezca justo después de aceptar/cerrar el diálogo.
    FocusManager.instance.primaryFocus?.unfocus();
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
                  DropdownMenuItem(value: 'VG+', child: Text('VG+')),
                  DropdownMenuItem(value: 'VG', child: Text('VG')),
                  DropdownMenuItem(value: 'G', child: Text('G')),
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
                  DropdownMenuItem(value: '2xLP', child: Text('2xLP')),
                ],
                onChanged: (v) => format = v ?? format,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.pop(ctx);
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.pop(ctx, {'condition': condition, 'format': format});
              },
              child: const Text('Aceptar'),
            ),
          ],
        );
      },
    );
  }

  
Future<String?> _askWishlistStatus() async {
  String picked = 'Por comprar';

  return showDialog<String>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setStateDialog) {
          return AlertDialog(
            title: const Text('Estado (wishlist)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  value: 'Por comprar',
                  groupValue: picked,
                  title: const Text('Por comprar'),
                  onChanged: (v) => setStateDialog(() => picked = v ?? picked),
                ),
                RadioListTile<String>(
                  value: 'En camino',
                  groupValue: picked,
                  title: const Text('En camino'),
                  onChanged: (v) => setStateDialog(() => picked = v ?? picked),
                ),
                RadioListTile<String>(
                  value: 'Comprado',
                  groupValue: picked,
                  title: const Text('Comprado'),
                  onChanged: (v) => setStateDialog(() => picked = v ?? picked),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  // Cierra teclado por si acaso
                  FocusScope.of(ctx).unfocus();
                  Navigator.pop(ctx, picked);
                },
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
    required AlbumItem album,
    required String condition,
    required String format,
  }) async {
    final key = _k(artistName, album.title);
    if (_busy[key] == true) return;

    // Si ya existe, no permitir desmarcar.
    final exists = _exists[key] == true;
    if (exists) {
      _snack('Ya está en tu lista');
      return;
    }

    setState(() {
      _busy[key] = true;
      _exists[key] = true; // optimista para deshabilitar botón
    });

    try {
      final p = await VinylAddService.prepare(
        artist: artistName,
        album: album.title,
        artistId: pickedArtist?.id,
      );

      final res = await VinylAddService.addPrepared(
        p,
        favorite: false,
        condition: condition,
        format: format,
      );

      if (!res.ok) {
        if (!mounted) return;
        setState(() => _exists[key] = false);
        _snack(res.message);
        return;
      }

      // refrescar cache real
      await _hydrateIfNeeded(artistName, album);
      await BackupService.autoSaveIfEnabled();
      _snack('Agregado ✅');
    } catch (_) {
      if (!mounted) return;
      setState(() => _exists[key] = false);
      _snack('Error agregando');
    } finally {
      if (!mounted) return;
      setState(() => _busy[key] = false);
    }
  }

  Future<void> _toggleFavorite(String artistName, AlbumItem al) async {
    final key = _k(artistName, al.title);
    if (_busy[key] == true) return;

    final exists = _exists[key] == true;
    if (!exists) {
      _snack('Primero agrégalo a tu lista');
      return;
    }

    await _hydrateIfNeeded(artistName, al);
    final id = _vinylId[key] ?? 0;
    if (id <= 0) return;

    final currentFav = _fav[key] == true;
    setState(() {
      _busy[key] = true;
      _fav[key] = !currentFav; // instantáneo
    });

    try {
      await VinylDb.instance.setFavorite(id: id, favorite: !currentFav);
      await BackupService.autoSaveIfEnabled();
    } catch (_) {
      if (!mounted) return;
      setState(() => _fav[key] = currentFav);
      _snack('Error actualizando favorito');
    } finally {
      if (!mounted) return;
      setState(() => _busy[key] = false);
    }
  }

  Future<void> _addWishlist(String artistName, AlbumItem al, String status) async {
    final key = _k(artistName, al.title);
    if (_busy[key] == true) return;

    final exists = _exists[key] == true;
    if (exists) {
      // si ya existe en colección, wishlist debe quedar deshabilitado
      _snack('Ya está en tu lista');
      return;
    }

    final inWish = _wish[key] == true;
    if (inWish) {
      _snack('Ya está en wishlist');
      return;
    }

    setState(() {
      _busy[key] = true;
      _wish[key] = true; // optimista
    });

    try {
      // VinylDb no tiene insertWishlist; el método real es addToWishlist
      await VinylDb.instance.addToWishlist(
        artista: artistName,
        album: al.title,
        year: al.year,
        cover250: al.cover250,
        cover500: al.cover500,
        artistId: pickedArtist?.id,
        status: status,
      );
      await BackupService.autoSaveIfEnabled();
      _snack('Agregado a wishlist');
    } catch (_) {
      if (!mounted) return;
      setState(() => _wish[key] = false);
      _snack('Error agregando a wishlist');
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
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: artistCtrl,
              onChanged: _onArtistTextChanged,
              decoration: const InputDecoration(
                labelText: 'Artista',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 10),
            if (searchingArtists) const LinearProgressIndicator(),
            if (artistResults.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  itemCount: artistResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final a = artistResults[i];
                    return ListTile(
                      title: Text(a.name),
                      subtitle: Text((a.country ?? '').trim().isEmpty ? '—' : (a.country ?? '').trim()),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _pickArtist(a),
                    );
                  },
                ),
              )
            else
              Expanded(
                child: loadingAlbums
                    ? const Center(child: CircularProgressIndicator())
                    : (albums.isEmpty
                        ? const Center(child: Text('Busca un artista para ver su discografía.'))
                        : ListView.builder(
                            itemCount: albums.length,
                            itemBuilder: (_, i) {
                              final al = albums[i];
                              final key = _k(artistName, al.title);

                              if (artistName.isNotEmpty && !_exists.containsKey(key) && _busy[key] != true) {
                                _hydrateIfNeeded(artistName, al);
                              }

                              final exists = _exists[key] == true;
                              final fav = _fav[key] == true;
                              final inWish = _wish[key] == true;
                              final busy = _busy[key] == true;

                              final addDisabled = exists || busy;
                              final wishDisabled = exists || inWish || busy;
                              final favDisabled = (!exists) || busy;

                              // iconos: contorno blanco + relleno gris cuando activo
                              IconData addIcon = Icons.format_list_bulleted;
                              IconData favIcon = fav ? Icons.star : Icons.star_border;
                              IconData wishIcon = inWish ? Icons.shopping_cart : Icons.shopping_cart_outlined;

                              return Card(
                                child: ListTile(
                                  onTap: () => _openDetail(artistName, al),
                                  leading: _leadingCover(al),
                                  title: Text(al.title),
                                  subtitle: Text('Año: ${((al.year ?? '').trim().isEmpty) ? '—' : (al.year ?? '')}'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: addDisabled ? 'Ya está en tu lista' : 'Agregar',
                                        onPressed: addDisabled
                                            ? null
                                            : () async {
                                              FocusManager.instance.primaryFocus?.unfocus();
                                                final opts = await _askConditionAndFormat();
                                              FocusManager.instance.primaryFocus?.unfocus();
                                              if (!mounted || opts == null) return;
                                                await _addAlbumOptimistic(
                                                  artistName: artistName,
                                                  album: al,
                                                  condition: opts['condition'] ?? 'VG+',
                                                  format: opts['format'] ?? 'LP',
                                                );
                                              },
                                        icon: Icon(addIcon, color: addDisabled ? Colors.grey : Colors.white),
                                      ),
                                      IconButton(
                                        tooltip: favDisabled
                                            ? (exists ? 'Cargando...' : 'Primero agrega a tu lista')
                                            : (fav ? 'Quitar favorito' : 'Marcar favorito'),
                                        onPressed: favDisabled ? null : () => _toggleFavorite(artistName, al),
                                        icon: Icon(favIcon, color: favDisabled ? Colors.grey : Colors.white),
                                      ),
                                      IconButton(
                                        tooltip: wishDisabled ? 'No disponible' : 'Wishlist',
                                        onPressed: wishDisabled
                                            ? null
                                            : () async {
                                                FocusManager.instance.primaryFocus?.unfocus();
                                                final st = await _askWishlistStatus();
                                              FocusManager.instance.primaryFocus?.unfocus();
                                              if (!mounted || st == null) return;
                                                await _addWishlist(artistName, al, st);
                                              },
                                        icon: Icon(wishIcon, color: wishDisabled ? Colors.grey : Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          )),
              ),
          ],
        ),
      ),
    );
  }
}
