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

  int _asInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  bool _asFav(dynamic v) {
    return (v == 1 || v == true || v == '1' || v == 'true' || v == 'TRUE');
  }


  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

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

  Future<void> _hydrateIfNeeded(String artistName, AlbumItem al, {bool force = false}) async {
    final key = _k(artistName, al.title);
    if (_busy[key] == true) return;
    if (!force && _exists.containsKey(key) && _fav.containsKey(key) && _wish.containsKey(key) && _vinylId.containsKey(key)) {
      // Si el item existe pero aún no tenemos un id válido, rehidratar.
      final ex = _exists[key] == true;
      final id = _vinylId[key] ?? 0;
      if (!(ex && id <= 0)) {
        return;
      }
    }

    _busy[key] = true;
    try {
      final row = await VinylDb.instance.findByExact(artista: artistName, album: al.title);
      _exists[key] = row != null;
      _vinylId[key] = _asInt(row?['id']);
      _fav[key] = _asFav(row?['favorite']);

      final w = await VinylDb.instance.findWishlistByExact(artista: artistName, album: al.title);
      _wish[key] = w != null;
    } finally {
      _busy[key] = false;
      if (mounted) setState(() {});
    }
  }

  Future<Map<String, String>?> _askConditionAndFormat() async {
    _dismissKeyboard();
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
            TextButton(onPressed: () { _dismissKeyboard(); Navigator.pop(ctx); }, child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () { _dismissKeyboard(); Navigator.pop(ctx, {'condition': condition, 'format': format}); },
              child: const Text('Aceptar'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _askWishlistStatus() async {
    _dismissKeyboard();
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
                    value: 'Buscando',
                    groupValue: picked,
                    title: const Text('Buscando'),
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
                  onPressed: () {
                    _dismissKeyboard();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    _dismissKeyboard();
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
      await _hydrateIfNeeded(artistName, album, force: true);
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

    await _hydrateIfNeeded(artistName, al, force: true);

    if (!mounted) return;

    final id = _vinylId[key] ?? 0;
    if (id <= 0) return;

    final currentFav = _fav[key] == true;
    setState(() {
      _busy[key] = true;
      _fav[key] = !currentFav; // instantáneo
    });

    try {
      await VinylDb.instance.setFavoriteSafe(
        id: id,
        artista: artistName,
        album: al.title,
        favorite: !currentFav,
      );
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
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.network(
                                      al.cover250,
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.album, size: 34),
                                      loadingBuilder: (ctx, child, prog) {
                                        if (prog == null) return child;
                                        return const SizedBox(
                                          width: 56,
                                          height: 56,
                                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                        );
                                      },
                                    ),
                                  ),
                                  title: Text(al.title),
                                  subtitle: Text('Año: ${((al.year ?? '').trim().isEmpty) ? '—' : (al.year ?? '')}'),
                                  onTap: () {
                                    if (artistName.trim().isEmpty) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AlbumTracksScreen(
                                          album: al,
                                          artistName: artistName,
                                          artistId: pickedArtist?.id,
                                        ),
                                      ),
                                    );
                                  },
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: addDisabled ? 'Ya está en tu lista' : 'Agregar',
                                        onPressed: addDisabled
                                            ? null
                                            : () async {
                                                _dismissKeyboard();
                                                final opts = await _askConditionAndFormat();
                                                if (!mounted || opts == null) return;
                                                await _addAlbumOptimistic(
                                                  artistName: artistName,
                                                  album: al,
                                                  condition: opts['condition'] ?? 'VG+',
                                                  format: opts['format'] ?? 'LP',
                                                );
                                              },
                                        icon: Icon(addIcon, color: addDisabled ? Colors.grey : null),
                                      ),
                                      IconButton(
                                        tooltip: favDisabled
                                            ? (exists ? 'Cargando...' : 'Primero agrega a tu lista')
                                            : (fav ? 'Quitar favorito' : 'Marcar favorito'),
                                        onPressed: favDisabled ? null : () => _toggleFavorite(artistName, al),
                                        icon: Icon(favIcon, color: favDisabled ? Colors.grey : null),
                                      ),
                                      IconButton(
                                        tooltip: wishDisabled ? 'No disponible' : 'Wishlist',
                                        onPressed: wishDisabled
                                            ? null
                                            : () async {
                                                final st = await _askWishlistStatus();
                                                if (!mounted || st == null) return;
                                                await _addWishlist(artistName, al, st);
                                              },
                                        icon: Icon(wishIcon, color: wishDisabled ? Colors.grey : null),
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
