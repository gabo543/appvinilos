import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db/vinyl_db.dart';
import '../services/backup_service.dart';
import '../services/discography_service.dart';
import '../services/vinyl_add_service.dart';
import '../services/add_defaults_service.dart';
import '../services/store_price_service.dart';
import '../utils/normalize.dart';
import 'widgets/app_cover_image.dart';
import 'album_tracks_screen.dart';
import 'app_logo.dart';
import 'explore_screen.dart';
import 'similar_artists_screen.dart';
import 'widgets/app_pager.dart';
import '../l10n/app_strings.dart';

class DiscographyScreen extends StatefulWidget {
  DiscographyScreen({super.key, this.initialArtist});

  final ArtistHit? initialArtist;

  @override
  State<DiscographyScreen> createState() => _DiscographyScreenState();
}

class _DiscographyScreenState extends State<DiscographyScreen> {

  // =============================================
  // ⚡ Performance: paginación REAL en MusicBrainz
  // =============================================
  // MusicBrainz pagina en bloques de 100. Antes descargábamos TODO siempre,
  // lo que hacía lento el cambio de artista. Ahora:
  // - cargamos 1 página para mostrar rápido,
  // - y traemos más páginas solo cuando se necesitan (ej. búsqueda de álbum).
  static const int _mbLimit = 100;
  int _mbOffset = 0;
  int _mbTotal = 0;
  bool _mbHasMore = false;
  bool _mbLoadingMore = false;
  String _mbArtistId = '';
  final Set<String> _mbLoadedIds = <String>{};

  // Búsqueda global de álbum: mientras el usuario escribe, si no encontramos
  // coincidencias en lo cargado, seguimos trayendo páginas automáticamente.
  Timer? _albumDebounce;
  int _albumSearchSeq = 0;
  bool _loadingAlbumGlobalSearch = false;

  // Hidratación (colección/wishlist) en lote para evitar 2 queries por ítem.
  String _lastHydrateSig = '';
  bool _hydrateInFlight = false;

  // 📄 Paginación (20 por página) para la lista de álbumes.
  static const int _pageSize = 20;
  int _albumPage = 1;

  // 🧭 Scroll: al cambiar de página, volver al inicio de la lista.
  final ScrollController _albumsScrollCtrl = ScrollController();

  // 🎵 Conteo de canciones por álbum (lazy) para mostrar "X canciones" en la lista
  // sin recargar toda la UI. Se calcula por release-group y se cachea en memoria.
  final Map<String, int> _trackCountByRg = <String, int>{};
  final Set<String> _trackCountLoading = <String>{};

  void _scrollAlbumsToTop() {
    // Post-frame por si el ListView aún no está montado justo después del setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_albumsScrollCtrl.hasClients) return;
      _albumsScrollCtrl.animateTo(
        0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _changeAlbumPage(int newPage) {
    if (newPage == _albumPage) return;
    setState(() => _albumPage = newPage);
    _scrollAlbumsToTop();
  }

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

  // 💿 Buscador por álbum (filtra la lista de álbumes)
  final TextEditingController albumCtrl = TextEditingController();
  final FocusNode _albumFocus = FocusNode();

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
  // Álbumes resultado del filtro de canción (lista pro: canción -> álbumes).
  List<AlbumItem> _songAlbumResults = <AlbumItem>[];
  // Para el autocompletado pro: por cada recording sugerido, guardamos
  // los álbumes verificados (primera edición) donde aparece.
  final Map<String, List<AlbumItem>> _songAlbumsByRecording = <String, List<AlbumItem>>{};
  final Set<String> _songAlbumsLoading = <String>{};
  String _lastSongQueryNorm = '';
  String _selectedSongRecordingId = '';
  String _selectedSongTitleNorm = '';
  int _songReqSeq = 0;
  final Map<String, Set<String>> _songCache = <String, Set<String>>{};
  // Cache de tracklists por release-group (para no volver a pedirlos al filtrar).
  final Map<String, List<String>> _trackTitlesCache = <String, List<String>>{};
  int _songScanTotal = 0;
  int _songScanDone = 0;

  // Cuando el filtro por canción necesita buscar en páginas no cargadas aún.
  bool _songLoadingMorePages = false;

  void _clearArtistSearch({bool keepFocus = true}) {
    _debounce?.cancel();
    artistCtrl.clear();

    _clearSongFilter(setText: true);
    _clearAlbumFilter(setText: true);

    setState(() {
      searchingArtists = false;
      artistResults = [];
      pickedArtist = null;
      albums = [];
      loadingAlbums = false;
      _albumPage = 1;

      _mbArtistId = '';
      _mbOffset = 0;
      _mbTotal = 0;
      _mbHasMore = false;
      _mbLoadingMore = false;
      _mbLoadedIds.clear();
      _loadingAlbumGlobalSearch = false;
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

  void _clearAlbumFilter({bool setText = false}) {
    if (setText) albumCtrl.clear();
    if (mounted) {
      setState(() {
        _albumPage = 1;
      });
    }
  }

  void _clearSongFilter({bool setText = false}) {
    _songDebounce?.cancel();
    _songSuggestDebounce?.cancel();
    if (setText) songCtrl.clear();
    setState(() {
      searchingSongs = false;
      _songMatchReleaseGroups = <String>{};
      _songAlbumResults = <AlbumItem>[];
      _loadingSongSuggestions = false;
      _songSuggestions = <SongHit>[];
      _songAlbumsByRecording.clear();
      _songAlbumsLoading.clear();
      _albumPage = 1;
      _songScanTotal = 0;
      _songScanDone = 0;
      _songLoadingMorePages = false;
    });
    _lastSongQueryNorm = '';
    _selectedSongRecordingId = '';
    _selectedSongTitleNorm = '';
    _songReqSeq++;
    _songSuggestSeq++;
  }

  Future<Set<String>> _scanLoadedAlbumsForSong(
    String songQueryNorm,
    int mySeq,
  ) async {
    final matches = <String>{};
    final list = albums;
    final total = list.length;
    if (!mounted) return matches;
    setState(() {
      _songScanTotal = total;
      _songScanDone = 0;
    });

    int done = 0;
    int lastUi = 0;

    for (final al in list) {
      if (!mounted) break;
      if (mySeq != _songReqSeq) break; // cancelado
      final rgid = al.releaseGroupId.toString().trim();
      if (rgid.isEmpty) {
        done++;
        if (mounted && (done - lastUi >= 6 || done == total)) {
          lastUi = done;
          setState(() => _songScanDone = done);
        }
        continue;
      }

      // Tracklist cache (primera edición) para evitar falsos positivos por deluxe/bonus.
      var titles = _trackTitlesCache[rgid];
      titles ??= await DiscographyService.getTrackTitlesFromReleaseGroupFirstEdition(rgid);
      _trackTitlesCache[rgid] = titles;

      bool ok = false;
      for (final t in titles) {
        if (_normQ(t).contains(songQueryNorm)) {
          ok = true;
          break;
        }
      }
      if (ok) matches.add(rgid);

      done++;
      if (mounted && (done - lastUi >= 6 || done == total)) {
        lastUi = done;
        setState(() => _songScanDone = done);
      }
    }
    return matches;
  }

  bool _hasAnyLoadedAlbumMatch(Set<String> rgids) {
    if (rgids.isEmpty) return false;
    for (final al in albums) {
      final id = al.releaseGroupId.trim();
      if (id.isNotEmpty && rgids.contains(id)) return true;
    }
    return false;
  }

  /// Cuando el filtro por canción devuelve release-groups que aún no están cargados
  /// (porque la discografía viene paginada), vamos cargando páginas hasta que
  /// aparezca al menos 1 coincidencia o se terminen las páginas.
  Future<void> _ensureSongMatchesAcrossPages(Set<String> rgids, int mySeq) async {
    if (rgids.isEmpty) return;
    if (_hasAnyLoadedAlbumMatch(rgids)) return;
    if (!_mbHasMore) return;

    if (mounted) {
      setState(() {
        _songLoadingMorePages = true;
      });
    }

    while (mounted && mySeq == _songReqSeq && _mbHasMore) {
      await _loadMoreDiscographyPage();
      if (!mounted || mySeq != _songReqSeq) break;
      if (_hasAnyLoadedAlbumMatch(rgids)) break;
    }

    if (mounted && mySeq == _songReqSeq) {
      setState(() {
        _songLoadingMorePages = false;
      });
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

  // 💶 Precios en lista (discografía) - tiendas (iMusic, Muziker)
  // Se activan por álbum (icono € en cada card), no global.
  final Map<String, bool> _priceEnabledByReleaseGroup = {};
  final Map<String, List<StoreOffer>?> _offersByReleaseGroup = {};
  final Map<String, Future<List<StoreOffer>>?> _offersInFlight = {};

  String _k(String artist, String album) => '${artist.trim()}||${album.trim()}';

  String _priceLabelForOffers(List<StoreOffer> offers) {
    // Formato: min - max (solo 2 precios visibles).
    String fmt(double v) {
      final r = v.roundToDouble();
      if ((v - r).abs() < 0.005) return r.toInt().toString();
      return v.toStringAsFixed(2);
    }

    if (offers.isEmpty) return '';
    final sorted = [...offers]..sort((a, b) => a.price.compareTo(b.price));
    final min = sorted.first.price;
    final max = sorted.last.price;
    final a = fmt(min);
    final b = fmt(max);
    if (a == b) return '€ $a';
    return '€ $a - $b';
  }


  Future<void> _openExternalUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('No se pudo abrir el enlace'))),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('No se pudo abrir el enlace'))),
        );
      }
    }
  }

  void _showPriceSources(BuildContext context, List<StoreOffer> offers) {
    if (offers.isEmpty) return;

    // Un solo link por tienda (elige el más barato).
    final Map<String, StoreOffer> byStore = {};
    for (final o in offers) {
      final k = o.store.trim();
      final prev = byStore[k];
      if (prev == null || o.price < prev.price) byStore[k] = o;
    }
    final list = byStore.values.toList()..sort((a, b) => a.store.compareTo(b.store));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.tr('Fuentes de precio'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 10),
                ...list.map((o) {
                  return Card(
                    child: ListTile(
                      title: Text(o.store, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(o.url, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('€${o.price.toStringAsFixed(2)}'.replaceAll('.00', ''), style: const TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(width: 8),
                          const Icon(Icons.open_in_new, size: 18),
                        ],
                      ),
                      onTap: () => _openExternalUrl(context, o.url),
                    ),
                  );
                }).toList(),
                const SizedBox(height: 6),
                Text(
                  context.tr('Los precios pueden cambiar en la tienda.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<StoreOffer>> _fetchOffersForAlbum(
    String artistName,
    AlbumItem al, {
    bool forceRefresh = false,
  }) async {
    final rgid = al.releaseGroupId.trim();
    if (rgid.isEmpty) return const <StoreOffer>[];

    if (!forceRefresh && _offersByReleaseGroup.containsKey(rgid)) {
      return _offersByReleaseGroup[rgid] ?? const <StoreOffer>[];
    }

    final inflight = _offersInFlight[rgid];
    if (!forceRefresh && inflight != null) {
      try {
        return await inflight;
      } catch (_) {
        return const <StoreOffer>[];
      }
    }

    final fut = StorePriceService.fetchOffersByQueryCached(
      artist: artistName,
      album: al.title,
      forceRefresh: forceRefresh,
    ).then((offers) {
      _offersByReleaseGroup[rgid] = offers;
      return offers;
    }).catchError((_) {
      _offersByReleaseGroup[rgid] = const <StoreOffer>[];
      return const <StoreOffer>[];
    }).whenComplete(() {
      _offersInFlight[rgid] = null;
      if (mounted) setState(() {});
    });

    _offersInFlight[rgid] = fut;
    return await fut;
  }

  Future<void> _onEuroPressed(
    String artistName,
    AlbumItem al, {
    bool forceRefresh = false,
  }) async {
    final rgid = al.releaseGroupId.trim();
    if (rgid.isEmpty) return;
    if (artistName.trim().isEmpty) return;

    final enabled = await StorePriceService.getEnabledStoreIds();
    if (enabled.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Precio no encontrado'))),
      );
      return;
    }

    // Marca el álbum como "precio solicitado" para que aparezca el label.
    setState(() {
      _priceEnabledByReleaseGroup[rgid] = true;
    });

    final offers = await _fetchOffersForAlbum(artistName, al, forceRefresh: forceRefresh);
    if (!mounted) return;

    // Si no hay coincidencias en iMusic/Muziker, no mostramos nada y quitamos el label.
    if (offers.isEmpty) {
      setState(() {
        _priceEnabledByReleaseGroup[rgid] = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Precio no encontrado'))),
      );
    }
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
    // Rebuild cuando el campo de álbum gana/pierde foco (para mostrar/ocultar autocompletado).
    _albumFocus.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
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
    _albumDebounce?.cancel();
    _songDebounce?.cancel();
    _songSuggestDebounce?.cancel();
    artistCtrl.dispose();
    albumCtrl.dispose();
    songCtrl.dispose();
    _artistFocus.dispose();
    _albumFocus.dispose();
    _songFocus.dispose();
    _albumsScrollCtrl.dispose();
    super.dispose();
  }

  void _onSongTextChanged(String _) {
    _songDebounce?.cancel();
    _songSuggestDebounce?.cancel();

    final a = pickedArtist;
    if (a == null) return;

    final raw = songCtrl.text.trim();
    final qNorm = _normQ(raw);

    // Si se borra el texto, limpiamos todo.
    if (qNorm.isEmpty) {
      _clearSongFilter(setText: false);
      return;
    }

    // Si el usuario empieza a tipear otra cosa, quitamos el filtro aplicado
    // (pero mantenemos el texto para seguir buscando).
    if (_selectedSongTitleNorm.isNotEmpty && qNorm != _selectedSongTitleNorm) {
      setState(() {
        _selectedSongRecordingId = '';
        _selectedSongTitleNorm = '';
        searchingSongs = false;
        _songAlbumResults = <AlbumItem>[];
        _songMatchReleaseGroups = <String>{};
        _albumPage = 1;
      });
    }

    // Con 1 letra MusicBrainz devuelve demasiados falsos positivos.
    if (qNorm.length < 2) {
      setState(() {
        _loadingSongSuggestions = false;
        _songSuggestions = <SongHit>[];
        _songAlbumsByRecording.clear();
        _songAlbumsLoading.clear();
      });
      return;
    }

    final mySeq = ++_songSuggestSeq;
    setState(() {
      _loadingSongSuggestions = true;
      _songSuggestions = <SongHit>[];
      _songAlbumsByRecording.clear();
      _songAlbumsLoading.clear();
    });

    _songSuggestDebounce = Timer(const Duration(milliseconds: 260), () async {
      if (!mounted || mySeq != _songSuggestSeq) return;
      try {
        final hits = await DiscographyService.searchSongSuggestions(
          artistId: a.id,
          songQuery: raw,
          limit: 8,
        );
        if (!mounted || mySeq != _songSuggestSeq) return;

        setState(() {
          _songSuggestions = hits;
          _loadingSongSuggestions = false;
        });

        // Prefetch de álbumes por sugerencia (verificados por 1ra edición).
        for (final h in hits.take(6)) {
          if (!mounted || mySeq != _songSuggestSeq) return;
          if (_songAlbumsByRecording.containsKey(h.id)) continue;
          setState(() => _songAlbumsLoading.add(h.id));
          try {
            final als = await DiscographyService.albumsForRecordingFirstEditionVerified(
              artistId: a.id,
              recordingId: h.id,
              songTitle: h.title,
              maxAlbums: 8,
            );
            if (!mounted || mySeq != _songSuggestSeq) return;
            setState(() {
              _songAlbumsByRecording[h.id] = als;
              _songAlbumsLoading.remove(h.id);
            });
          } catch (_) {
            if (!mounted || mySeq != _songSuggestSeq) return;
            setState(() {
              _songAlbumsByRecording[h.id] = <AlbumItem>[];
              _songAlbumsLoading.remove(h.id);
            });
          }
        }
      } catch (_) {
        if (!mounted || mySeq != _songSuggestSeq) return;
        setState(() {
          _loadingSongSuggestions = false;
          _songSuggestions = <SongHit>[];
          _songAlbumsByRecording.clear();
          _songAlbumsLoading.clear();
        });
      }
    });

    _lastSongQueryNorm = qNorm;
  }

  Future<void> _runSongSearchImmediate(String raw, {bool full = false}) async {
    final a = pickedArtist;
    if (a == null) return;
    final q = raw.trim();
    final qNorm = _normQ(q);
    if (qNorm.isEmpty) {
      _clearSongFilter(setText: true);
      return;
    }

    // Cancela sugerencias pendientes y aplica filtro "pro":
    // 1) buscar sugerencia de canción (título completo)
    // 2) traer álbumes verificados (primera edición)
    _songDebounce?.cancel();
    _songSuggestDebounce?.cancel();
    final mySeq = ++_songReqSeq;

    if (!mounted) return;
    setState(() {
      searchingSongs = true;
      _songAlbumResults = <AlbumItem>[];
      _songMatchReleaseGroups = <String>{};
      _albumPage = 1;
      _songSuggestions = <SongHit>[];
      _loadingSongSuggestions = false;
    });

    try {
      final hits = await DiscographyService.searchSongSuggestions(
        artistId: a.id,
        songQuery: q,
        limit: 8,
      );
      if (!mounted || mySeq != _songReqSeq) return;
      if (hits.isEmpty) {
        setState(() {
          searchingSongs = false;
          _selectedSongRecordingId = 'text';
          _selectedSongTitleNorm = qNorm;
          _songAlbumResults = <AlbumItem>[];
          _songMatchReleaseGroups = <String>{};
        });
        return;
      }

      // Elegimos la mejor sugerencia y autocompletamos el campo.
      final best = hits.first;
      final title = best.title.trim();
      songCtrl.text = title;
      songCtrl.selection = TextSelection.collapsed(offset: title.length);

      _selectedSongRecordingId = best.id;
      _selectedSongTitleNorm = _normQ(title);

      // Si ya prefeteamos desde el dropdown, reutilizamos.
      List<AlbumItem> items = _songAlbumsByRecording[best.id] ?? <AlbumItem>[];
      if (items.isEmpty) {
        items = await DiscographyService.albumsForRecordingFirstEditionVerified(
          artistId: a.id,
          recordingId: best.id,
          songTitle: best.title,
          maxAlbums: full ? 16 : 10,
        );
      }

      if (!mounted || mySeq != _songReqSeq) return;
      final ids = items.map((e) => e.releaseGroupId.trim()).where((id) => id.isNotEmpty).toSet();

      setState(() {
        searchingSongs = false;
        _songAlbumResults = items;
        _songMatchReleaseGroups = ids;
        _albumPage = 1;
        _songSuggestions = <SongHit>[];
        _loadingSongSuggestions = false;
      });
    } catch (_) {
      if (!mounted || mySeq != _songReqSeq) return;
      setState(() {
        searchingSongs = false;
        _songAlbumResults = <AlbumItem>[];
        _songMatchReleaseGroups = <String>{};
        _selectedSongRecordingId = 'text';
        _selectedSongTitleNorm = qNorm;
      });
    }
  }

  Future<void> _applySongFilterByRecording(SongHit hit) async {
    final a = pickedArtist;
    if (a == null) return;

    // Usamos búsqueda robusta por título + artista, pero priorizando el recordingId
    // seleccionado (más preciso). Esto evita falsos negativos típicos de remasters/live.
    await _applySongFilterByText(
      hit.title,
      preferredRecordingId: hit.id,
      markAsSelected: true,
    );
  }

  Future<void> _applySongFilterByText(
    String songTitle, {
    String? preferredRecordingId,
    bool markAsSelected = false,
    int searchLimit = 50,
    int maxLookups = 12,
    bool allowTracklistScanFallback = true,
  }) async {
    final a = pickedArtist;
    if (a == null) return;

    final raw = songTitle.trim();
    final qNorm = _normQ(raw);
    if (qNorm.isEmpty) {
      _clearSongFilter(setText: true);
      return;
    }

    // Evita filtrar mientras la discografía aún está cargando.
    if (loadingAlbums && albums.isEmpty) {
      _snack('Cargando discografía...');
      return;
    }

    // Activamos la selección lo antes posible para que la UI pueda mostrar
    // progreso/estado mientras llegan resultados.
    if (markAsSelected || _selectedSongRecordingId.isEmpty) {
      _selectedSongRecordingId = (preferredRecordingId ?? 'text');
      _selectedSongTitleNorm = qNorm;
    }

    final mySeq = ++_songReqSeq;
    // Cache key incluye "modo" para no reutilizar resultados livianos
    // (en vivo) cuando el usuario presiona buscar (modo completo).
    final cacheKey = '${a.id}||song:$qNorm||sl:$searchLimit||ml:$maxLookups||fb:${allowTracklistScanFallback ? 1 : 0}';
    final cached = _songCache[cacheKey];
    if (cached != null) {
      if (!mounted) return;

      // (Ya activamos la selección arriba.)

      setState(() {
        searchingSongs = true;
        _songLoadingMorePages = false;
        _songMatchReleaseGroups = cached;
        _albumPage = 1;
        _songScanTotal = 0;
        _songScanDone = 0;
      });

      // Si la discografía está paginada, puede que aún no tengamos cargado
      // el(los) álbum(es) donde aparece la canción. Cargamos páginas hasta que aparezca.
      await _ensureSongMatchesAcrossPages(cached, mySeq);
      if (!mounted) return;
      if (mySeq != _songReqSeq) return;

      setState(() {
        searchingSongs = false;
        _songLoadingMorePages = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      searchingSongs = true;
      _songLoadingMorePages = false;
      _songMatchReleaseGroups = <String>{};
      _albumPage = 1;
      _songScanTotal = 0;
      _songScanDone = 0;
    });

    try {
      // 🔎 Buscamos en MusicBrainz por recording y devolvemos release-groups.
      // Luego la UI filtra *solo* los álbumes que ya están en la discografía cargada.
      // Aumentamos `searchLimit` y `maxLookups` para reducir falsos negativos.
      final idsRaw = await DiscographyService.searchAlbumReleaseGroupsBySongRobust(
        artistId: a.id,
        songQuery: raw,
        preferredRecordingId: preferredRecordingId,
        searchLimit: searchLimit,
        maxLookups: maxLookups,
      );

      // IDs de release-groups (álbumes) donde aparece la canción.
      // OJO: ahora la discografía se carga paginada para ser rápida, así que puede que
      // el(los) álbum(es) estén en páginas aún no cargadas.
      var ids = idsRaw;

      // 🛟 Fallback opcional: si MusicBrainz no devolvió nada, escaneamos tracklists
      // de lo ya cargado. Es más lento, así que lo desactivamos para modo "en vivo".
      if (allowTracklistScanFallback && ids.isEmpty && qNorm.length >= 2) {
        final scanned = await _scanLoadedAlbumsForSong(qNorm, mySeq);
        if (!mounted) return;
        if (mySeq != _songReqSeq) return;
        ids = scanned;
      }

      if (!mounted) return;
      if (mySeq != _songReqSeq) return;

      // (Ya activamos la selección arriba.)

      _songCache[cacheKey] = ids;

      // Aplicamos el filtro (aunque aún no tengamos cargado la página donde cae el álbum).
      setState(() {
        _songMatchReleaseGroups = ids;
      });

      // ✅ Nuevo: si aún no hay coincidencias visibles, vamos cargando páginas hasta que aparezcan.
      await _ensureSongMatchesAcrossPages(ids, mySeq);
      if (!mounted) return;
      if (mySeq != _songReqSeq) return;

      setState(() {
        searchingSongs = false;
        _songLoadingMorePages = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (mySeq != _songReqSeq) return;
      setState(() {
        searchingSongs = false;
        _songLoadingMorePages = false;
        _songMatchReleaseGroups = <String>{};
      });
      if (markAsSelected || _selectedSongRecordingId.isEmpty) {
        _selectedSongRecordingId = (preferredRecordingId ?? 'text');
        _selectedSongTitleNorm = qNorm;
      }
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
      _albumPage = 1;
    });
    FocusScope.of(context).unfocus();

    // Aplicar filtro con el recording id (más preciso) y verificado
    // por tracklist de primera edición.
    _applySongFilterBySuggestion(hit);
  }

  Future<void> _applySongFilterBySuggestion(SongHit hit) async {
    final a = pickedArtist;
    if (a == null) return;

    final mySeq = ++_songReqSeq;
    final title = hit.title.trim();
    final norm = _normQ(title);
    if (norm.isEmpty) return;

    _selectedSongRecordingId = hit.id;
    _selectedSongTitleNorm = norm;

    if (!mounted) return;
    setState(() {
      searchingSongs = true;
      _songAlbumResults = <AlbumItem>[];
      _songMatchReleaseGroups = <String>{};
      _albumPage = 1;
    });

    try {
      List<AlbumItem> items = _songAlbumsByRecording[hit.id] ?? <AlbumItem>[];
      if (items.isEmpty) {
        items = await DiscographyService.albumsForRecordingFirstEditionVerified(
          artistId: a.id,
          recordingId: hit.id,
          songTitle: hit.title,
          maxAlbums: 16,
        );
      }
      if (!mounted || mySeq != _songReqSeq) return;

      final ids = items.map((e) => e.releaseGroupId.trim()).where((id) => id.isNotEmpty).toSet();
      setState(() {
        searchingSongs = false;
        _songAlbumResults = items;
        _songMatchReleaseGroups = ids;
        _albumPage = 1;
      });
    } catch (_) {
      if (!mounted || mySeq != _songReqSeq) return;
      setState(() {
        searchingSongs = false;
        _songAlbumResults = <AlbumItem>[];
        _songMatchReleaseGroups = <String>{};
      });
    }
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

  Widget _highlightAlbumTitle(String text, String query) {
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

  void _onAlbumTextChanged(String _) {
    // Filtro en vivo. Además, si el álbum no está dentro de lo que ya
    // cargamos desde MusicBrainz, vamos trayendo más páginas automáticamente
    // (modo "buscar en todas las páginas").
    if (mounted) setState(() => _albumPage = 1);

    _albumDebounce?.cancel();
    _albumSearchSeq++;
    final mySeq = _albumSearchSeq;

    final qNorm = _normQ(albumCtrl.text.trim());
    if (pickedArtist == null || qNorm.isEmpty) {
      if (mounted) setState(() => _loadingAlbumGlobalSearch = false);
      return;
    }

    _albumDebounce = Timer(const Duration(milliseconds: 260), () async {
      if (!mounted) return;
      if (mySeq != _albumSearchSeq) return;

      bool hasMatch = albums.any((a) => _normQ(a.title).contains(qNorm));
      if (hasMatch || !_mbHasMore) {
        if (mounted) setState(() => _loadingAlbumGlobalSearch = false);
        return;
      }

      if (mounted) setState(() => _loadingAlbumGlobalSearch = true);

      // Mientras no haya match, seguimos trayendo páginas.
      while (mounted && mySeq == _albumSearchSeq) {
        hasMatch = albums.any((a) => _normQ(a.title).contains(qNorm));
        if (hasMatch || !_mbHasMore) break;
        if (_mbLoadingMore) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          continue;
        }
        await _loadMoreDiscographyPage();
        // Si hay otra operación de carga (songs/explore), dejamos respirar.
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      if (mounted && mySeq == _albumSearchSeq) {
        setState(() => _loadingAlbumGlobalSearch = false);
      }
    });
  }

  void _openAlbum(BuildContext context, String artistName, AlbumItem al) {
    if (artistName.trim().isEmpty) return;
    _dismissKeyboard();
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
  }

  void _ensureTrackCountFor(AlbumItem al) {
    final rgid = al.releaseGroupId.trim();
    if (rgid.isEmpty) return;
    if (_trackCountByRg.containsKey(rgid)) return;
    if (_trackCountLoading.contains(rgid)) return;

    // Límite simple de concurrencia: máximo 2 fetches al mismo tiempo.
    if (_trackCountLoading.length >= 2) return;

    _trackCountLoading.add(rgid);
    DiscographyService.getTracksFromReleaseGroup(rgid).then((tracks) {
      if (!mounted) return;
      setState(() {
        _trackCountByRg[rgid] = tracks.length;
        _trackCountLoading.remove(rgid);
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _trackCountByRg[rgid] = 0;
        _trackCountLoading.remove(rgid);
      });
    });
  }

  void _showAlbumActionsSheet(String artistName, AlbumItem al) {
    _dismissKeyboard();
    final key = _k(artistName, al.title);
    final exists = _exists[key] == true;
    final fav = _fav[key] == true;
    final inWish = _wish[key] == true;
    final busy = _busy[key] == true;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: Text(context.tr('Abrir')),
                onTap: () {
                  Navigator.pop(context);
                  _openAlbum(context, artistName, al);
                },
              ),
              ListTile(
                leading: const Icon(Icons.format_list_bulleted),
                title: Text(context.tr('Agregar a tu lista')),
                enabled: !exists && !busy,
                onTap: () async {
                  Navigator.pop(context);
                  final opts = await _askConditionAndFormat(artistName: artistName);
                  if (!mounted || opts == null) return;
                  await _addAlbumOptimistic(
                    artistName: artistName,
                    album: al,
                    condition: opts['condition'] ?? 'VG+',
                    format: opts['format'] ?? 'LP',
                  );
                },
              ),
              ListTile(
                leading: Icon(fav ? Icons.star : Icons.star_border),
                title: Text(fav ? context.tr('Quitar favorito') : context.tr('Marcar favorito')),
                enabled: exists && !busy,
                onTap: () {
                  Navigator.pop(context);
                  _toggleFavorite(artistName, al);
                },
              ),
              ListTile(
                leading: Icon(inWish ? Icons.shopping_cart : Icons.shopping_cart_outlined),
                title: Text(context.tr('Agregar a deseos')),
                enabled: !exists && !inWish && !busy,
                onTap: () async {
                  Navigator.pop(context);
                  final st = await _askWishlistStatus();
                  if (!mounted || st == null) return;
                  await _addWishlist(artistName, al, st);
                },
              ),
              ListTile(
                leading: const Icon(Icons.euro_symbol),
                title: Text(context.tr('Precios')),
                enabled: !busy,
                onTap: () async {
                  Navigator.pop(context);
                  await _onEuroPressed(artistName, al, forceRefresh: true);
                },
              ),
            ],
          ),
        );
      },
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
      _clearAlbumFilter(setText: true);
      setState(() {
        pickedArtist = null;
        albums = [];
        loadingAlbums = false;
        _mbArtistId = '';
        _mbOffset = 0;
        _mbTotal = 0;
        _mbHasMore = false;
        _mbLoadingMore = false;
        _mbLoadedIds.clear();
        _loadingAlbumGlobalSearch = false;
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
      _clearAlbumFilter(setText: true);
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
    _clearAlbumFilter(setText: true);
    setState(() {
      pickedArtist = a;
      artistCtrl.text = a.name;
      artistResults = [];
      albums = [];
      loadingAlbums = true;
      _albumPage = 1;

      // reset MusicBrainz paging
      _mbArtistId = a.id;
      _mbOffset = 0;
      _mbTotal = 0;
      _mbHasMore = false;
      _mbLoadingMore = false;
      _mbLoadedIds.clear();
      _loadingAlbumGlobalSearch = false;
      _albumSearchSeq++;

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
      final page = await DiscographyService.getDiscographyPageByArtistId(
        a.id,
        limit: _mbLimit,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _mbOffset = _mbLimit;
        _mbTotal = page.total;
        _mbHasMore = _mbOffset < _mbTotal;

        // Merge único + orden por año
        final merged = <AlbumItem>[];
        for (final it in page.items) {
          if (_mbLoadedIds.add(it.releaseGroupId)) merged.add(it);
        }
        merged.sort((a, b) {
          final ay = int.tryParse(a.year ?? '') ?? 9999;
          final by = int.tryParse(b.year ?? '') ?? 9999;
          return ay.compareTo(by);
        });
        albums = merged;
        loadingAlbums = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        albums = [];
        loadingAlbums = false;

        _mbOffset = 0;
        _mbTotal = 0;
        _mbHasMore = false;
        _mbLoadingMore = false;
      });
      _snack('Error cargando discografía');
    }
  }

  Future<void> _loadMoreDiscographyPage() async {
    if (!mounted) return;
    if (_mbLoadingMore || !_mbHasMore) return;
    if (_mbArtistId.trim().isEmpty) return;

    setState(() => _mbLoadingMore = true);
    try {
      final page = await DiscographyService.getDiscographyPageByArtistId(
        _mbArtistId,
        limit: _mbLimit,
        offset: _mbOffset,
      );
      if (!mounted) return;

      // Avanza offset siempre (incluso si una página tiene 0 álbumes)
      final nextOffset = _mbOffset + _mbLimit;

      final merged = <AlbumItem>[...albums];
      for (final it in page.items) {
        if (_mbLoadedIds.add(it.releaseGroupId)) merged.add(it);
      }
      merged.sort((a, b) {
        final ay = int.tryParse(a.year ?? '') ?? 9999;
        final by = int.tryParse(b.year ?? '') ?? 9999;
        return ay.compareTo(by);
      });

      setState(() {
        _mbOffset = nextOffset;
        _mbTotal = page.total;
        _mbHasMore = _mbOffset < _mbTotal;
        albums = merged;
      });
    } catch (_) {
      // Si falla, dejamos el botón disponible para reintentar
    } finally {
      if (mounted) setState(() => _mbLoadingMore = false);
    }
  }

  void _scheduleHydrateForVisiblePage(String artistName, List<AlbumItem> items) {
    if (artistName.trim().isEmpty) return;
    if (items.isEmpty) return;

    final sig = '$artistName|${items.map((e) => e.releaseGroupId).join(',')}';
    if (sig == _lastHydrateSig) return;
    _lastHydrateSig = sig;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hydrateBatchForAlbums(artistName, items);
    });
  }

  Future<void> _hydrateBatchForAlbums(String artistName, List<AlbumItem> items) async {
    if (!mounted) return;
    if (_hydrateInFlight) return;
    if (artistName.trim().isEmpty || items.isEmpty) return;

    _hydrateInFlight = true;
    try {
      final titles = items.map((e) => e.title).where((t) => t.trim().isNotEmpty).toList();
      if (titles.isEmpty) return;

      final got = await VinylDb.instance.findManyByExact(artista: artistName, albums: titles);
      final gotWish = await VinylDb.instance.findWishlistManyByExact(artista: artistName, albums: titles);
      if (!mounted) return;

      for (final al in items) {
        final k = _k(artistName, al.title);
        final norm = normalizeKey(al.title);
        final row = got[norm];
        _exists[k] = row != null;
        _vinylId[k] = _asInt(row?['id']);
        _fav[k] = _asFav(row?['favorite']);
        _wish[k] = (gotWish[norm] != null);
      }

      if (mounted) setState(() {});
    } finally {
      _hydrateInFlight = false;
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

  Future<Map<String, String>?> _askConditionAndFormat({required String artistName}) async {
    _dismissKeyboard();
    String condition = 'VG+';
    String format = 'LP';

    // ✅ Precalcula el próximo código de colección para mostrarlo en el diálogo.
    String? nextCode;
    try {
      nextCode = await VinylDb.instance.previewNextCollectionCode(artistName);
    } catch (_) {
      nextCode = null;
    }

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
              if ((nextCode ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      AppStrings.labeled(context, 'ID colección', nextCode!),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
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
    final a = pickedArtist;
    final artistName = a?.name ?? '';

    // Si la pantalla fue abierta con un artista inicial, pero aún no se ha cargado,
    // mostramos un loader corto en vez del UI antiguo.
    if (a == null && widget.initialArtist != null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('Discografías'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // ---------------------------
    // ✅ Vista "Pantalla 2" (mock): álbumes del artista
    // ---------------------------
    if (a != null) {
      final songRaw = songCtrl.text.trim();
      final songNorm = _normQ(songRaw);
      final songFilterActive = (a != null && _selectedSongTitleNorm.isNotEmpty);
      final showUnfilteredWhileSearching = songFilterActive && searchingSongs && _songAlbumResults.isEmpty;

      final songVisibleAlbums = (!songFilterActive || showUnfilteredWhileSearching)
          ? albums
          : _songAlbumResults;

      final albumRaw = albumCtrl.text.trim();
      final albumNorm = _normQ(albumRaw);
      final albumFilterActive = albumNorm.isNotEmpty;

      final visibleAlbums = (!albumFilterActive)
          ? songVisibleAlbums
          : songVisibleAlbums.where((al) => _normQ(al.title).contains(albumNorm)).toList();

      final totalAlbums = visibleAlbums.length;
      final totalPages = (totalAlbums <= 0) ? 1 : ((totalAlbums + _pageSize - 1) ~/ _pageSize);
      final page = _albumPage.clamp(1, totalPages);
      if (page != _albumPage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _albumPage = page);
        });
      }
      final start = (page - 1) * _pageSize;
      final end = (start + _pageSize < totalAlbums) ? (start + _pageSize) : totalAlbums;
      final pageAlbums = (totalAlbums <= 0 || start >= totalAlbums)
          ? const <AlbumItem>[]
          : visibleAlbums.sublist(start, end);

      if (!loadingAlbums) {
        _scheduleHydrateForVisiblePage(artistName, pageAlbums);
      }

      final cc = (a.country ?? '').trim();
      final loaded = albums.length;
      final total = _mbTotal;
      final countText = (total > 0)
          ? '$loaded ${context.tr('de')} $total ${context.tr('álbumes cargados')}'
          : '$loaded ${context.tr('álbumes')}';
      final title = cc.isEmpty ? '$artistName · $countText' : '$artistName · $cc · $countText';

      final theme = Theme.of(context);
      final cs = theme.colorScheme;

      Widget pillButton({
        required String text,
        required VoidCallback? onPressed,
        required bool selected,
      }) {
        final style = selected
            ? ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              )
            : OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              );

        final child = Text(text, style: const TextStyle(fontWeight: FontWeight.w800));
        return selected
            ? ElevatedButton(onPressed: onPressed, style: style, child: child)
            : OutlinedButton(onPressed: onPressed, style: style, child: child);
      }

      return Scaffold(
        appBar: AppBar(
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: pillButton(
                        text: context.tr('Buscar'),
                        selected: true,
                        onPressed: () {},
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: pillButton(
                        text: context.tr('Explorar'),
                        selected: false,
                        onPressed: () {
                          _dismissKeyboard();
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ExploreScreen()),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: pillButton(
                        text: context.tr('Similares'),
                        selected: false,
                        onPressed: () {
                          _dismissKeyboard();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SimilarArtistsScreen(
                                initialArtistName: artistName.isEmpty ? null : artistName,
                                initialArtistId: a.id,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${context.trSmart('Artista seleccionado')}: $artistName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          _dismissKeyboard();
                          Navigator.of(context).maybePop();
                        },
                        icon: const Icon(Icons.edit, size: 18),
                        label: Text(context.tr('Cambiar')),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: albumCtrl,
                  focusNode: _albumFocus,
                  textInputAction: TextInputAction.search,
                  onChanged: (v) {
                    setState(() {});
                    _onAlbumTextChanged(v);
                  },
                  decoration: InputDecoration(
                    hintText: context.tr('Álbum'),
                    prefixIcon: const Icon(Icons.album),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: albumCtrl.text.trim().isEmpty
                        ? null
                        : IconButton(
                            tooltip: context.tr('Limpiar'),
                            icon: const Icon(Icons.close),
                            onPressed: () => _clearAlbumFilter(setText: true),
                          ),
                  ),
                ),
                if (_loadingAlbumGlobalSearch || _mbLoadingMore) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: songCtrl,
                  focusNode: _songFocus,
                  textInputAction: TextInputAction.search,
                  onChanged: (v) {
                    setState(() {});
                    _onSongTextChanged(v);
                  },
                  onSubmitted: (v) {
                    final raw = v.trim();
                    if (raw.isEmpty) {
                      _clearSongFilter(setText: true);
                      return;
                    }
                    FocusScope.of(context).unfocus();
                    _runSongSearchImmediate(raw, full: true);
                  },
                  decoration: InputDecoration(
                    hintText: context.tr('Canción'),
                    prefixIcon: const Icon(Icons.music_note),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: songCtrl.text.trim().isEmpty
                        ? null
                        : IconButton(
                            tooltip: context.tr('Limpiar'),
                            icon: const Icon(Icons.close),
                            onPressed: () => _clearSongFilter(setText: true),
                          ),
                  ),
                ),
                // Mantener el dropdown de sugerencias (si está funcionando) sin forzar
                // que ocupe espacio si el usuario no lo está usando.
                if (_songFocus.hasFocus && songNorm.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outlineVariant),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Builder(
                          builder: (_) {
                            if (_loadingSongSuggestions) {
                              return const Center(child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: CircularProgressIndicator(),
                              ));
                            }
                            if (_songSuggestions.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                child: Text(
                                  (songNorm.length < 2)
                                      ? context.trSmart('Escribe al menos 2 letras...')
                                      : context.trSmart('Sin resultados.'),
                                ),
                              );
                            }
                            final q = songCtrl.text.trim();
                            return ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: _songSuggestions.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final hit = _songSuggestions[i];
                                final loading = _songAlbumsLoading.contains(hit.id);
                                final als = _songAlbumsByRecording[hit.id];
                                String subtitle;
                                if (loading) {
                                  subtitle = context.tr('Buscando álbumes...');
                                } else if (als == null) {
                                  subtitle = '—';
                                } else if (als.isEmpty) {
                                  subtitle = context.trSmart('No aparece en álbumes (1ª edición).');
                                } else {
                                  final parts = als.take(2).map((a) {
                                    final y = (a.year ?? '').trim();
                                    return y.isEmpty ? a.title : '${a.title} ($y)';
                                  }).toList();
                                  subtitle = parts.join(' · ');
                                  if (als.length > 2) subtitle = '$subtitle · +${als.length - 2}';
                                }
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.music_note),
                                  title: _highlightSongTitle(hit.title, q),
                                  subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  onTap: () => _selectSongSuggestion(hit),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
                if (searchingSongs) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (_songScanTotal > 0)
                        ? (_songScanDone / _songScanTotal).clamp(0.0, 1.0)
                        : null,
                  ),
                ],
                const SizedBox(height: 10),
                Expanded(
                  child: Builder(
                    builder: (_) {
                      if (loadingAlbums) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (albums.isEmpty) {
                        return Center(child: Text(context.tr('No hay álbumes.')));
                      }
                      if (songFilterActive && !searchingSongs && visibleAlbums.isEmpty) {
                        return Center(child: Text(context.tr('No encontré esa canción en álbumes.')));
                      }
                      return Column(
                        children: [
                          Expanded(
                            child: ListView.separated(
                              controller: _albumsScrollCtrl,
                              itemCount: pageAlbums.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final al = pageAlbums[i];
                                _ensureTrackCountFor(al);
                                final rgid = al.releaseGroupId.trim();
                                final cnt = rgid.isEmpty ? null : _trackCountByRg[rgid];
                                final year = (al.year ?? '').trim().isEmpty ? '—' : (al.year ?? '').trim();
                                final cntText = (cnt == null) ? '—' : cnt.toString();
                                final sub = '$year · $cntText ${context.tr('Canciones')}';

                                return Card(
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    leading: AppCoverImage(
                                      pathOrUrl: al.cover250,
                                      width: 54,
                                      height: 54,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    title: Text(
                                      al.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w900),
                                    ),
                                    subtitle: Text(sub),
                                    onTap: () => _openAlbum(context, artistName, al),
                                    onLongPress: () => _showAlbumActionsSheet(artistName, al),
                                  ),
                                );
                              },
                            ),
                          ),
                          if (_mbHasMore && !albumFilterActive && !songFilterActive)
                            Padding(
                              padding: const EdgeInsets.only(top: 6, bottom: 4),
                              child: Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: _mbLoadingMore ? null : _loadMoreDiscographyPage,
                                    icon: const Icon(Icons.download),
                                    label: Text(
                                      _mbLoadingMore ? context.tr('Cargando...') : '${context.tr('Cargar más')} (+$_mbLimit)',
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${albums.length} ${context.tr('álbumes')}',
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          AppPager(
                            page: page,
                            totalPages: totalPages,
                            onPrev: () => _changeAlbumPage((page - 1).clamp(1, totalPages)),
                            onNext: () => _changeAlbumPage((page + 1).clamp(1, totalPages)),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Fallback: si se abre sin artista (no debería pasar desde Home), guiamos al usuario.
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Discografías'))),
      body: Center(child: Text(context.tr('Busca un artista para ver su discografía.'))),
    );
  }
}
