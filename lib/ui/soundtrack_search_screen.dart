import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db/vinyl_db.dart';
import '../l10n/app_strings.dart';
import '../services/add_defaults_service.dart';
import '../services/backup_service.dart';
import '../services/discography_service.dart';
import '../services/store_price_service.dart';
import '../services/vinyl_add_service.dart';
import '../utils/normalize.dart';
import 'album_tracks_screen.dart';
import 'app_logo.dart';
import 'widgets/app_cover_image.dart';
import 'widgets/app_state_view.dart';

/// 🎬 Buscar bandas sonoras (Soundtracks) por título.
///
/// Mantiene el flujo actual: al tocar un resultado se abre la ficha
/// (canciones/detalle) y desde ahí puedes agregar a Lista o Deseos.
class SoundtrackSearchScreen extends StatefulWidget {
  const SoundtrackSearchScreen({super.key});

  @override
  State<SoundtrackSearchScreen> createState() => _SoundtrackSearchScreenState();
}

class _SoundtrackSearchScreenState extends State<SoundtrackSearchScreen> {
  final TextEditingController _titleCtrl = TextEditingController();
  final FocusNode _titleFocus = FocusNode();

  Timer? _debounce;
  Timer? _suggestDebounce;
  int _suggestReqSeq = 0;
  bool _suggestLoading = false;
  List<ExploreAlbumHit> _suggestions = <ExploreAlbumHit>[];

  bool _loading = false;
  String? _error;

  int _page = 0;
  static const int _pageSize = 30;
  int _total = 0;
  List<ExploreAlbumHit> _items = <ExploreAlbumHit>[];

  // UI: Cards / Lista (como Discografías)
  bool _useCards = true;

  // Estado (colección / favoritos / deseos) por resultado
  final Map<String, bool> _exists = <String, bool>{};
  final Map<String, bool> _fav = <String, bool>{};
  final Map<String, bool> _wish = <String, bool>{};
  final Map<String, int> _vinylId = <String, int>{};
  final Map<String, bool> _busy = <String, bool>{};

  // Precios por release-group
  final Map<String, bool> _priceEnabledByReleaseGroup = <String, bool>{};
  final Map<String, List<StoreOffer>?> _offersByReleaseGroup = <String, List<StoreOffer>?>{};
  final Map<String, Future<List<StoreOffer>>?> _offersInFlight = <String, Future<List<StoreOffer>>?>{};

  int _hydrateSeq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _suggestDebounce?.cancel();
    _titleCtrl.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  String _k(String artist, String album) => '${artist.trim()}||${album.trim()}';

  int _asInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  bool _asFav(dynamic v) {
    return (v == 1 || v == true || v == '1' || v == 'true' || v == 'TRUE');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.trSmart(msg))),
    );
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        _snack('No se pudo abrir el enlace');
      }
    } catch (_) {
      if (mounted) _snack('No se pudo abrir el enlace');
    }
  }

  void _showPriceSources(List<StoreOffer> offers) {
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
                      onTap: () => _openExternalUrl(o.url),
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

  String _priceLabelForOffers(List<StoreOffer> offers) {
    if (offers.isEmpty) return '';
    final min = offers.map((o) => o.price).reduce((a, b) => a < b ? a : b);
    final txt = min.toStringAsFixed(2).replaceAll('.00', '');
    return '€$txt';
  }

  Future<List<StoreOffer>> _fetchOffersForReleaseGroup(
    String artistName,
    String albumTitle,
    String releaseGroupId, {
    bool forceRefresh = false,
  }) async {
    final rgid = releaseGroupId.trim();
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
      album: albumTitle,
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

  Future<void> _onEuroPressed(ExploreAlbumHit hit, {bool forceRefresh = true}) async {
    final rgid = hit.releaseGroupId.trim();
    if (rgid.isEmpty) return;
    if (hit.artistName.trim().isEmpty) return;

    final enabled = await StorePriceService.getEnabledStoreIds();
    if (enabled.isEmpty) {
      _snack('Activa tiendas en Ajustes');
      return;
    }

    setState(() {
      _priceEnabledByReleaseGroup[rgid] = true;
    });

    final offers = await _fetchOffersForReleaseGroup(
      hit.artistName,
      hit.title,
      rgid,
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;

    if (offers.isEmpty) {
      setState(() {
        _priceEnabledByReleaseGroup[rgid] = false;
      });
      _snack('Precio no encontrado');
      return;
    }

    _showPriceSources(offers);
  }

  Future<void> _hydrateForItems(List<ExploreAlbumHit> items) async {
    final seq = ++_hydrateSeq;

    // Agrupa por artista para reducir queries.
    final Map<String, List<ExploreAlbumHit>> byArtist = <String, List<ExploreAlbumHit>>{};
    for (final h in items) {
      final a = h.artistName.trim();
      if (a.isEmpty) continue;
      (byArtist[a] ??= <ExploreAlbumHit>[]).add(h);
    }

    final Map<String, bool> exists = <String, bool>{};
    final Map<String, bool> fav = <String, bool>{};
    final Map<String, bool> wish = <String, bool>{};
    final Map<String, int> ids = <String, int>{};

    for (final entry in byArtist.entries) {
      final artist = entry.key;
      final hits = entry.value;
      final albums = hits.map((e) => e.title).toList();

      final inVinyls = await VinylDb.instance.findManyByExact(artista: artist, albums: albums);
      final inWish = await VinylDb.instance.findWishlistManyByExact(artista: artist, albums: albums);

      for (final h in hits) {
        final k = _k(artist, h.title);
        final ak = normalizeKey(h.title);
        final v = inVinyls[ak];
        final w = inWish[ak];
        exists[k] = v != null;
        fav[k] = _asFav(v?['favorite']);
        wish[k] = w != null;
        ids[k] = _asInt(v?['id']);
      }
    }

    if (!mounted) return;
    if (seq != _hydrateSeq) return;

    setState(() {
      _exists
        ..clear()
        ..addAll(exists);
      _fav
        ..clear()
        ..addAll(fav);
      _wish
        ..clear()
        ..addAll(wish);
      _vinylId
        ..clear()
        ..addAll(ids);
    });
  }

  Future<Map<String, String>?> _askConditionAndFormat({required String artistName}) async {
    _dismissKeyboard();
    String condition = 'VG+';
    String format = 'LP';

    String? nextCode;
    try {
      nextCode = await VinylDb.instance.previewNextCollectionCode(artistName);
    } catch (_) {
      nextCode = null;
    }

    try {
      condition = await AddDefaultsService.getLastCondition(fallback: condition);
      format = await AddDefaultsService.getLastFormat(fallback: format);
    } catch (_) {}

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
              const SizedBox(height: 12),
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
                Navigator.pop(ctx, {'condition': condition, 'format': format});
              },
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
    required ExploreAlbumHit hit,
    required String condition,
    required String format,
  }) async {
    final key = _k(hit.artistName, hit.title);
    if (_busy[key] == true) return;

    final exists = _exists[key] == true;
    if (exists) {
      _snack('Ya está en tu lista');
      return;
    }

    setState(() {
      _busy[key] = true;
      _exists[key] = true;
    });

    try {
      final p = await VinylAddService.prepare(
        artist: hit.artistName,
        album: hit.title,
        artistId: null,
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

      await _hydrateForItems(_items);
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

  Future<void> _toggleFavorite(ExploreAlbumHit hit) async {
    final key = _k(hit.artistName, hit.title);
    if (_busy[key] == true) return;

    final exists = _exists[key] == true;
    if (!exists) {
      _snack('Primero agrégalo a tu lista');
      return;
    }

    final currentFav = _fav[key] == true;
    final next = !currentFav;

    int id = _vinylId[key] ?? 0;
    if (id <= 0) {
      final row = await VinylDb.instance.findByExact(artista: hit.artistName, album: hit.title);
      if (!mounted) return;
      id = _asInt(row?['id']);
      _vinylId[key] = id;
    }
    if (id <= 0) return;

    setState(() {
      _busy[key] = true;
      _fav[key] = next;
    });

    try {
      try {
        await VinylDb.instance.setFavoriteStrictById(id: id, favorite: next);
      } catch (_) {
        await VinylDb.instance.setFavoriteSafe(
          favorite: next,
          id: id,
          artista: hit.artistName,
          album: hit.title,
        );
      }

      final row = await VinylDb.instance.findByExact(artista: hit.artistName, album: hit.title);
      final dbFav = _asFav(row?['favorite']);
      if (!mounted) return;
      setState(() {
        _fav[key] = dbFav;
        _vinylId[key] = _asInt(row?['id']);
        _exists[key] = row != null;
      });

      await BackupService.autoSaveIfEnabled();
    } finally {
      if (!mounted) return;
      setState(() => _busy[key] = false);
    }
  }

  Future<void> _addWishlist(ExploreAlbumHit hit, String status) async {
    final key = _k(hit.artistName, hit.title);
    if (_busy[key] == true) return;

    final exists = _exists[key] == true;
    final inWish = _wish[key] == true;
    if (exists || inWish) return;

    setState(() {
      _busy[key] = true;
      _wish[key] = true;
    });

    try {
      await VinylDb.instance.addToWishlist(
        artista: hit.artistName,
        album: hit.title,
        year: hit.year,
        cover250: hit.cover250,
        cover500: hit.cover500,
        artistId: null,
        status: status,
      );
      await BackupService.autoSaveIfEnabled();
      _snack('Agregado a deseos ✅');
    } catch (_) {
      if (!mounted) return;
      setState(() => _wish[key] = false);
      _snack('Error agregando a deseos');
    } finally {
      if (!mounted) return;
      setState(() => _busy[key] = false);
    }
  }

  void _onChanged(String _) {
    // Refresca sufijo (X) del input
    if (mounted) setState(() {});

    final qNow = _titleCtrl.text.trim();

    // Autocompletado (desde 1 letra)
    _suggestDebounce?.cancel();
    if (qNow.isEmpty) {
      if (mounted) {
        setState(() {
          _suggestions = <ExploreAlbumHit>[];
          _suggestLoading = false;
        });
      }
    } else {
      // Para 1 letra usamos un debounce un poco mayor para evitar disparar mientras el usuario sigue escribiendo.
      final ms = (qNow.length <= 1) ? 520 : 360;
      _suggestDebounce = Timer(Duration(milliseconds: ms), () {
        if (!mounted) return;
        _runSuggestions();
      });
    }

    // Mantiene el comportamiento actual: búsqueda automática desde 3 letras.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 520), () {
      if (!mounted) return;
      final q = _titleCtrl.text.trim();
      if (q.length < 3) return;
      _runSearch(resetPage: true);
    });
  }

  Future<void> _runSuggestions() async {
    final q = _titleCtrl.text.trim();
    if (q.isEmpty) return;

    final mySeq = ++_suggestReqSeq;

    setState(() {
      _suggestLoading = true;
    });

    try {
      final list = await DiscographyService.autocompleteSoundtracks(
        title: q,
        limit: 10,
      );
      if (!mounted) return;
      if (mySeq != _suggestReqSeq) return;
      setState(() {
        _suggestions = list;
      });
    } catch (_) {
      if (!mounted) return;
      if (mySeq != _suggestReqSeq) return;
      setState(() {
        _suggestions = <ExploreAlbumHit>[];
      });
    } finally {
      if (!mounted) return;
      if (mySeq != _suggestReqSeq) return;
      setState(() {
        _suggestLoading = false;
      });
    }
  }

  Future<void> _runSearch({bool resetPage = false}) async {
    final q = _titleCtrl.text.trim();
    if (q.isEmpty) {
      setState(() {
        _error = context.tr('Escribe un título para buscar.');
        _items = <ExploreAlbumHit>[];
        _total = 0;
        _page = 0;
      });
      return;
    }

    if (resetPage) _page = 0;
    final offset = _page * _pageSize;

    setState(() {
      _loading = true;
      _error = null;
      // Oculta sugerencias mientras se muestran resultados.
      _suggestReqSeq++;
      _suggestions = <ExploreAlbumHit>[];
      _suggestLoading = false;
    });

    try {
      final page = await DiscographyService.searchSoundtracksByTitle(
        title: q,
        limit: _pageSize,
        offset: offset,
      );
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        // Limpia caches por lista nueva (se vuelven a hidratar).
        _exists.clear();
        _fav.clear();
        _wish.clear();
        _vinylId.clear();
        _busy.clear();
      });

      // Hidrata (colección/fav/deseos) en segundo plano.
      unawaited(_hydrateForItems(page.items));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.tr('No se pudo buscar en MusicBrainz. Intenta de nuevo.');
        _items = <ExploreAlbumHit>[];
        _total = 0;
      });
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _clear() {
    _debounce?.cancel();
    _suggestDebounce?.cancel();
    _suggestReqSeq++;
    setState(() {
      _titleCtrl.clear();
      _items = <ExploreAlbumHit>[];
      _suggestions = <ExploreAlbumHit>[];
      _suggestLoading = false;
      _total = 0;
      _page = 0;
      _error = null;

      _exists.clear();
      _fav.clear();
      _wish.clear();
      _vinylId.clear();
      _busy.clear();
      _priceEnabledByReleaseGroup.clear();
      _offersByReleaseGroup.clear();
      _offersInFlight.clear();
    });
    _titleFocus.requestFocus();
  }

  Widget _suggestionsView(ThemeData t) {
    final q = _titleCtrl.text.trim();
    // Autocompletado desde 1 letra (las sugerencias se muestran solo con foco).
    final show = _titleFocus.hasFocus && q.length >= 1 && (_suggestLoading || _suggestions.isNotEmpty);
    if (!show) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.colorScheme.outlineVariant.withOpacity(0.6)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  Text(
                    context.tr('Sugerencias'),
                    style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const Spacer(),
                  if (_suggestLoading)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ),
            if (_suggestions.isEmpty && !_suggestLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.tr('Sin sugerencias.'),
                    style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final hit = _suggestions[i];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      leading: const Icon(Icons.local_movies_outlined),
                      title: Text(
                        hit.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        '${hit.artistName}${hit.year != null ? ' · ${hit.year}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openDetails(hit),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openDetails(ExploreAlbumHit hit) {
    _dismissKeyboard();

    final album = AlbumItem(
      releaseGroupId: hit.releaseGroupId,
      title: hit.title,
      year: hit.year,
      cover250: hit.cover250,
      cover500: hit.cover500,
      primaryType: 'album',
      secondaryTypes: const ['soundtrack'],
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumTracksScreen(
          album: album,
          artistName: hit.artistName,
          artistId: null,
        ),
      ),
    );
  }

  Widget _buildResultItem(BuildContext ctx, ExploreAlbumHit hit) {
    final t = Theme.of(ctx);
    final cs = t.colorScheme;

    final key = _k(hit.artistName, hit.title);
    final exists = _exists[key] == true;
    final fav = _fav[key] == true;
    final inWish = _wish[key] == true;
    final busy = _busy[key] == true;

    final addDisabled = exists || busy;
    final wishDisabled = exists || inWish || busy;
    final favDisabled = (!exists) || busy;

    final rgid = hit.releaseGroupId.trim();
    final priceEnabled = rgid.isNotEmpty && (_priceEnabledByReleaseGroup[rgid] ?? false);
    final priceDisabled = rgid.isEmpty || hit.artistName.trim().isEmpty;
    if (priceEnabled) {
      _fetchOffersForReleaseGroup(hit.artistName, hit.title, rgid, forceRefresh: false);
    }

    final hasOffers = rgid.isNotEmpty && _offersByReleaseGroup.containsKey(rgid);
    final offers = rgid.isEmpty ? null : _offersByReleaseGroup[rgid];
    final String? priceLabel = !priceEnabled
        ? null
        : (!hasOffers ? '€ …' : (_priceLabelForOffers(offers ?? const []).isEmpty ? null : _priceLabelForOffers(offers ?? const [])));

    Color? iconColor({required bool disabled, bool active = false}) {
      if (disabled) return cs.onSurfaceVariant;
      if (active) return cs.primary;
      return null;
    }

    Widget actionItem({
      required IconData icon,
      required String label,
      required VoidCallback? onTap,
      required bool disabled,
      required String tooltip,
      bool active = false,
    }) {
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
                Icon(icon, color: iconColor(disabled: disabled, active: active)),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: t.textTheme.labelSmall?.copyWith(color: iconColor(disabled: disabled, active: active)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final cover = (hit.cover500.trim().isNotEmpty) ? hit.cover500 : hit.cover250;
    final coverSize = _useCards ? 56.0 : 46.0;

    return Card(
      child: Column(
        children: [
          ListTile(
            onTap: () => _openDetails(hit),
            leading: AppCoverImage(
              pathOrUrl: cover,
              width: coverSize,
              height: coverSize,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(10),
            ),
            title: Text(
              hit.title,
              maxLines: _useCards ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  '${hit.artistName}${hit.year != null ? ' · ${hit.year}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (priceLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      priceLabel,
                      style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
              ],
            ),
            trailing: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                actionItem(
                  icon: Icons.format_list_bulleted,
                  label: context.tr('Lista'),
                  tooltip: context.tr('Agregar a tu lista'),
                  disabled: addDisabled,
                  onTap: () async {
                    final opts = await _askConditionAndFormat(artistName: hit.artistName);
                    if (opts == null) return;
                    await _addAlbumOptimistic(
                      hit: hit,
                      condition: opts['condition'] ?? 'VG+',
                      format: opts['format'] ?? 'LP',
                    );
                  },
                ),
                actionItem(
                  icon: fav ? Icons.star : Icons.star_border,
                  label: context.tr('Fav'),
                  tooltip: context.tr('Favorito'),
                  disabled: favDisabled,
                  active: fav,
                  onTap: () => _toggleFavorite(hit),
                ),
                actionItem(
                  icon: inWish ? Icons.shopping_cart : Icons.shopping_cart_outlined,
                  label: context.tr('Deseos'),
                  tooltip: context.tr('Agregar a deseos'),
                  disabled: wishDisabled,
                  active: inWish,
                  onTap: () async {
                    final status = await _askWishlistStatus();
                    if (status == null) return;
                    await _addWishlist(hit, status);
                  },
                ),
                actionItem(
                  icon: Icons.euro,
                  label: '€',
                  tooltip: context.tr('Precios'),
                  disabled: priceDisabled,
                  active: priceEnabled,
                  onTap: () => _onEuroPressed(hit, forceRefresh: true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pager() {
    if (_total <= _pageSize) return const SizedBox.shrink();
    final pages = (_total / _pageSize).ceil();
    final canPrev = _page > 0;
    final canNext = _page < pages - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: canPrev
                ? () {
                    setState(() => _page--);
                    _runSearch();
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
            label: Text(context.tr('Anterior')),
          ),
          Text(
            '${_page + 1} / $pages',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          TextButton.icon(
            onPressed: canNext
                ? () {
                    setState(() => _page++);
                    _runSearch();
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
            label: Text(context.tr('Siguiente')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kAppBarToolbarHeight,
        leadingWidth: appBarLeadingWidthForLogoBack(logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        leading: appBarLeadingLogoBack(context, logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        title: appBarTitleTextScaled(context.trSmart('Soundtracks'), padding: const EdgeInsets.only(left: 8)),
        titleSpacing: 12,
        actions: const <Widget>[],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _titleCtrl,
                    focusNode: _titleFocus,
                    textInputAction: TextInputAction.search,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _runSearch(resetPage: true),
                    decoration: InputDecoration(
                      hintText: context.trSmart('Ej: Interstellar, Dune, The Last of Us'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _titleCtrl.text.trim().isEmpty
                          ? null
                          : IconButton(
                              tooltip: context.tr('Limpiar'),
                              icon: const Icon(Icons.close),
                              onPressed: _clear,
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: context.tr('Buscar'),
                  icon: const Icon(Icons.search),
                  onPressed: () => _runSearch(resetPage: true),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (_loading)
              const LinearProgressIndicator(minHeight: 2),
            if (!_loading)
              const SizedBox(height: 2),

            // Autocompletado: aparece desde 2 letras (solo mientras el usuario escribe).
            _suggestionsView(t),

            if (_error != null)
              Expanded(
                child: AppStateView(
                  icon: Icons.error_outline,
                  title: context.tr('Error'),
                  subtitle: _error!,
                  actionText: context.tr('Buscar'),
                  onAction: () => _runSearch(resetPage: true),
                ),
              )
            else if (!_loading && _items.isEmpty)
              Expanded(
                child: AppStateView(
                  icon: Icons.local_movies_outlined,
                  title: context.trSmart('Soundtracks'),
                  subtitle: context.trSmart('Escribe un título para buscar bandas sonoras. Ej: Interstellar, Dune, GTA.'),
                ),
              )
            else
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                      child: Row(
                        children: [
                          Text(
                            '${context.tr('Resultados')}: ${_total > 0 ? _total : _items.length}',
                            style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const Spacer(),
                          if (_total > _items.length)
                            Text(
                              context.trSmart('Mostrando') + ' ${_items.length}',
                              style: t.textTheme.labelMedium,
                            ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: context.tr('Cuadros'),
                            child: IconButton(
                              onPressed: () => setState(() => _useCards = true),
                              icon: Icon(
                                Icons.grid_view,
                                color: _useCards ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Tooltip(
                            message: context.tr('Lista'),
                            child: IconButton(
                              onPressed: () => setState(() => _useCards = false),
                              icon: Icon(
                                Icons.view_agenda,
                                color: !_useCards ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final hit = _items[i];
                          return _buildResultItem(ctx, hit);
                        },
                      ),
                    ),
                    _pager(),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
