import 'dart:async';

import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
import '../services/backup_service.dart';
import '../services/discography_service.dart';
import '../services/vinyl_add_service.dart';
import '../services/add_defaults_service.dart';
import '../services/store_price_service.dart';
import 'widgets/app_cover_image.dart';
import 'album_tracks_screen.dart';
import 'app_logo.dart';
import 'explore_screen.dart';
import 'similar_artists_screen.dart';
import '../l10n/app_strings.dart';

class DiscographyScreen extends StatefulWidget {
  DiscographyScreen({super.key, this.initialArtist});

  final ArtistHit? initialArtist;

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

  // 🎵 Buscador por canción (filtra álbumes)
  final TextEditingController songCtrl = TextEditingController();
  final FocusNode _songFocus = FocusNode();
  Timer? _songDebounce;
  Timer? _songSuggestDebounce;
  bool _loadingSongSuggestions = false;
  List<SongHit> _songSuggestions = <SongHit>[];
  int _songSuggestSeq = 0;
  bool searchingSongs = false;
  Set<String> _songMatchReleaseGroups = <String>{};
  String _lastSongQueryNorm = '';
  String _selectedSongRecordingId = '';
  String _selectedSongTitleNorm = '';
  int _songReqSeq = 0;
  final Map<String, Set<String>> _songCache = <String, Set<String>>{};

  void _clearArtistSearch({bool keepFocus = true}) {
    _debounce?.cancel();
    artistCtrl.clear();

    _clearSongFilter(setText: true);

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
    _priceEnabledByReleaseGroup.clear();
    _offersByReleaseGroup.clear();
    _offersInFlight.clear();

    if (keepFocus) {
      // Mantener el foco en el TextField para seguir escribiendo.
      FocusScope.of(context).requestFocus(_artistFocus);
    }
  }

  void _clearSongFilter({bool setText = false}) {
    _songDebounce?.cancel();
    _songSuggestDebounce?.cancel();
    if (setText) songCtrl.clear();
    setState(() {
      searchingSongs = false;
      _songMatchReleaseGroups = <String>{};
      _loadingSongSuggestions = false;
      _songSuggestions = <SongHit>[];
    });
    _lastSongQueryNorm = '';
    _selectedSongRecordingId = '';
    _selectedSongTitleNorm = '';
    _songReqSeq++;
    _songSuggestSeq++;
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

  // 💶 Precios en lista (discografía) - tiendas (iMusic, Muziker, Äx)
  // Se activan por álbum (icono € en cada card), no global.
  final Map<String, bool> _priceEnabledByReleaseGroup = {};
  final Map<String, List<StoreOffer>?> _offersByReleaseGroup = {};
  final Map<String, Future<List<StoreOffer>>?> _offersInFlight = {};

  String _k(String artist, String album) => '${artist.trim()}||${album.trim()}';

  String _priceLabelForOffers(List<StoreOffer> offers) {
    // Formato: mostrar rango mín–máx.
    String fmt(double v) {
      final r = v.roundToDouble();
      if ((v - r).abs() < 0.005) return r.toInt().toString();
      return v.toStringAsFixed(2);
    }

    if (offers.isEmpty) return '€ —';
    final min = offers.first.price;
    final max = offers.last.price;
    final a = fmt(min);
    final b = fmt(max);
    if (a == b) return '€ $a';
    return '€ $a - $b';
  }

  void _ensureOffersLoaded(String artistName, AlbumItem al) {
    final rgid = al.releaseGroupId.trim();
    if (rgid.isEmpty) return;
    if (_offersByReleaseGroup.containsKey(rgid)) return;
    if (_offersInFlight[rgid] != null) return;

    _offersInFlight[rgid] = StorePriceService.fetchOffersByQueryCached(
      artist: artistName,
      album: al.title,
    ).then((offers) {
      _offersByReleaseGroup[rgid] = offers;
      _offersInFlight[rgid] = null;
      if (mounted) setState(() {});
      return offers;
    }).catchError((_) {
      _offersByReleaseGroup[rgid] = const [];
      _offersInFlight[rgid] = null;
      if (mounted) setState(() {});
      return const <StoreOffer>[];
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
  void initState() {
    super.initState();
    // Cierra el dropdown de sugerencias de canciones cuando el campo pierde foco.
    _songFocus.addListener(() {
      if (!mounted) return;
      if (!_songFocus.hasFocus) {
        if (_songSuggestions.isNotEmpty || _loadingSongSuggestions) {
          setState(() {
            _songSuggestions = <SongHit>[];
            _loadingSongSuggestions = false;
          });
        }
      }
    });
    // Si nos pasan un artista inicial (por ejemplo desde 'Similares'), lo cargamos directo.
    if (widget.initialArtist != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pickArtist(widget.initialArtist!);
      });
    }

  }

  @override
  void dispose() {
    _debounce?.cancel();
    _songDebounce?.cancel();
    _songSuggestDebounce?.cancel();
    artistCtrl.dispose();
    songCtrl.dispose();
    _artistFocus.dispose();
    _songFocus.dispose();
    super.dispose();
  }

  void _onSongTextChanged(String _) {
    _songDebounce?.cancel();
    _songSuggestDebounce?.cancel();

    final a = pickedArtist;
    if (a == null) return;

    final raw = songCtrl.text.trim();
    final qNorm = _normQ(raw);

    // Si el usuario empezó a editar después de haber seleccionado una sugerencia,
    // desactivamos el filtro y mostramos todo hasta que vuelva a seleccionar.
    if (_selectedSongRecordingId.isNotEmpty && qNorm != _selectedSongTitleNorm) {
      _songReqSeq++; // invalida requests en vuelo
      _selectedSongRecordingId = '';
      _selectedSongTitleNorm = '';
      if (_songMatchReleaseGroups.isNotEmpty || searchingSongs) {
        setState(() {
          searchingSongs = false;
          _songMatchReleaseGroups = <String>{};
        });
      }
    }

    // -----------------
    // Autocomplete (desde 1 letra)
    // -----------------
    if (qNorm.isEmpty) {
      if (_songSuggestions.isNotEmpty || _loadingSongSuggestions) {
        setState(() {
          _songSuggestions = <SongHit>[];
          _loadingSongSuggestions = false;
        });
      }
    } else {
      final mySuggestSeq = ++_songSuggestSeq;
      // Muestra loading solo si el dropdown está visible.
      if (_songFocus.hasFocus) {
        setState(() => _loadingSongSuggestions = true);
      }
      _songSuggestDebounce = Timer(const Duration(milliseconds: 240), () async {
        if (!mounted) return;
        if (mySuggestSeq != _songSuggestSeq) return;
        if (!_songFocus.hasFocus) return;
        final currentNorm = _normQ(songCtrl.text.trim());
        if (currentNorm != qNorm) return;

        try {
          final hits = await DiscographyService.searchSongSuggestions(
            artistId: a.id,
            songQuery: raw,
            limit: 8,
          );
          if (!mounted) return;
          if (mySuggestSeq != _songSuggestSeq) return;
          if (!_songFocus.hasFocus) return;
          setState(() {
            _songSuggestions = hits;
            _loadingSongSuggestions = false;
          });
        } catch (_) {
          if (!mounted) return;
          if (mySuggestSeq != _songSuggestSeq) return;
          setState(() {
            _songSuggestions = <SongHit>[];
            _loadingSongSuggestions = false;
          });
        }
      });
    }

    // El filtro NO se aplica por texto suelto.
    // Se aplica solo al seleccionar una opción del dropdown.
    _lastSongQueryNorm = qNorm;
  }

  Future<void> _applySongFilterByRecording(SongHit hit) async {
    final a = pickedArtist;
    if (a == null) return;

    final mySeq = ++_songReqSeq;
    final cacheKey = '${a.id}||rid:${hit.id}';
    final cached = _songCache[cacheKey];
    if (cached != null) {
      if (!mounted) return;
      setState(() {
        searchingSongs = false;
        _songMatchReleaseGroups = cached;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      searchingSongs = true;
      _songMatchReleaseGroups = <String>{};
    });

    try {
      final ids = await DiscographyService.getAlbumReleaseGroupsForRecordingId(
        recordingId: hit.id,
      );
      if (!mounted) return;
      if (mySeq != _songReqSeq) return;
      _songCache[cacheKey] = ids;
      setState(() {
        searchingSongs = false;
        _songMatchReleaseGroups = ids;
      });
    } catch (_) {
      if (!mounted) return;
      if (mySeq != _songReqSeq) return;
      setState(() {
        searchingSongs = false;
        _songMatchReleaseGroups = <String>{};
      });
    }
  }

  void _selectSongSuggestion(SongHit hit) {
    final title = hit.title.trim();
    songCtrl.text = title;
    songCtrl.selection = TextSelection.collapsed(offset: title.length);
    _lastSongQueryNorm = _normQ(title);
    _selectedSongRecordingId = hit.id;
    _selectedSongTitleNorm = _normQ(title);

    // Cerrar dropdown + teclado.
    setState(() {
      _songSuggestions = <SongHit>[];
      _loadingSongSuggestions = false;
    });
    FocusScope.of(context).unfocus();

    // Aplicar filtro con el recording id (más preciso).
    _applySongFilterByRecording(hit);
  }

  Widget _highlightSongTitle(String text, String query) {
    final q = query.trim();
    if (q.isEmpty) return Text(text);
    final tl = text.toLowerCase();
    final ql = q.toLowerCase();
    final idx = tl.indexOf(ql);
    if (idx < 0) return Text(text);

    final before = text.substring(0, idx);
    final mid = text.substring(idx, idx + q.length);
    final after = text.substring(idx + q.length);
    final base = Theme.of(context).textTheme.bodyMedium;
    final on = Theme.of(context).colorScheme.onSurface;

    return RichText(
      text: TextSpan(
        style: base?.copyWith(color: on),
        children: [
          TextSpan(text: before),
          TextSpan(text: mid, style: base?.copyWith(color: on, fontWeight: FontWeight.w900)),
          TextSpan(text: after),
        ],
      ),
    );
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.trSmart(t))));
  }

  void _onArtistTextChanged(String _) {
    _debounce?.cancel();
    final q = artistCtrl.text.trim();
    // Si el usuario cambia el texto, invalidamos la selección anterior.
    if (pickedArtist != null && _normQ(q) != _normQ(pickedArtist!.name)) {
      _clearSongFilter(setText: true);
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
      _offersByReleaseGroup.clear();
      _offersInFlight.clear();
    }
    if (q.isEmpty) {
      _clearSongFilter(setText: true);
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
      _offersByReleaseGroup.clear();
      _offersInFlight.clear();
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
    _clearSongFilter(setText: true);
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
      _offersByReleaseGroup.clear();
      _offersInFlight.clear();
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
                items: [
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
                items: [
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

    final songRaw = songCtrl.text.trim();
    final songNorm = _normQ(songRaw);
    final songFilterActive = (pickedArtist != null && _selectedSongRecordingId.isNotEmpty);
    final showUnfilteredWhileSearching = songFilterActive && searchingSongs && _songMatchReleaseGroups.isEmpty;

    final visibleAlbums = (!songFilterActive || showUnfilteredWhileSearching)
        ? albums
        : albums.where((al) {
            final rgid = al.releaseGroupId.trim();
            return rgid.isNotEmpty && _songMatchReleaseGroups.contains(rgid);
          }).toList();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kAppBarToolbarHeight,
        leadingWidth: appBarLeadingWidthForLogoBack(logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        leading: appBarLeadingLogoBack(context, logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        title: appBarTitleTextScaled(context.tr('Discografías'), padding: const EdgeInsets.only(left: 8)),
        titleSpacing: 12,
        actions: [
          IconButton(
            tooltip: context.tr('Buscar'),
            icon: const Icon(Icons.search),
            onPressed: () {
              // Llevar el foco al buscador de artista.
              FocusScope.of(context).requestFocus(_artistFocus);
            },
          ),
          IconButton(
            tooltip: context.tr('Explorar'),
            icon: const Icon(Icons.explore),
            onPressed: () {
              _dismissKeyboard();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExploreScreen()),
              );
            },
          ),
          IconButton(
            tooltip: context.tr('Similares'),
            icon: const Icon(Icons.hub_outlined),
            onPressed: () {
              _dismissKeyboard();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SimilarArtistsScreen()),
              );
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

            // 🎵 Buscador de canción (aparece solo cuando ya hay artista elegido)
            if (pickedArtist != null && artistResults.isEmpty) ...[
              TextField(
                controller: songCtrl,
                focusNode: _songFocus,
                onChanged: (v) {
                  setState(() {});
                  _onSongTextChanged(v);
                },
                decoration: InputDecoration(
                  labelText: context.tr('Canción'),
                  hintText: context.tr('Escribe una canción para filtrar álbumes.'),
                  prefixIcon: Icon(Icons.music_note),
                  suffixIcon: songCtrl.text.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.tr('Limpiar'),
                          icon: Icon(Icons.close),
                          onPressed: () => _clearSongFilter(setText: true),
                        ),
                ),
              ),
              if (_songFocus.hasFocus && songCtrl.text.trim().isNotEmpty && (_loadingSongSuggestions || _songSuggestions.isNotEmpty)) ...[
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _loadingSongSuggestions
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : ListView.separated(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: _songSuggestions.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final hit = _songSuggestions[i];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.music_note),
                                  title: _highlightSongTitle(hit.title, songCtrl.text.trim()),
                                  onTap: () => _selectSongSuggestion(hit),
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ],
              SizedBox(height: 8),
              if (searchingSongs) LinearProgressIndicator(),
              if (songFilterActive && !searchingSongs)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${context.tr('Coinciden')}: ${visibleAlbums.length}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
              SizedBox(height: 6),
            ],

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
                        : (songFilterActive && !searchingSongs && visibleAlbums.isEmpty
                            ? Center(child: Text(context.tr('No encontré esa canción en álbumes.')))
                            : ListView.builder(
                            itemCount: visibleAlbums.length,
                            itemBuilder: (_, i) {
                              final al = visibleAlbums[i];
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

                              // 💶 Precios (lazy): se activan por álbum (icono € en cada card)
                              final rgid = al.releaseGroupId.trim();
                              final priceEnabled = rgid.isNotEmpty && (_priceEnabledByReleaseGroup[rgid] ?? false);
                              final priceDisabled = rgid.isEmpty || artistName.trim().isEmpty;
                              if (priceEnabled) {
                                _ensureOffersLoaded(artistName, al);
                              }

                              final hasOffers = rgid.isNotEmpty && _offersByReleaseGroup.containsKey(rgid);
                              final offers = rgid.isEmpty ? null : _offersByReleaseGroup[rgid];
                              final priceLabel = !priceEnabled
                                  ? null
                                  : (!hasOffers ? '€ …' : _priceLabelForOffers(offers ?? const []));

                              Widget actionItem({
                                required IconData icon,
                                required String label,
                                required VoidCallback? onTap,
                                required bool disabled,
                                required String tooltip,
                                bool active = false,
                              }) {
                                final color = disabled
                                    ? Theme.of(context).colorScheme.onSurfaceVariant
                                    : (active ? Theme.of(context).colorScheme.primary : null);
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
                                      leading: AppCoverImage(
                                        pathOrUrl: al.cover250,
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        borderRadius: BorderRadius.circular(10),
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
                                                label: context.tr('Lista'),
                                                tooltip: addDisabled ? context.tr('Ya está en tu lista') : context.tr('Agregar a tu lista'),
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
                                                label: context.tr('Fav'),
                                                tooltip: favDisabled
                                                    ? (exists ? context.tr('Cargando...') : context.tr('Primero agrega a tu lista'))
                                                    : (fav ? context.tr('Quitar favorito') : context.tr('Marcar favorito')),
                                                disabled: favDisabled,
                                                onTap: () => _toggleFavorite(artistName, al),
                                              ),
                                              actionItem(
                                                icon: wishIcon,
                                                label: context.tr('Deseos'),
                                                tooltip: wishDisabled ? context.tr('No disponible') : context.tr('Agregar a deseos'),
                                                disabled: wishDisabled,
                                                onTap: () async {
                                                  final st = await _askWishlistStatus();
                                                  if (!mounted || st == null) return;
                                                  await _addWishlist(artistName, al, st);
                                                },
                                              ),
                                              actionItem(
                                                icon: Icons.euro_symbol,
                                                label: '€',
                                                tooltip: priceEnabled ? context.tr('Ocultar precio') : context.tr('Ver precio'),
                                                disabled: priceDisabled,
                                                active: priceEnabled,
                                                onTap: () {
                                                  if (rgid.isEmpty) return;
                                                  setState(() {
                                                    final next = !(_priceEnabledByReleaseGroup[rgid] ?? false);
                                                    _priceEnabledByReleaseGroup[rgid] = next;
                                                  });
                                                  if (!priceEnabled) {
                                                    // Al activar, disparar carga.
                                                    _ensureOffersLoaded(artistName, al);
                                                  }
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
                          ))),
              ),
          ],
        ),
      ),
    );
  }
}