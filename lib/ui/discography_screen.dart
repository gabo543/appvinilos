import 'dart:async';

import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
import '../services/backup_service.dart';
import '../services/discography_service.dart';
import '../services/vinyl_add_service.dart';
import '../services/add_defaults_service.dart';
import '../services/price_range_service.dart';
import 'album_tracks_screen.dart';
import 'app_logo.dart';
import '../l10n/app_strings.dart';

class DiscographyScreen extends StatefulWidget {
  DiscographyScreen({super.key});

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
  final FocusNode _artistFocus = FocusNode();
  Timer? _debounce;

  void _clearArtistSearch({bool keepFocus = true}) {
    _debounce?.cancel();
    artistCtrl.clear();

    setState(() {
      searchingArtists = false;
      artistResults = [];
      pickedArtist = null;
      albums = [];
      loadingAlbums = false;
    });
    _lastAutoPickedQuery = '';
    _exists.clear();
    _vinylId.clear();
    _fav.clear();
    _wish.clear();
    _busy.clear();
    _priceByReleaseGroup.clear();
    _priceInFlight.clear();

    if (keepFocus) {
      // Mantener el foco en el TextField para seguir escribiendo.
      FocusScope.of(context).requestFocus(_artistFocus);
    }
  }

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

  // 💶 Precios en lista (discografía)
  bool _showPrices = false;
  final Map<String, PriceRange?> _priceByReleaseGroup = {};
  final Map<String, Future<PriceRange?>?> _priceInFlight = {};

  String _k(String artist, String album) => '${artist.trim()}||${album.trim()}';

  String _priceLabelFor(PriceRange pr) {
    // Formato pedido: "€ A - B".
    // Antes redondeábamos con .round() y en rangos cercanos terminaba igual
    // (ej: 18.4–18.6 => 18–18). Mostramos enteros cuando corresponde, pero
    // usamos 2 decimales si hay fracción.

    String fmt(double v) {
      final r = v.roundToDouble();
      if ((v - r).abs() < 0.005) return r.toInt().toString();
      return v.toStringAsFixed(2);
    }

    final a = fmt(pr.min);
    final b = fmt(pr.max);
    if (a == b) return '€ $a';
    return '€ $a - $b';
  }

  void _ensurePriceLoaded(String artistName, AlbumItem al) {
    if (!_showPrices) return;
    final rgid = al.releaseGroupId.trim();
    if (rgid.isEmpty) return;
    if (_priceByReleaseGroup.containsKey(rgid)) return;
    if (_priceInFlight[rgid] != null) return;

    _priceInFlight[rgid] = PriceRangeService.getRange(
      artist: artistName,
      album: al.title,
      mbid: rgid,
    ).then((pr) {
      _priceByReleaseGroup[rgid] = pr;
      _priceInFlight[rgid] = null;
      if (mounted) setState(() {});
      return pr;
    }).catchError((_) {
      _priceByReleaseGroup[rgid] = null;
      _priceInFlight[rgid] = null;
      if (mounted) setState(() {});
      return null;
    });
  }

  // 🔎 Auto-selección (modo A): si el mejor resultado es claramente superior,
  // entramos directo a la discografía. Si hay duda, mostramos la lista.
  String _lastAutoPickedQuery = '';

  String _normQ(String s) {
    var out = s.toLowerCase().trim();
    const rep = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
      'ñ': 'n',
    };
    rep.forEach((k, v) => out = out.replaceAll(k, v));
    out = out.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    // tolera "the "
    if (out.startsWith('the ')) out = out.substring(4);
    return out;
  }

  bool _shouldAutoPick(String qNorm, List<ArtistHit> hits) {
    if (qNorm.length < 4) return false;
    if (hits.isEmpty) return false;

    final best = hits.first;
    final bestScore = best.score ?? 0;
    final secondScore = hits.length > 1 ? (hits[1].score ?? 0) : 0;

    final nameNorm = _normQ(best.name);
    final exact = nameNorm == qNorm;
    final prefix = nameNorm.startsWith(qNorm);

    final clearLead = (hits.length == 1) || (bestScore - secondScore >= 12);
    final strong = bestScore >= 95;

    return clearLead && (exact || (strong && prefix));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    artistCtrl.dispose();
    _artistFocus.dispose();
    super.dispose();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  void _onArtistTextChanged(String _) {
    _debounce?.cancel();
    final q = artistCtrl.text.trim();
    // Si el usuario cambia el texto, invalidamos la selección anterior.
    if (pickedArtist != null && _normQ(q) != _normQ(pickedArtist!.name)) {
      setState(() {
        pickedArtist = null;
        albums = [];
        loadingAlbums = false;
      });
      _exists.clear();
      _vinylId.clear();
      _fav.clear();
      _wish.clear();
      _busy.clear();
      _priceByReleaseGroup.clear();
      _priceInFlight.clear();
    }
    if (q.isEmpty) {
      setState(() {
        searchingArtists = false;
        artistResults = [];
        pickedArtist = null;
        albums = [];
        loadingAlbums = false;
      });
      _lastAutoPickedQuery = '';
      _exists.clear();
      _vinylId.clear();
      _fav.clear();
      _wish.clear();
      _busy.clear();
      _priceByReleaseGroup.clear();
      _priceInFlight.clear();
      return;
    }

    _debounce = Timer(Duration(milliseconds: 260), () async {
      if (!mounted) return;
      setState(() => searchingArtists = true);
      try {
        final hits = await DiscographyService.searchArtists(q);
        if (!mounted) return;

        final qNorm = _normQ(q);

        // ✅ Modo A: si el 1° es claramente el correcto, entramos directo.
        if (hits.isNotEmpty && _shouldAutoPick(qNorm, hits)) {
          final best = hits.first;
          if (_lastAutoPickedQuery != qNorm && pickedArtist?.id != best.id) {
            _lastAutoPickedQuery = qNorm;
            setState(() {
              searchingArtists = false;
              artistResults = [];
            });
            await _pickArtist(best);
            return;
          }
        }

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
      _priceByReleaseGroup.clear();
      _priceInFlight.clear();
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

    // ✅ Prefill con la última selección del usuario
    try {
      condition = await AddDefaultsService.getLastCondition(fallback: condition);
      format = await AddDefaultsService.getLastFormat(fallback: format);
    } catch (_) {
      // si prefs falla, seguimos con defaults
    }

    final res = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(context.tr('Agregar a tu lista')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: condition,
                decoration: InputDecoration(labelText: context.tr('Condición')),
                items: const [
                  DropdownMenuItem(value: 'M', child: Text(context.tr('M (Mint)'))),
                  DropdownMenuItem(value: 'NM', child: Text(context.tr('NM (Near Mint)'))),
                  DropdownMenuItem(value: 'VG+', child: Text(context.tr('VG+'))),
                  DropdownMenuItem(value: 'VG', child: Text(context.tr('VG'))),
                  DropdownMenuItem(value: 'G', child: Text('G')),
                ],
                onChanged: (v) => condition = v ?? condition,
              ),
              SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: format,
                decoration: InputDecoration(labelText: context.tr('Formato')),
                items: const [
                  DropdownMenuItem(value: 'LP', child: Text(context.tr('LP'))),
                  DropdownMenuItem(value: 'EP', child: Text(context.tr('EP'))),
                  DropdownMenuItem(value: 'Single', child: Text(context.tr('Single'))),
                  DropdownMenuItem(value: '2xLP', child: Text(context.tr('2xLP'))),
                ],
                onChanged: (v) => format = v ?? format,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () { _dismissKeyboard(); Navigator.pop(ctx); }, child: Text(context.tr('Cancelar'))),
            ElevatedButton(
              onPressed: () { _dismissKeyboard(); Navigator.pop(ctx, {'condition': condition, 'format': format}); },
              child: Text(context.tr('Aceptar')),
            ),
          ],
        );
      },
    );

    if (res != null) {
      await AddDefaultsService.saveLast(condition: res['condition'] ?? condition, format: res['format'] ?? format);
    }
    return res;
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
              title: Text(context.tr('Estado (wishlist)')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    value: 'Por comprar',
                    groupValue: picked,
                    title: Text(context.tr('Por comprar')),
                    onChanged: (v) => setStateDialog(() => picked = v ?? picked),
                  ),
                  RadioListTile<String>(
                    value: 'Buscando',
                    groupValue: picked,
                    title: Text(context.tr('Buscando')),
                    onChanged: (v) => setStateDialog(() => picked = v ?? picked),
                  ),
                  RadioListTile<String>(
                    value: 'Comprado',
                    groupValue: picked,
                    title: Text(context.tr('Comprado')),
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
                  child: Text(context.tr('Cancelar')),
                ),
                ElevatedButton(
                  onPressed: () {
                    _dismissKeyboard();
                    Navigator.pop(ctx, picked);
                  },
                  child: Text(context.tr('Aceptar')),
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

    final currentFav = _fav[key] == true;
    final next = !currentFav;

    // Resolver ID (si por algún motivo quedó vacío)
    int id = _vinylId[key] ?? 0;
    if (id <= 0) {
      final row = await VinylDb.instance.findByExact(artista: artistName, album: al.title);
      if (!mounted) return;
      id = _asInt(row?['id']);
      _vinylId[key] = id;
    }
    if (id <= 0) return;

    setState(() {
      _busy[key] = true;
      _fav[key] = next; // UI instantánea
    });

    try {
      // ✅ Ruta estricta por ID (evita que quede “pegado”)
      try {
        await VinylDb.instance.setFavoriteStrictById(id: id, favorite: next);
      } catch (_) {
        // Fallback robusto si el strict falla por algún motivo
        await VinylDb.instance.setFavoriteSafe(
          favorite: next,
          id: id,
          artista: artistName,
          album: al.title,
        );
      }

      // ✅ Confirmar en DB (evita UI desincronizada)
      final row = await VinylDb.instance.findByExact(artista: artistName, album: al.title);
      final dbFav = _asFav(row?['favorite']);
      _vinylId[key] = _asInt(row?['id']);
      _exists[key] = row != null;
      _fav[key] = dbFav;

      if (dbFav != next) {
        throw Exception('Favorito no persistió');
      }

      // Backup NO debe romper favorito
      try {
        await BackupService.autoSaveIfEnabled();
      } catch (_) {}
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
      appBar: AppBar(
        toolbarHeight: kAppBarToolbarHeight,
        leadingWidth: appBarLeadingWidthForLogoBack(logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        leading: appBarLeadingLogoBack(context, logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        title: appBarTitleTextScaled(context.tr('Discografías'), padding: const EdgeInsets.only(left: 8)),
        titleSpacing: 12,
        actions: [
          if ((pickedArtist != null || albums.isNotEmpty) && artistName.trim().isNotEmpty)
            IconButton(
              tooltip: _showPrices ? 'Ocultar precios' : 'Mostrar precios',
              icon: Icon(Icons.euro_symbol),
              onPressed: () {
                setState(() => _showPrices = !_showPrices);
              },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: artistCtrl,
              focusNode: _artistFocus,
              onChanged: (v) {
                // Asegura que el botón X aparezca/desaparezca al tipear.
                setState(() {});
                _onArtistTextChanged(v);
              },
              decoration: InputDecoration(
                labelText: context.tr('Artista'),
                prefixIcon: Icon(Icons.search),
                suffixIcon: artistCtrl.text.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.tr('Limpiar'),
                        icon: Icon(Icons.close),
                        onPressed: () => _clearArtistSearch(),
                      ),
              ),
            ),
            SizedBox(height: 10),
            if (searchingArtists) LinearProgressIndicator(),
            if (artistResults.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  itemCount: artistResults.length,
                  separatorBuilder: (_, __) => Divider(height: 1),
                  itemBuilder: (_, i) {
                    final a = artistResults[i];
                    return ListTile(
                      title: Text(a.name),
                      subtitle: Text((a.country ?? '').trim().isEmpty ? '—' : (a.country ?? '').trim()),
                      trailing: Icon(Icons.chevron_right),
                      onTap: () => _pickArtist(a),
                    );
                  },
                ),
              )
            else
              Expanded(
                child: loadingAlbums
                    ? Center(child: CircularProgressIndicator())
                    : (albums.isEmpty
                        ? Center(child: Text(context.tr('Busca un artista para ver su discografía.')))
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

                              // 💶 Precios (lazy): solo si el usuario activó el icono €
                              if (_showPrices) {
                                _ensurePriceLoaded(artistName, al);
                              }

                              final rgid = al.releaseGroupId.trim();
                              final hasPrice = rgid.isNotEmpty && _priceByReleaseGroup.containsKey(rgid);
                              final pr = rgid.isEmpty ? null : _priceByReleaseGroup[rgid];
                              final priceLabel = !_showPrices
                                  ? null
                                  : (!hasPrice
                                      ? '€ …'
                                      : (pr == null ? '€ —' : _priceLabelFor(pr)));

                              Widget actionItem({
                                required IconData icon,
                                required String label,
                                required VoidCallback? onTap,
                                required bool disabled,
                                required String tooltip,
                              }) {
                                final color = disabled ? Theme.of(context).colorScheme.onSurfaceVariant : null;
                                return Tooltip(
                                  message: tooltip,
                                  child: InkWell(
                                    onTap: disabled ? null : onTap,
                                    borderRadius: BorderRadius.circular(10),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(icon, color: color),
                                          SizedBox(height: 2),
                                          Text(
                                            label,
                                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }

                              return Card(
                                child: Column(
                                  children: [
                                    ListTile(
                                      leading: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.network(
                                          al.cover250,
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Icon(Icons.album, size: 34),
                                          loadingBuilder: (ctx, child, prog) {
                                            if (prog == null) return child;
                                            return SizedBox(
                                              width: 56,
                                              height: 56,
                                              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                            );
                                          },
                                        ),
                                      ),
                                      title: Text(
                                        al.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              AppStrings.labeled(context, 'Año', ((al.year ?? '').trim().isEmpty) ? '—' : (al.year ?? '')),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (priceLabel != null)
                                            Text(
                                              priceLabel,
                                              style: Theme.of(context).textTheme.labelMedium,
                                            ),
                                        ],
                                      ),
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
                                    ),
                                    Divider(height: 1),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Row(
                                        children: [
                                          // 🇨🇱 País del artista (misma línea inferior izquierda)
                                          Expanded(
                                            child: Builder(
                                              builder: (_) {
                                                final c = (pickedArtist?.country ?? '').trim();
                                                if (c.isEmpty) return const SizedBox.shrink();
                                                return Text(
                                                  AppStrings.labeled(context, 'País', c),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                      ),
                                                );
                                              },
                                            ),
                                          ),

                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              actionItem(
                                                icon: addIcon,
                                                label: 'Lista',
                                                tooltip: addDisabled ? 'Ya está en tu lista' : 'Agregar a tu lista',
                                                disabled: addDisabled,
                                                onTap: () async {
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
                                              ),
                                              actionItem(
                                                icon: favIcon,
                                                label: 'Fav',
                                                tooltip: favDisabled
                                                    ? (exists ? 'Cargando...' : 'Primero agrega a tu lista')
                                                    : (fav ? 'Quitar favorito' : 'Marcar favorito'),
                                                disabled: favDisabled,
                                                onTap: () => _toggleFavorite(artistName, al),
                                              ),
                                              actionItem(
                                                icon: wishIcon,
                                                label: 'Deseos',
                                                tooltip: wishDisabled ? 'No disponible' : 'Agregar a deseos',
                                                disabled: wishDisabled,
                                                onTap: () async {
                                                  final st = await _askWishlistStatus();
                                                  if (!mounted || st == null) return;
                                                  await _addWishlist(artistName, al, st);
                                                },
                                              ),
                                              if (busy)
                                                Padding(
                                                  padding: EdgeInsets.only(left: 8),
                                                  child: SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child: CircularProgressIndicator(strokeWidth: 2),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
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