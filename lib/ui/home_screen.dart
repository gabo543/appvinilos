import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/vinyl_db.dart';
import '../services/discography_service.dart';
import '../services/metadata_service.dart';
import '../services/vinyl_add_service.dart';
import '../services/add_defaults_service.dart';
import '../services/backup_service.dart';
import '../services/view_mode_service.dart';
import '../services/app_theme_service.dart';
import 'discography_screen.dart';
import 'similar_artists_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';
import 'vinyl_detail_sheet.dart';
import 'wishlist_screen.dart';
import 'app_logo.dart';
import 'home/home_header.dart';
import 'manual_vinyl_entry_screen.dart';
import '../l10n/app_strings.dart';
import 'widgets/app_cover_image.dart';
import 'widgets/app_pager.dart';
import 'liked_tracks_view.dart';

enum Vista { inicio, lista, favoritos, borrar }

/// Sub-vista dentro de "Vinilos".
///
/// - vinilos: listado normal (lista/grid/caratula)
/// - artistas: listado agrupado por artista (país + total)
enum VinylScope { vinilos, artistas, canciones }

enum VinylSortMode { az, yearDesc, recent, code }

/// Fila renderizable para listas con encabezados alfabéticos.
///
/// Se usa en:
/// - Vinilos (cuando se ordena por Artista A–Z)
/// - Sub-vista Artistas (lista tipo “contactos”)
class _AlphaRow {
  final String? header;
  final Map<String, dynamic>? payload;
  const _AlphaRow._({this.header, this.payload});
  const _AlphaRow.header(String h) : this._(header: h);
  const _AlphaRow.item(Map<String, dynamic> p) : this._(payload: p);

  bool get isHeader => header != null;
}

enum _AddVinylMethod { scan, manual }

String vinylSortLabel(VinylSortMode m) {
  switch (m) {
    case VinylSortMode.az:
      return 'A–Z';
    case VinylSortMode.yearDesc:
      return 'Año';
    case VinylSortMode.recent:
      return 'Recientes';
    case VinylSortMode.code:
      return 'Código';
  }
}

class HomeScreen extends StatefulWidget {
  HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Logo tipo “rombo con líneas”, usado como marca en el header.
///
/// Se dibuja con `CustomPaint` para no depender de assets extra y para
/// adaptarse automáticamente al color del tema.
class _DiamondLogoPainter extends CustomPainter {
  final Color color;
  const _DiamondLogoPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final r = s * 0.46;

    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (s * 0.12).clamp(1.2, 2.4)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final diamond = Path()
      ..moveTo(center.dx, center.dy - r)
      ..lineTo(center.dx + r, center.dy)
      ..lineTo(center.dx, center.dy + r)
      ..lineTo(center.dx - r, center.dy)
      ..close();

    canvas.drawPath(diamond, outline);

    // Líneas internas diagonales (3 trazos), estilo “rombo con líneas”.
    final lines = Paint()
      ..color = color.withOpacity(0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (s * 0.10).clamp(1.0, 2.0)
      ..strokeCap = StrokeCap.round;

    // Direcciones normalizadas para diagonales.
    const dir = Offset(1, -1);
    const perp = Offset(1, 1);
    final dirN = dir / dir.distance;
    final perpN = perp / perp.distance;

    for (final t in const [-0.18, 0.0, 0.18]) {
      final shift = perpN * (t * r * 1.10);
      final a = center + shift - dirN * (r * 0.55);
      final b = center + shift + dirN * (r * 0.55);
      canvas.drawLine(a, b, lines);
    }
  }

  @override
  bool shouldRepaint(covariant _DiamondLogoPainter oldDelegate) => oldDelegate.color != color;
}

class _HomeScreenState extends State<HomeScreen> {
  // 🔒 Persistencia UI (última vista / orden) para que al reabrir quede igual.
  static const String _kPrefLastVista = 'ui.lastVista';
  static const String _kPrefSortMode = 'ui.sortMode';
  static const String _kPrefVinylScope = 'ui.vinylScope';

  // Aviso al iniciar: deseos marcados como "Comprado".
  static const String _kPrefPurchasedWishLaterTs = 'ui.purchasedWishLaterTs';
  static const Duration _kPurchasedWishLaterTtl = Duration(hours: 24);
  bool _purchasedWishPromptShown = false;

  SharedPreferences? _prefs;

  // ⭐ Cache local para favoritos (cambio instantáneo)
  final Map<int, bool> _favCache = {};

  // 📄 Paginación (20 por página) en modo lista.
  static const int _pageSize = 20;
  int _pageVinilos = 1;
  int _pageFavoritos = 1;
  int _pageBorrar = 1;

  // 🔎 Filtros + orden (solo para "Vinilos")
  String _filterArtistQ = '';
  String _filterGenreQ = '';
  String _filterCountryQ = '';
  int? _filterYearFrom;
  int? _filterYearTo;
  VinylSortMode _sortMode = VinylSortMode.code;

  bool get _hasAnyFilter =>
      _filterArtistQ.trim().isNotEmpty ||
      _filterGenreQ.trim().isNotEmpty ||
      _filterCountryQ.trim().isNotEmpty ||
      _filterYearFrom != null ||
      _filterYearTo != null;

  // ✅ micro-opt: evitar File.existsSync() en cada build (especialmente en grid)
  final Map<String, bool> _fileExistsCache = {};

  bool _fileExistsCached(String path) {
    final p = path.trim();
    if (p.isEmpty) return false;
    final cached = _fileExistsCache[p];
    if (cached != null) return cached;
    final ok = File(p).existsSync();
    _fileExistsCache[p] = ok;
    return ok;
  }

  Vista vista = Vista.inicio;

  // 🔁 Dentro de "Vinilos": Vinilos | Artistas
  VinylScope _vinylScope = VinylScope.vinilos;
  String? _artistFilterKey;
  String? _artistFilterName;

  // 🗑️ En vista borrar: false = 'Para borrar' (colección), true = 'Papelera' (recuperar/eliminar definitivo)
  bool _borrarPapelera = false;
  VinylViewMode _viewMode = VinylViewMode.list;
  late final VoidCallback _viewModeListener;

  // ✅ Contadores para badges en los botones del inicio
  Future<Map<String, int>>? _homeCountsFuture;
  Map<String, int> _homeCounts = const {'all': 0, 'fav': 0, 'wish': 0};

  // ✅ Cache de la lista completa (evita recargar en cada setState y permite favorito instantáneo)
  late Future<List<Map<String, dynamic>>> _futureAll;

  // ✅ Cache de resumen por artistas (para la sub-vista "Artistas")
  late Future<List<Map<String, dynamic>>> _futureArtists;

  // ✅ Cache de favoritos / papelera (evita recargar en cada setState)
  late Future<List<Map<String, dynamic>>> _futureFav;
  late Future<List<Map<String, dynamic>>> _futureTrash;

  final artistaCtrl = TextEditingController();
  final albumCtrl = TextEditingController();
  final yearCtrl = TextEditingController();

  // ✅ Defaults para Agregar (condición/formato)
  String _addCondition = 'VG+';
  String _addFormat = 'LP';
  bool _addDefaultsLoaded = false;

  // ✅ Focus dedicado para poder abrir el buscador desde Home con un tap.
  final FocusNode _artistFocus = FocusNode();

  // 🔎 Búsqueda local (solo en tu colección) para Vinilos/Favoritos
  bool _localSearchActive = false;
  final TextEditingController _localSearchCtrl = TextEditingController();
  final FocusNode _localSearchFocus = FocusNode();
  Timer? _debounceLocalSearch;
  String _localQuery = '';
  List<String> _artistSuggestions = const [];

  Timer? _debounceArtist;
  bool buscandoArtistas = false;
  List<ArtistHit> sugerenciasArtistas = [];
  ArtistHit? artistaElegido;

  Timer? _debounceAlbum;
  bool buscandoAlbums = false;
  List<AlbumSuggest> sugerenciasAlbums = [];
  AlbumSuggest? albumElegido;

  List<Map<String, dynamic>> resultados = [];
  bool mostrarAgregar = false;

  bool autocompletando = false;
  PreparedVinylAdd? prepared;

  // ----------------- LIMPIEZA BUSCADOR -----------------
  void _cancelarBusqueda() {
    FocusScope.of(context).unfocus();
    _debounceArtist?.cancel();
    _debounceAlbum?.cancel();

    setState(() {
      artistaCtrl.clear();
      albumCtrl.clear();
      yearCtrl.clear();

      buscandoArtistas = false;
      buscandoAlbums = false;
      sugerenciasArtistas = [];
      sugerenciasAlbums = [];

      artistaElegido = null;
      albumElegido = null;

      resultados = [];
      prepared = null;
      mostrarAgregar = false;
      autocompletando = false;
    });
  }

  void _limpiarArtista() {
    FocusScope.of(context).unfocus();
    _debounceArtist?.cancel();
    _debounceAlbum?.cancel();

    setState(() {
      artistaCtrl.clear();
      albumCtrl.clear();
      yearCtrl.clear();

      buscandoArtistas = false;
      buscandoAlbums = false;
      sugerenciasArtistas = [];
      sugerenciasAlbums = [];

      artistaElegido = null;
      albumElegido = null;

      resultados = [];
      prepared = null;
      mostrarAgregar = false;
      autocompletando = false;
    });
  }

  void _limpiarAlbum() {
    FocusScope.of(context).unfocus();
    _debounceAlbum?.cancel();

    setState(() {
      albumCtrl.clear();
      yearCtrl.clear();

      buscandoAlbums = false;
      sugerenciasAlbums = [];

      albumElegido = null;

      resultados = [];
      prepared = null;
      mostrarAgregar = false;
      autocompletando = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadUiPrefs();
    _loadAddDefaults();
    // ✅ Vista (3 modos) instantánea (notifier en memoria)
    _viewMode = ViewModeService.modeNotifier.value;
    _viewModeListener = () {
      if (!mounted) return;
      setState(() => _viewMode = ViewModeService.modeNotifier.value);
    };
    ViewModeService.modeNotifier.addListener(_viewModeListener);
    _refreshHomeCounts();
    _futureAll = VinylDb.instance.getAll();
    _futureArtists = VinylDb.instance.getArtistSummaries();
    _futureFav = VinylDb.instance.getFavorites();
    _futureTrash = VinylDb.instance.getTrash();

    // Aviso: deseos marcados como "Comprado".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePromptPurchasedWishlist();
    });
  }

  Future<void> _loadAddDefaults() async {
    try {
      final c = await AddDefaultsService.getLastCondition(fallback: _addCondition);
      final f = await AddDefaultsService.getLastFormat(fallback: _addFormat);
      if (!mounted) return;
      setState(() {
        _addCondition = c;
        _addFormat = f;
        _addDefaultsLoaded = true;
      });
    } catch (_) {
      _addDefaultsLoaded = true;
    }
  }

  Future<void> _loadUiPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;

      final vistaIdx = p.getInt(_kPrefLastVista);
      final sortIdx = p.getInt(_kPrefSortMode);
      final scopeIdx = p.getInt(_kPrefVinylScope);

      setState(() {
        _prefs = p;

        if (vistaIdx != null && vistaIdx >= 0 && vistaIdx < Vista.values.length) {
          vista = Vista.values[vistaIdx];
        }
        if (sortIdx != null && sortIdx >= 0 && sortIdx < VinylSortMode.values.length) {
          _sortMode = VinylSortMode.values[sortIdx];
        }
        if (scopeIdx != null && scopeIdx >= 0 && scopeIdx < VinylScope.values.length) {
          _vinylScope = VinylScope.values[scopeIdx];
        }
      });
    } catch (_) {
      // Preferimos fallar silencioso: la app funciona igual sin persistencia.
    }
  }

  Future<void> _persistVista(Vista v) async {
    try {
      final p = _prefs ?? await SharedPreferences.getInstance();
      _prefs ??= p;
      await p.setInt(_kPrefLastVista, v.index);
    } catch (_) {}
  }

  Future<void> _persistSortMode(VinylSortMode m) async {
    try {
      final p = _prefs ?? await SharedPreferences.getInstance();
      _prefs ??= p;
      await p.setInt(_kPrefSortMode, m.index);
    } catch (_) {}
  }

  Future<void> _persistVinylScope(VinylScope s) async {
    try {
      final p = _prefs ?? await SharedPreferences.getInstance();
      _prefs ??= p;
      await p.setInt(_kPrefVinylScope, s.index);
    } catch (_) {}
  }

  Future<void> _refreshHomeCounts() async {
    if (!mounted) return;

    // ✅ Cargamos 3 contadores SIN traer listas completas (más rápido y más exacto)
    final fut = Future.wait([
      VinylDb.instance.countAll(),
      VinylDb.instance.countFavorites(),
      VinylDb.instance.countWishlist(),
    ]).then((r) {
      final all = (r[0] as int);
      final fav = (r[1] as int);
      final wish = (r[2] as int);
      return {'all': all, 'fav': fav, 'wish': wish};
    });

    setState(() => _homeCountsFuture = fut);

    try {
      final counts = await fut;
      if (!mounted) return;
      setState(() => _homeCounts = counts);
    } catch (_) {
      // si falla, dejamos los contadores anteriores
    }
  }

  
  // ----------------- AVISO AL INICIAR (DESEOS COMPRADOS) -----------------

  Future<void> _maybePromptPurchasedWishlist() async {
    if (!mounted) return;
    if (_purchasedWishPromptShown) return;
    _purchasedWishPromptShown = true;

    try {
      final p = _prefs ?? await SharedPreferences.getInstance();
      _prefs ??= p;

      final ts = p.getInt(_kPrefPurchasedWishLaterTs) ?? 0;
      if (ts > 0) {
        final dt = DateTime.fromMillisecondsSinceEpoch(ts);
        if (DateTime.now().difference(dt) <= _kPurchasedWishLaterTtl) {
          return;
        }
      }

      final items = await VinylDb.instance.getPurchasedWishlistNotInVinyls(limit: 25);
      if (!mounted) return;
      if (items.isEmpty) return;

      await _showPurchasedWishlistSheet(items);
    } catch (_) {
      // ignore (si falla, no bloquea el inicio)
    }
  }

  Future<void> _showPurchasedWishlistSheet(List<Map<String, dynamic>> items) async {
    if (!mounted) return;

    final preview = items.take(6).toList();
    final extra = items.length - preview.length;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        bool working = false;

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> onAddAll() async {
              if (working) return;
              setModalState(() => working = true);

              final added = await _movePurchasedWishlistToVinyls(items);

              if (!mounted) return;
              Navigator.of(ctx).maybePop();

              if (added > 0) {
                _reloadAllData();
              }

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    added > 0
                        ? '${context.tr('Agregado a vinilos')}: $added'
                        : context.tr('Nada para agregar'),
                  ),
                ),
              );
            }

            Future<void> onLater() async {
              try {
                final p = _prefs ?? await SharedPreferences.getInstance();
                _prefs ??= p;
                await p.setInt(_kPrefPurchasedWishLaterTs, DateTime.now().millisecondsSinceEpoch);
              } catch (_) {}
              if (!mounted) return;
              Navigator.of(ctx).maybePop();
            }

            void onReview() {
              Navigator.of(ctx).maybePop();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WishlistScreen(showOnlyPurchased: true)),
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 14,
                  bottom: 14 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('Tienes vinilos comprados en deseos'),
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.tr('¿Quieres agregarlos a Mis vinilos?'),
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    ...preview.map((w) {
                      final a = (w['artista'] ?? '').toString();
                      final al = (w['album'] ?? '').toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$a — $al',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (extra > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 8),
                        child: Text(
                          '+ $extra ${context.tr('más')}',
                          style: Theme.of(ctx).textTheme.labelMedium,
                        ),
                      ),
                    if (working) const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.library_add),
                            label: Text(context.tr('Agregar todos')),
                            onPressed: working ? null : onAddAll,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: working ? null : onReview,
                            child: Text(context.tr('Revisar')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: working ? null : onLater,
                        child: Text(context.tr('Más tarde')),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<int> _movePurchasedWishlistToVinyls(List<Map<String, dynamic>> items) async {
    final cond = await AddDefaultsService.getLastCondition(fallback: _addCondition);
    final fmt = await AddDefaultsService.getLastFormat(fallback: _addFormat);

    int added = 0;
    for (final w in items) {
      final idAny = w['id'];
      final id = (idAny is int) ? idAny : int.tryParse(idAny?.toString() ?? '');
      if (id == null) continue;

      final artista = (w['artista'] ?? '').toString().trim();
      final album = (w['album'] ?? '').toString().trim();
      if (artista.isEmpty || album.isEmpty) continue;

      final year = (w['year'] ?? '').toString().trim();
      final cover = (w['cover250'] ?? w['cover500'] ?? '').toString().trim();
      final barcode = (w['barcode'] ?? '').toString().trim();
      final status = (w['status'] ?? '').toString().toLowerCase();

      if (!status.contains('comprad')) continue;

      try {
        await VinylDb.instance.insertVinyl(
          artista: artista,
          album: album,
          year: year.isEmpty ? null : year,
          coverPath: cover.isEmpty ? null : cover,
          barcode: barcode.isEmpty ? null : barcode,
          condition: cond,
          format: fmt,
        );

        // En el flujo actual, al agregar a vinilos lo sacamos de deseos.
        await VinylDb.instance.removeWishlistById(id);

        added++;
      } catch (_) {
        // si hay duplicado u otro problema, seguimos con el resto
      }
    }

    try {
      await BackupService.autoSaveIfEnabled();
    } catch (_) {}

    return added;
  }

void _reloadAllData() {
  if (!mounted) return;
  setState(() {
    _favCache.clear();
    _futureAll = VinylDb.instance.getAll();
    _futureArtists = VinylDb.instance.getArtistSummaries();
    _futureFav = VinylDb.instance.getFavorites();
    _futureTrash = VinylDb.instance.getTrash();
    });
  _refreshHomeCounts();
}

Future<void> _loadViewMode() async {
    // Mantenemos por compatibilidad, pero hoy la app usa un notifier.
    final m = await ViewModeService.getMode();
    if (!mounted) return;
    ViewModeService.modeNotifier.value = m;
  }

  // ----------------- NAVEGACIÓN / BUSCADOR LOCAL -----------------
  void _setVista(Vista v) {
    if (!mounted) return;
    setState(() {
      vista = v;

      // Al cambiar de vista, cerramos búsqueda local para evitar estados “pegados”.
      _localSearchActive = false;
      _localSearchCtrl.clear();
      _localQuery = '';
    });
    FocusScope.of(context).unfocus();
    _persistVista(v);
  }

  void _setVinylScope(VinylScope s) {
    if (!mounted) return;
    setState(() {
      _vinylScope = s;
      // Si vuelvo a "Artistas", no tiene sentido mantener un filtro de artista
      // (ya estoy mirando TODOS los artistas).
      if (s == VinylScope.artistas) {
        _artistFilterKey = null;
        _artistFilterName = null;
      }
    });
    _persistVinylScope(s);
  }

  void _toggleLocalSearch() {
    if (!mounted) return;
    setState(() {
      _localSearchActive = !_localSearchActive;
      if (!_localSearchActive) {
        _localSearchCtrl.clear();
        _localQuery = '';
      }
    });

    if (_localSearchActive) {
      Future.microtask(() {
        if (!mounted) return;
        FocusScope.of(context).requestFocus(_localSearchFocus);
      });
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _openAddVinylMenu() async {
    // ✅ Entrada rápida para agregar desde la vista "Vinilos"
    final pick = await showModalBottomSheet<_AddVinylMethod>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final t = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.tr('Agregar vinilo'),
                  style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 8),
                ListTile(
                  leading: Icon(Icons.qr_code_scanner),
                  title: Text(context.tr('Escanear')),
                  subtitle: Text(context.tr('Código, carátula o escuchar una canción.')),
                  onTap: () => Navigator.pop(ctx, _AddVinylMethod.scan),
                ),
                ListTile(
                  leading: Icon(Icons.edit_note_outlined),
                  title: Text(context.tr('Ingresar a mano')),
                  subtitle: Text(context.tr('Escribe artista y álbum (opcional: año y género).')),
                  onTap: () => Navigator.pop(ctx, _AddVinylMethod.manual),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || pick == null) return;

    switch (pick) {
      case _AddVinylMethod.scan:
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ScannerScreen()));
        break;
      case _AddVinylMethod.manual:
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ManualVinylEntryScreen()));
        break;
    }

    if (!mounted) return;
    _reloadAllData();
  }

  void _onLocalSearchChanged(String _) {
    // Rebuild inmediato (para el botón de limpiar en el AppBar),
    // pero filtramos con debounce para no recalcular toda la lista a cada tecla.
    if (mounted) setState(() {});
    _debounceLocalSearch?.cancel();
    _debounceLocalSearch = Timer(Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() {
        _localQuery = _localSearchCtrl.text;
        _resetPagingAll();
      });
    });
  }

  String _norm(String s) {
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
    out = out.replaceAll(RegExp(r'[^a-z0-9# ]'), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }

  String _vinylCode(Map<String, dynamic> v) {
    final a = _asInt(v['artistNo']);
    final b = _asInt(v['albumNo']);
    if (a > 0 && b > 0) return '$a.$b';

    final n = (v['numero'] ?? '').toString().trim();
    return n.isEmpty ? '—' : n;
  }

  bool _matchesLocal(Map<String, dynamic> v, String qNorm) {
    if (qNorm.isEmpty) return true;

    final artista = _norm((v['artista'] ?? '').toString());
    final album = _norm((v['album'] ?? '').toString());
    final genre = _norm((v['genre'] ?? '').toString());
    final country = _norm((v['country'] ?? '').toString());
    final year = _norm((v['year'] ?? '').toString());
    final numero = _norm(_vinylCode(v));

    if (artista.contains(qNorm)) return true;
    if (album.contains(qNorm)) return true;
    if (numero.contains(qNorm)) return true;
    if (year.contains(qNorm)) return true;
    if (genre.contains(qNorm)) return true;
    if (country.contains(qNorm)) return true;

    return false;
  }

  int _getPageForList({required bool conBorrar, required bool onlyFavorites}) {
    if (conBorrar) return _pageBorrar;
    if (onlyFavorites) return _pageFavoritos;
    return _pageVinilos;
  }

  void _setPageForList({required bool conBorrar, required bool onlyFavorites, required int page}) {
    final p = page < 1 ? 1 : page;
    setState(() {
      if (conBorrar) {
        _pageBorrar = p;
      } else if (onlyFavorites) {
        _pageFavoritos = p;
      } else {
        _pageVinilos = p;
      }
    });
  }

  void _resetPagingAll() {
    _pageVinilos = 1;
    _pageFavoritos = 1;
    _pageBorrar = 1;
  }

  @override
  void dispose() {
    _debounceArtist?.cancel();
    _debounceAlbum?.cancel();
    _debounceLocalSearch?.cancel();
    ViewModeService.modeNotifier.removeListener(_viewModeListener);
    artistaCtrl.dispose();
    albumCtrl.dispose();
    yearCtrl.dispose();
    _artistFocus.dispose();
    _localSearchCtrl.dispose();
    _localSearchFocus.dispose();
    super.dispose();
  }

  void snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  bool _isFav(Map<String, dynamic> v) {
    final id = _asInt(v['id']);
    final raw = v['favorite'];
    final dbFav = (raw == 1 || raw == true || raw == '1' || raw == 'true' || raw == 'TRUE');
    if (id > 0) return _favCache[id] ?? dbFav;
    return dbFav;
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }



    Future<void> _toggleFavorite(Map<String, dynamic> v) async {
    // 💡 Meta: que SIEMPRE funcione (marcar y desmarcar) sin depender de que el mapa sea mutable
    // y sin que falle por backups/permisos.
    final id0 = _asInt(v['id']);
    final artista = (v['artista'] ?? '').toString();
    final album = (v['album'] ?? '').toString();
    final numero = _asInt(v['numero']);
    final mbid = (v['mbid'] ?? '').toString();

    final current = _isFav(v);
    final next = !current;

    // ✅ UI instantánea
    setState(() {
      if (id0 > 0) _favCache[id0] = next;
      // No tocamos v['favorite'] para evitar errores si el Map viene de sqflite como solo-lectura.
    });

    int resolvedId = id0;

    try {
      // 1) Intento estricto por ID cuando está disponible.
      if (resolvedId > 0) {
        try {
          await VinylDb.instance.setFavoriteStrictById(id: resolvedId, favorite: next);
        } catch (_) {
          // Si por algún motivo el ID no actualiza, hacemos fallback seguro.
          await VinylDb.instance.setFavoriteSafe(
            favorite: next,
            id: resolvedId,
            artista: artista,
            album: album,
            numero: numero,
            mbid: mbid,
          );

          // Re-resolver ID por exact/mbid para dejar el cache consistente.
          final exact = (artista.trim().isNotEmpty && album.trim().isNotEmpty)
              ? await VinylDb.instance.findByExact(artista: artista, album: album)
              : null;
          resolvedId = _asInt(exact?['id']);
          if (resolvedId <= 0 && mbid.trim().isNotEmpty) {
            final byMbid = await VinylDb.instance.findByMbid(mbid: mbid);
            resolvedId = _asInt(byMbid?['id']);
          }
        }
      } else {
        // 2) Sin ID: fallback robusto (artista+álbum / mbid / número)
        await VinylDb.instance.setFavoriteSafe(
          favorite: next,
          id: null,
          artista: artista,
          album: album,
          numero: numero,
          mbid: mbid,
        );

        final exact = (artista.trim().isNotEmpty && album.trim().isNotEmpty)
            ? await VinylDb.instance.findByExact(artista: artista, album: album)
            : null;
        resolvedId = _asInt(exact?['id']);
        if (resolvedId <= 0 && mbid.trim().isNotEmpty) {
          final byMbid = await VinylDb.instance.findByMbid(mbid: mbid);
          resolvedId = _asInt(byMbid?['id']);
        }
      }

      // Si el usuario salió de la pantalla mientras esperábamos respuestas, evitamos setState.
      if (!mounted) return;

      // ✅ Mantener cache consistente con el ID real (si cambió)
      if (resolvedId > 0 && resolvedId != id0) {
        setState(() {
          _favCache.remove(id0);
          _favCache[resolvedId] = next;
        });
      }

      // ✅ Refrescar favoritos (para que al entrar se vea correcto)
      setState(() {
        _futureFav = VinylDb.instance.getFavorites();
      });

      await _refreshHomeCounts();

      if (!mounted) return;

      // 3) Backup: NO debe romper favoritos si falla
      try {
        await BackupService.autoSaveIfEnabled();
      } catch (_) {
        // no revertimos favorito
      }
    } catch (_) {
      // revertir si falla el update real en DB
      if (!mounted) return;
      setState(() {
        if (resolvedId > 0) _favCache[resolvedId] = current;
        if (id0 > 0) _favCache[id0] = current;
      });
      snack('Error actualizando favorito.');
    }
  }


  void _openDetail(Map<String, dynamic> v) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.90,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            child: VinylDetailSheet(vinyl: v, showPrices: false),
          ),
        ),
      ),
    ).then((_) {
      if (!mounted) return;
      setState(() {}); // por si cambiaste favorito en el detalle
    });
  }

  /// Badge para el número de orden (NO editable).
  /// Se apoya en el ColorScheme para que se vea bien en todos los temas.
  Widget _numeroBadge(BuildContext context, dynamic numero, {bool compact = false, bool micro = false}) {
    final scheme = Theme.of(context).colorScheme;
    final txt = (numero ?? '').toString().trim();

    // En grid/overlays queremos que NO tape la carátula.
    // En lista puede ir un pelín más grande, pero igual compacto.
    final padH = micro ? 5.0 : (compact ? 6.0 : 7.0);
    final padV = micro ? 1.5 : (compact ? 2.0 : 3.0);
    final fontSize = micro ? 9.0 : (compact ? 10.0 : 11.0);
    final radius = micro ? 5.0 : (compact ? 6.0 : 7.0);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      constraints: BoxConstraints(minWidth: micro ? 18 : 22, minHeight: micro ? 16 : 18),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withOpacity(micro ? 0.88 : 0.92),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.8)),
      ),
      child: Text(
        txt,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          height: 1.0,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _leadingCover(
    Map<String, dynamic> v, {
    double size = 56,
    BoxFit fit = BoxFit.cover,
  }) {
    final cp = (v['coverPath'] as String?)?.trim() ?? '';
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cachePx = (size * dpr).round().clamp(64, 1024);

    String pick = cp;
    if (pick.isNotEmpty && _fileExistsCached(pick)) {
      // Si existe un thumb descargado (cover_cache_service), úsalo en tamaños pequeños.
      if (size <= 72 && pick.contains('_full.')) {
        final thumb = pick.replaceFirst('_full.', '_thumb.');
        if (_fileExistsCached(thumb)) pick = thumb;
      }
    }

    return AppCoverImage(
      pathOrUrl: pick,
      width: size,
      height: size,
      fit: fit,
      borderRadius: BorderRadius.circular(8),
      cacheWidth: cachePx,
      cacheHeight: cachePx,
    );
  }

  /// Carátula para cards tipo Grid.
  ///
  /// En Grid priorizamos que la carátula se vea **completa** (sin recorte).
  /// Por eso el `fit` por defecto es [BoxFit.contain].
  Widget _gridCover(Map<String, dynamic> v, {BoxFit fit = BoxFit.contain}) {
    final cp = (v['coverPath'] as String?)?.trim() ?? '';
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final side = constraints.biggest.shortestSide;
        final target = (side.isFinite && side > 0) ? side : 220.0;
        final cache = (target * dpr).round().clamp(128, 1024);

        String pick = cp;
        if (pick.isNotEmpty && _fileExistsCached(pick)) {
          if (target <= 150 && pick.contains('_full.')) {
            final thumb = pick.replaceFirst('_full.', '_thumb.');
            if (_fileExistsCached(thumb)) pick = thumb;
          }
        }

        return AppCoverImage(
          pathOrUrl: pick,
          fit: fit,
          cacheWidth: cache,
          cacheHeight: cache,
          borderRadius: BorderRadius.zero,
        );
      },
    );
  }
  Widget _metaPill(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = text.trim().isEmpty ? '—' : text.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(isDark ? 0.35 : 0.65),
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

  Widget _vinylListCard(Map<String, dynamic> v, {required bool conBorrar}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final year = ((v['year'] ?? '').toString().trim());
    final genre = ((v['genre'] ?? '').toString().trim());
    final country = ((v['country'] ?? '').toString().trim());
    final artista = ((v['artista'] ?? '').toString().trim());
    final album = ((v['album'] ?? '').toString().trim());
    final fav = _isFav(v);

    final actions = <Widget>[
      if (!conBorrar && artista.isNotEmpty)
        _gridActionIcon(
          tooltip: context.tr('Similares'),
          icon: Icons.hub_outlined,
          color: cs.onSurfaceVariant,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SimilarArtistsScreen(initialArtistName: artista),
              ),
            );
          },
        ),
      if (!conBorrar)
        _gridActionIcon(
          tooltip: fav ? 'Quitar favorito' : 'Marcar favorito',
          icon: fav ? Icons.star : Icons.star_border,
          color: fav ? Colors.amber : cs.onSurfaceVariant,
          onPressed: () => _toggleFavorite(v),
        ),
      if (conBorrar && !_borrarPapelera)
        _gridActionIcon(
          tooltip: context.tr('Enviar a papelera'),
          icon: Icons.delete_outline,
          color: cs.onSurfaceVariant,
          onPressed: () async {
            final id = _asInt(v['id']);
            if (id == 0) return;
            await VinylDb.instance.moveToTrash(id);
            await BackupService.autoSaveIfEnabled();
            if (!mounted) return;
            _reloadAllData();
            snack('Enviado a papelera');
          },
        ),
      if (conBorrar && _borrarPapelera) ...[
        _gridActionIcon(
          tooltip: context.tr('Restaurar'),
          icon: Icons.restore_from_trash,
          color: cs.onSurfaceVariant,
          onPressed: () async {
            final trashId = _asInt(v['id']);
            if (trashId == 0) return;
            final ok = await VinylDb.instance.restoreFromTrash(trashId);
            await BackupService.autoSaveIfEnabled();
            if (!mounted) return;
            _reloadAllData();
            snack(ok ? 'Restaurado' : 'No se pudo restaurar');
          },
        ),
        _gridActionIcon(
          tooltip: context.tr('Eliminar definitivo'),
          icon: Icons.delete_forever,
          color: cs.onSurfaceVariant,
          onPressed: () async {
            final trashId = _asInt(v['id']);
            if (trashId == 0) return;
            await VinylDb.instance.deleteTrashById(trashId);
            await BackupService.autoSaveIfEnabled();
            if (!mounted) return;
            _reloadAllData();
            snack('Eliminado');
          },
        ),
      ],
    ];

    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      color: Theme.of(context).cardTheme.color ?? cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(isDark ? 0.55 : 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openDetail(v),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              color: cs.surfaceContainerHighest.withOpacity(isDark ? 0.30 : 0.60),
                              child: _leadingCover(v, size: 92, fit: BoxFit.contain),
                            ),
                          ),
                          Positioned(
                            left: 6,
                            bottom: 6,
                            child: _numeroBadge(context, _vinylCode(v), micro: true),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${context.tr('Año')} ${year.isEmpty ? '—' : year}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${context.tr('País')} ${country.isEmpty ? '—' : country}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                    if (genre.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        genre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Spacer(),
                        if (actions.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: actions
                                .map((w) => Padding(padding: const EdgeInsets.only(left: 2), child: w))
                                .toList(growable: false),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // ✅ Swipes rápidos (modo normal):
    // - Swipe → (izq...der) = favorito
    // - Swipe ← (der...izq) = enviar a papelera (con confirmación)
    if (conBorrar) return card;

    final id = _asInt(v['id']);
    if (id <= 0) return card;

    return Dismissible(
      key: ValueKey('vinyl_$id'),
      direction: DismissDirection.horizontal,
      background: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.centerLeft,
        color: cs.primary.withOpacity(0.18),
        child: Row(
          children: [
            Icon(_isFav(v) ? Icons.star_outline : Icons.star, color: cs.primary),
            SizedBox(width: 8),
            Text(_isFav(v) ? 'Quitar favorito' : 'Favorito', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
      secondaryBackground: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.centerRight,
        color: Colors.red.withOpacity(0.18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text(context.tr('Papelera'), style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          await _toggleFavorite(v);
          return false; // no se elimina
        }

        // endToStart
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: Text(context.tr('¿Enviar a papelera?')),
              content: Text('"$artista" — "$album"'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('Cancelar'))),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('Enviar'))),
              ],
            );
          },
        );

        if (ok == true) {
          await VinylDb.instance.moveToTrash(id);
          await BackupService.autoSaveIfEnabled();
          if (mounted) {
            _reloadAllData();
            snack('Enviado a papelera');
          }
          return true;
        }
        return false;
      },
      onDismissed: (_) {
        // El reload ya se pidió en confirmDismiss, pero esto asegura UI estable.
        if (mounted) _reloadAllData();
      },
      child: card,
    );
  }


  Widget _gridActionIcon({
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
    Color? color,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: color),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  
  Widget _gridTile(Map<String, dynamic> v, {required bool conBorrar}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final artista = ((v['artista'] ?? '').toString().trim());
    final album = ((v['album'] ?? '').toString().trim());
    final year = ((v['year'] ?? '').toString().trim());
    final fav = _isFav(v);

    Widget actions() {
      if (!conBorrar) {
        return IconButton(
          tooltip: fav ? 'Quitar favorito' : 'Marcar favorito',
          onPressed: () => _toggleFavorite(v),
          icon: Icon(
            fav ? Icons.star : Icons.star_border,
            color: fav ? Colors.amber : cs.onSurfaceVariant,
            size: 22,
          ),
          visualDensity: VisualDensity.compact,
        );
      }
      if (!_borrarPapelera) {
        return IconButton(
          tooltip: context.tr('Enviar a papelera'),
          onPressed: () async {
            final id = _asInt(v['id']);
            if (id == 0) return;
            await VinylDb.instance.moveToTrash(id);
            await BackupService.autoSaveIfEnabled();
            if (!mounted) return;
            _reloadAllData();
            snack('Enviado a papelera');
          },
          icon: Icon(Icons.delete_outline, color: cs.onSurfaceVariant, size: 22),
          visualDensity: VisualDensity.compact,
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: context.tr('Restaurar'),
            onPressed: () async {
              final trashId = _asInt(v['id']);
              if (trashId == 0) return;
              final ok = await VinylDb.instance.restoreFromTrash(trashId);
              await BackupService.autoSaveIfEnabled();
              if (!mounted) return;
              _reloadAllData();
              snack(ok ? 'Restaurado' : 'No se pudo restaurar');
            },
            icon: Icon(Icons.restore_from_trash, color: cs.onSurfaceVariant, size: 20),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: context.tr('Eliminar definitivo'),
            onPressed: () async {
              final trashId = _asInt(v['id']);
              if (trashId == 0) return;
              await VinylDb.instance.deleteTrashById(trashId);
              await BackupService.autoSaveIfEnabled();
              if (!mounted) return;
              _reloadAllData();
              snack('Eliminado');
            },
            icon: Icon(Icons.delete_forever, color: cs.onSurfaceVariant, size: 20),
            visualDensity: VisualDensity.compact,
          ),
        ],
      );
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(isDark ? 0.55 : 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(v),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: cs.surfaceContainerHighest.withOpacity(isDark ? 0.30 : 0.60),
                    child: _gridCover(v, fit: BoxFit.contain),
                  ),
                ),
              ),
              SizedBox(height: 10),
              Text(
                artista.isEmpty ? '—' : artista,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 2),
              Text(
                album.isEmpty ? '—' : album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              Spacer(),
              Row(
                children: [
                  _numeroBadge(context, _vinylCode(v), compact: true),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      year.isEmpty ? '—' : year,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  actions(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverOnlyTile(Map<String, dynamic> v, {required bool conBorrar}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final code = _vinylCode(v);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(isDark ? 0.55 : 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(v),
        onLongPress: (!conBorrar) ? () => _toggleFavorite(v) : null,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: cs.surfaceContainerHighest.withOpacity(isDark ? 0.30 : 0.60),
                    child: _gridCover(v, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: _numeroBadge(context, code, micro: true),
            ),
          ],
        ),
      ),
    );
  }


  Widget _gridVinylCard(Map<String, dynamic> v, {required bool conBorrar}) {
    final cs = Theme.of(context).colorScheme;
    final year = (v['year'] as String?)?.trim() ?? '';
    final artista = (v['artista'] as String?)?.trim() ?? '';
    final album = (v['album'] as String?)?.trim() ?? '';
    final fav = _isFav(v);

    return InkWell(
      onTap: () => _openDetail(v),
      borderRadius: BorderRadius.circular(14),
      child: Card(
        color: Theme.of(context).cardTheme.color ?? cs.surface,
        surfaceTintColor: Colors.transparent,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _gridCover(v),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    artista,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                          album,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                  SizedBox(height: 4),
                  Text(year.isEmpty ? '—' : year),
                ],
              ),
            ),

            // 🔢 número arriba derecha
            Positioned(
              right: 6,
              top: 6,
              child: _numeroBadge(context, _vinylCode(v), compact: true),
            ),

            // ⭐ Favoritos abajo derecha (lista grid + favoritos grid)
            if (!conBorrar)
              Positioned(
                right: 2,
                bottom: 2,
	                child: IconButton(
	                  tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
	                  // Borde blanco (no marcado) + relleno gris (marcado)
	                  icon: Icon(
	                    fav ? Icons.star : Icons.star_border,
	                    color: fav ? cs.primary : cs.onSurfaceVariant,
	                  ),
	                  onPressed: () => _toggleFavorite(v),
	                ),
	              ),

            // 🗑️ borrar abajo derecha (bien a la esquina)
            if (conBorrar)
              Positioned(
                right: 0,
                bottom: 0,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),

                  icon: Icon(Icons.delete),
                  onPressed: () async {
                    final id = _asInt(v['id']);
                    if (id == 0) return;

                    await VinylDb.instance.deleteById(id);
                    await BackupService.autoSaveIfEnabled();

                    // Si el usuario salió de la pantalla mientras esperaba, evitamos setState/snack.
                    if (!mounted) return;
                    snack('Borrado');
                    _reloadAllData();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- autocomplete artista ----
  void _onArtistChanged(String v) {
    _debounceArtist?.cancel();
    final q = v.trim();

    setState(() {
      artistaElegido = null;
      albumElegido = null;
      sugerenciasAlbums = [];
      buscandoAlbums = false;
      prepared = null;
      mostrarAgregar = false;
      resultados = [];
    });

    if (q.isEmpty) {
      setState(() {
        sugerenciasArtistas = [];
        buscandoArtistas = false;
      });
      return;
    }

    _debounceArtist = Timer(Duration(milliseconds: 350), () async {
      setState(() => buscandoArtistas = true);
      final hits = await DiscographyService.searchArtists(q);
      if (!mounted) return;
      setState(() {
        sugerenciasArtistas = hits;
        buscandoArtistas = false;
      });
    });
  }

  Future<void> _pickArtist(ArtistHit a) async {
    FocusScope.of(context).unfocus();
    setState(() {
      artistaElegido = a;
      artistaCtrl.text = a.name;
      sugerenciasArtistas = [];

      // Cuando eliges artista: reinicia álbum
      albumCtrl.clear();
      albumElegido = null;
      sugerenciasAlbums = [];
      buscandoAlbums = false;

      prepared = null;
      mostrarAgregar = false;
      resultados = [];
    });
  }

  void _onAlbumChanged(String v) {
    _debounceAlbum?.cancel();
    final q = v.trim();
    final artistName = artistaCtrl.text.trim();

    setState(() {
      albumElegido = null;
      prepared = null;
      mostrarAgregar = false;
      resultados = [];
    });

    if (artistName.isEmpty || q.isEmpty) {
      setState(() {
        sugerenciasAlbums = [];
        buscandoAlbums = false;
      });
      return;
    }

    _debounceAlbum = Timer(Duration(milliseconds: 220), () async {
      setState(() => buscandoAlbums = true);
      // MetadataService.searchAlbumsForArtist usa parámetros POSICIONALES
      // (artistName, albumQuery)
      final hits = await MetadataService.searchAlbumsForArtist(artistName, q);
      if (!mounted) return;
      setState(() {
        sugerenciasAlbums = hits;
        buscandoAlbums = false;
      });
    });
  }

  Future<void> _pickAlbum(AlbumSuggest a) async {
    FocusScope.of(context).unfocus();
    setState(() {
      albumElegido = a;
      albumCtrl.text = a.title;
      sugerenciasAlbums = [];
      prepared = null;
      mostrarAgregar = false;
      resultados = [];
    });
  }

  Future<void> buscar() async {
    final artista = artistaCtrl.text.trim();
    final album = albumCtrl.text.trim();

    if (artista.isEmpty && album.isEmpty) {
      snack('Escribe al menos Artista o Álbum');
      return;
    }

    final res = await VinylDb.instance.search(artista: artista, album: album);


    if (!mounted) return;

        setState(() {
      resultados = res;
      prepared = null;
      mostrarAgregar = res.isEmpty && artista.isNotEmpty && album.isNotEmpty;
      yearCtrl.clear();
    });

    if (res.isEmpty) {
      snack('No lo tienes');
    } else {
      snack('Discos encontrados: ${res.length}');
    }

    if (mostrarAgregar) {
      setState(() => autocompletando = true);

      final p = await VinylAddService.prepare(
        artist: artista,
        album: album,
        artistId: artistaElegido?.id,
      );

      if (!mounted) return;

      setState(() {
        prepared = p;
        yearCtrl.text = p.year ?? '';
        autocompletando = false;
      });
    }

    // dejamos el texto (para que veas lo que buscaste) y solo ocultamos sugerencias
    setState(() {
      sugerenciasArtistas = [];
      sugerenciasAlbums = [];
      buscandoArtistas = false;
      buscandoAlbums = false;
    });
  }

  Future<void> agregar() async {
    final p = prepared;
    if (p == null) return;

    final res = await VinylAddService.addPrepared(
      p,
      overrideYear: yearCtrl.text.trim().isEmpty ? null : yearCtrl.text.trim(),
      condition: _addCondition,
      format: _addFormat,
    );

    snack(res.message);
    if (!res.ok) return;

    await AddDefaultsService.saveLast(condition: _addCondition, format: _addFormat);

    await BackupService.autoSaveIfEnabled();


    if (!mounted) return;

        setState(() {
      prepared = null;
      mostrarAgregar = false;
      resultados = [];
      yearCtrl.clear();
    });
  }

  Widget contadorLp() {
    return FutureBuilder<int>(
      future: VinylDb.instance.getCount(),
      builder: (context, snap) {
        if (snap.hasError) {
          return SizedBox(width: 90, height: 70);
        }
        final total = snap.data ?? 0;
        return Container(
          width: 90,
          height: 70,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(
            '$total',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      },
    );
  }

  Widget nubeEstado() {
    return FutureBuilder<bool>(
      future: BackupService.isAutoEnabled(),
      builder: (context, snap) {
        final auto = snap.data ?? false;
        return Container(
          width: 90,
          height: 70,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            auto ? Icons.cloud_done : Icons.cloud_off,
            color: auto ? Colors.greenAccent : Colors.white54,
            size: 30,
          ),
        );
      },
    );
  }

  Widget encabezadoInicio() {
    // ✅ Pedido: quitar contador total y nube de activación del inicio
    return const SizedBox.shrink();
  }

  Widget gabolpMarca() {
    return Positioned(
      right: 10,
      bottom: 8,
      child: IgnorePointer(
        child: Text(context.tr('GaBoLP'),
          style: TextStyle(
            fontSize: 14,
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget botonesInicio() {
    // ✅ Home Dashboard (diseño premium).
    // Mantiene la misma lógica/callbacks.

    final all = _homeCounts['all'] ?? 0;
    final fav = _homeCounts['fav'] ?? 0;
    final wish = _homeCounts['wish'] ?? 0;

    void openDiscografias() {
      Navigator.push(context, MaterialPageRoute(builder: (_) => DiscographyScreen())).then((_) {
        if (!mounted) return;
        _reloadAllData();
      });
    }

    Widget sectionHeader(String title, {String? subtitle, String? action, VoidCallback? onAction}) {
      final t = Theme.of(context);
      final cs = t.colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                  if (subtitle != null) ...[
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: t.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.72),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ]
                ],
              ),
            ),
            if (action != null && onAction != null)
              TextButton.icon(
                onPressed: onAction,
                icon: Icon(Icons.chevron_right),
                label: Text(action, style: TextStyle(fontWeight: FontWeight.w900)),
              ),
          ],
        ),
      );
    }


    Widget recentGrid() {
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: _futureAll,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return SizedBox(
              height: 260,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final items = snap.data ?? const <Map<String, dynamic>>[];
          if (items.isEmpty) {
            return _emptyState(
              icon: Icons.library_music,
              title: 'Aún no hay vinilos',
              subtitle: 'Agrega tu primer vinilo para empezar tu colección.',
              actionText: 'Ir a Discografías',
              onAction: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => DiscographyScreen())).then((_) {
                  if (!mounted) return;
                  _reloadAllData();
                });
              },
            );
          }

          final sorted = List<Map<String, dynamic>>.from(items);
          sorted.sort((a, b) => _asInt(b['id']).compareTo(_asInt(a['id'])));
          final recent = sorted.take(8).toList();

          return SizedBox(
            height: 280,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: recent.length,
              separatorBuilder: (_, __) => SizedBox(width: 12),
              itemBuilder: (context, i) {
                return SizedBox(
                  width: 220,
                  child: _gridVinylCard(recent[i], conBorrar: false),
                );
              },
            ),
          );
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeHeader(
          allCount: all,
          favoritesCount: fav,
          wishlistCount: wish,
          onRefresh: _reloadAllData,
          onVinyls: () {
            _reloadAllData();
            if (!mounted) return;
            _setVista(Vista.lista);
          },
          onFavorites: () {
            _reloadAllData();
            if (!mounted) return;
            _setVista(Vista.favoritos);
          },
          onWishlist: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => WishlistScreen())).then((_) {
              if (!mounted) return;
              _reloadAllData();
            });
          },
          onSearch: openDiscografias,
          onScanner: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => ScannerScreen())).then((_) {
              if (!mounted) return;
              _reloadAllData();
            });
          },
          onTrash: () {
            _borrarPapelera = false;
            _reloadAllData();
            if (!mounted) return;
            _setVista(Vista.borrar);
          },
          onSettings: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen())),
        ),

        sectionHeader(
          context.tr('Últimos agregados'),
          subtitle: context.tr('Lo último que guardaste en tu colección.'),
          action: context.tr('Ver todos'),
          onAction: () {
            _reloadAllData();
            if (!mounted) return;
            _setVista(Vista.lista);
          },
        ),

        recentGrid(),
        SizedBox(height: 10),
      ],
    );
  }


Widget vistaBorrar({bool embedInScroll = true}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: _borrarPapelera
                ? OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _borrarPapelera = false);
                      _reloadAllData();
                    },
                    icon: Icon(Icons.delete_outline),
                    label: Text(context.tr('Para borrar')),
                  )
                : ElevatedButton.icon(
                    onPressed: () {},
                    icon: Icon(Icons.delete_outline),
                    label: Text(context.tr('Para borrar')),
                  ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: _borrarPapelera
                ? ElevatedButton.icon(
                    onPressed: () {},
                    icon: Icon(Icons.restore),
                    label: Text(context.tr('Papelera')),
                  )
                : OutlinedButton.icon(
                    onPressed: () async {
                      // Carga rápida para mostrar papelera
                      setState(() {
                        _borrarPapelera = true;
                        _futureTrash = VinylDb.instance.getTrash();
                      });
                    },
                    icon: Icon(Icons.restore),
                    label: Text(context.tr('Papelera')),
                  ),
          ),
        ],
      ),
      if (embedInScroll) ...[
        SizedBox(height: 12),
        listaCompleta(conBorrar: true, onlyFavorites: false, embedInScroll: true),
      ],
    ],
  );
}




  Widget vistaBuscar() {
    final p = prepared;
    final showXArtist = artistaCtrl.text.trim().isNotEmpty;
    final showXAlbum = albumCtrl.text.trim().isNotEmpty;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget suggestionBox<T>({
      required List<T> items,
      required Widget Function(T) tile,
    }) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline.withOpacity(isDark ? 0.85 : 1.0)),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => Divider(height: 1),
          itemBuilder: (context, i) => tile(items[i]),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ✅ SOLO: Artista, Álbum y botón Buscar
        TextField(
          controller: artistaCtrl,
          focusNode: _artistFocus,
          onChanged: _onArtistChanged,
          decoration: InputDecoration(
            labelText: context.tr('Artista'),
            suffixIcon: showXArtist
                ? IconButton(
                    tooltip: context.tr('Limpiar'),
                    icon: Icon(Icons.close, size: 18),
                    onPressed: _limpiarArtista,
                  )
                : null,
          ),
        ),
        if (buscandoArtistas)
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(),
          ),
        if (sugerenciasArtistas.isNotEmpty)
          suggestionBox<ArtistHit>(
            items: sugerenciasArtistas,
            tile: (a) {
              final c = (a.country ?? '').trim();
              return ListTile(
                dense: true,
                title: Text(a.name),
                subtitle: c.isEmpty ? null : Text(AppStrings.labeled(context, 'País', c)),
                onTap: () => _pickArtist(a),
              );
            },
          ),

        SizedBox(height: 10),

        TextField(
          controller: albumCtrl,
          onChanged: _onAlbumChanged,
          decoration: InputDecoration(
            labelText: context.tr('Álbum'),
            suffixIcon: showXAlbum
                ? IconButton(
                    tooltip: context.tr('Limpiar'),
                    icon: Icon(Icons.close, size: 18),
                    onPressed: _limpiarAlbum,
                  )
                : null,
          ),
        ),
        if (buscandoAlbums)
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(),
          ),
        if (sugerenciasAlbums.isNotEmpty)
          suggestionBox<AlbumSuggest>(
            items: sugerenciasAlbums,
            tile: (al) {
              final y = (al.year ?? '').trim();
              return ListTile(
                dense: true,
                title: Text(al.title),
                subtitle: y.isEmpty ? null : Text(AppStrings.labeled(context, 'Año', y)),
                onTap: () => _pickAlbum(al),
              );
            },
          ),

        SizedBox(height: 10),
        ElevatedButton(
          onPressed: buscar,
          child: Text(context.tr('Buscar')),
        ),

        SizedBox(height: 8),
        OutlinedButton(
          onPressed: _cancelarBusqueda,
          child: Text(context.tr('Limpiar')),
        ),

        // ✅ Si lo tienes en la colección
        if (resultados.isNotEmpty) ...[
          SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline.withOpacity(isDark ? 0.85 : 1.0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('Ya lo tienes en tu colección:'),
                  style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
                ),
                SizedBox(height: 8),
                ...resultados.map((v) {
                  final y = (v['year'] as String?)?.trim() ?? '';
                  final yTxt = y.isEmpty ? '' : ' ($y)';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        _leadingCover(v),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_vinylCode(v)} — ${v['artista']} — ${v['album']}$yTxt',
                            style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ],

        // ✅ Si NO está y se puede agregar, mostramos automático año/género/país/caratula + botón
        if (mostrarAgregar) ...[
          SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline.withOpacity(isDark ? 0.85 : 1.0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('Agregar este vinilo'), style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
                SizedBox(height: 8),
                if (autocompletando) LinearProgressIndicator(),
                if (!autocompletando && p != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: (p.selectedCover500 ?? '').trim().isEmpty
                            ? Container(
                                width: 90,
                                height: 90,
                                color: Colors.black12,
                                alignment: Alignment.center,
                                child: Icon(Icons.album, size: 40),
                              )
                            : Image.network(
                                p.selectedCover500!,
                                width: 90,
                                height: 90,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 90,
                                  height: 90,
                                  color: Colors.black12,
                                  alignment: Alignment.center,
                                  child: Icon(Icons.broken_image),
                                ),
                              ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(AppStrings.labeled(context, 'Artista', p.artist), style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
                            Text(AppStrings.labeled(context, 'Álbum', p.album), style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
                            SizedBox(height: 6),
                            Text(AppStrings.labeled(context, 'Año', (p.year ?? '—')), style: TextStyle(color: cs.onSurface.withOpacity(0.72), fontWeight: FontWeight.w600)),
                            Text(AppStrings.labeled(context, 'Género', (p.genre ?? '—')), style: TextStyle(color: cs.onSurface.withOpacity(0.72), fontWeight: FontWeight.w600)),
                            Text(AppStrings.labeled(context, 'País', (p.country ?? '—')), style: TextStyle(color: cs.onSurface.withOpacity(0.72), fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  // ✅ Selector simple de carátula (cuando hay varias opciones)
                  if (p.coverCandidates.length > 1)
                    SizedBox(
                      height: 54,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: p.coverCandidates.length,
                        separatorBuilder: (_, __) => SizedBox(width: 10),
                        itemBuilder: (_, i) {
                          final c = p.coverCandidates[i];
                          final selected = identical(p.selectedCover, c);
                          final url = (c.coverUrl250 ?? c.coverUrl500 ?? '').trim();
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setState(() => p.selectedCover = c),
                            child: Container(
                              width: 54,
                              height: 54,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected ? cs.primary : cs.outlineVariant,
                                  width: selected ? 2 : 1,
                                ),
                                color: cs.surfaceContainerHighest.withOpacity(selected ? 0.55 : 0.30),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: url.isEmpty
                                    ? Center(child: Icon(Icons.album, size: 20))
                                    : Image.network(
                                        url,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Center(child: Icon(Icons.album, size: 20)),
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  if (p.coverCandidates.length > 1) SizedBox(height: 10),
                  // año editable (opcional)
                  TextField(
                    controller: yearCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.tr('Año (opcional: corregir)'),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withOpacity(isDark ? 0.14 : 0.65),
                    ),
                    style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _addCondition,
                          decoration: InputDecoration(labelText: context.tr('Condición')),
                          items: [
                            DropdownMenuItem(value: 'M', child: Text(context.tr('M (Mint)'))),
                            DropdownMenuItem(value: 'NM', child: Text(context.tr('NM (Near Mint)'))),
                            DropdownMenuItem(value: 'VG+', child: Text(context.tr('VG+'))),
                            DropdownMenuItem(value: 'VG', child: Text(context.tr('VG'))),
                            DropdownMenuItem(value: 'G', child: Text('G')),
                          ],
                          onChanged: (v) => setState(() => _addCondition = v ?? _addCondition),
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _addFormat,
                          decoration: InputDecoration(labelText: context.tr('Formato')),
                          items: [
                            DropdownMenuItem(value: 'LP', child: Text(context.tr('LP'))),
                            DropdownMenuItem(value: 'EP', child: Text(context.tr('EP'))),
                            DropdownMenuItem(value: 'Single', child: Text(context.tr('Single'))),
                            DropdownMenuItem(value: '2xLP', child: Text(context.tr('2xLP'))),
                          ],
                          onChanged: (v) => setState(() => _addFormat = v ?? _addFormat),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: agregar,
                    child: Text(context.tr('Agregar vinilo')),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  
  int? _parseYear(dynamic y) {
    final s = (y as String?)?.trim();
    if (s == null || s.isEmpty) return null;
    return int.tryParse(s);
  }

  // ----------------- ORDEN / SECCIONES POR ARTISTA -----------------
  String _normalizeArtistForSort(String s) {
    var t = s.trim().toLowerCase();
    // Quitamos artículos comunes al inicio para ordenar “Beatles” bajo B, no bajo T.
    for (final a in const ['the ', 'los ', 'las ', 'el ', 'la ']) {
      if (t.startsWith(a)) {
        t = t.substring(a.length);
        break;
      }
    }
    // Normalización básica de acentos (suficiente para encabezados A–Z).
    t = t
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
    // Quitamos símbolos iniciales comunes.
    // Nota: usamos raw triple-quoted string para poder incluir comillas dobles y simples sin romper el parser.
    t = t.replaceFirst(RegExp(r'''^[\s\"'\(\[\{]+'''), '');
    return t;
  }

  String _alphaBucketFromArtist(String artistName) {
    final norm = _normalizeArtistForSort(artistName);
    if (norm.isEmpty) return '#';
    final ch = String.fromCharCode(norm.runes.first).toUpperCase();
    if (RegExp(r'[A-Z]').hasMatch(ch)) return ch;
    if (RegExp(r'[0-9]').hasMatch(ch)) return '#';
    return '#';
  }

  Widget _alphaHeader(String letter) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    // Encabezado de sección (A/B/C…) con fondo suave para que se diferencie
    // tanto en tema claro como oscuro.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.outlineVariant.withOpacity(0.55),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Text(
              letter,
              style: t.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
                color: cs.onSurfaceVariant.withOpacity(0.95),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 1,
                color: cs.outlineVariant.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _applyListFiltersAndSort(List<Map<String, dynamic>> items) {
    final aQ = _filterArtistQ.trim().toLowerCase();
    final gQ = _filterGenreQ.trim().toLowerCase();
    final cQ = _filterCountryQ.trim().toLowerCase();

    Iterable<Map<String, dynamic>> it = items;

    if (aQ.isNotEmpty) {
      it = it.where((v) {
        final a = ((v['artista'] as String?) ?? '').toLowerCase();
        final al = ((v['album'] as String?) ?? '').toLowerCase();
        return a.contains(aQ) || al.contains(aQ);
      });
    }
    if (gQ.isNotEmpty) {
      it = it.where((v) => (((v['genre'] as String?) ?? '').toLowerCase()).contains(gQ));
    }
    if (cQ.isNotEmpty) {
      it = it.where((v) => (((v['country'] as String?) ?? '').toLowerCase()).contains(cQ));
    }
    if (_filterYearFrom != null || _filterYearTo != null) {
      final from = _filterYearFrom;
      final to = _filterYearTo;
      it = it.where((v) {
        final y = _parseYear(v['year']);
        if (y == null) return false;
        if (from != null && y < from) return false;
        if (to != null && y > to) return false;
        return true;
      });
    }

    final list = it.toList();

    int safeCmp(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

    switch (_sortMode) {
      case VinylSortMode.az:
        list.sort((x, y) {
          final ax = (x['artista'] as String?) ?? '';
          final ay = (y['artista'] as String?) ?? '';
          final c1 = safeCmp(_normalizeArtistForSort(ax), _normalizeArtistForSort(ay));
          if (c1 != 0) return c1;
          final bx = (x['album'] as String?) ?? '';
          final by = (y['album'] as String?) ?? '';
          return safeCmp(bx, by);
        });
        break;
      case VinylSortMode.yearDesc:
        list.sort((x, y) {
          final yx = _parseYear(x['year']) ?? -1;
          final yy = _parseYear(y['year']) ?? -1;
          final c1 = yy.compareTo(yx);
          if (c1 != 0) return c1;
          final ax = (x['artista'] as String?) ?? '';
          final ay = (y['artista'] as String?) ?? '';
          return safeCmp(ax, ay);
        });
        break;
      case VinylSortMode.recent:
        list.sort((x, y) {
          final ix = (x['id'] as int?) ?? 0;
          final iy = (y['id'] as int?) ?? 0;
          return iy.compareTo(ix);
        });
        break;
      case VinylSortMode.code:
        list.sort((x, y) {
          final ax = _asInt(x['artistNo']);
          final ay = _asInt(y['artistNo']);
          final c1 = ax.compareTo(ay);
          if (c1 != 0) return c1;

          final bx = _asInt(x['albumNo']);
          final by = _asInt(y['albumNo']);
          final c2 = bx.compareTo(by);
          if (c2 != 0) return c2;

          final ix = _asInt(x['id']);
          final iy = _asInt(y['id']);
          return ix.compareTo(iy);
        });
        break;
    }

    return list;
  }

  void _openVinylFiltersSheet() {
    // valores temporales (para no aplicar hasta "Aplicar")
    String tArtist = _filterArtistQ;
    String tGenre = _filterGenreQ;
    String tCountry = _filterCountryQ;
    String tFrom = _filterYearFrom?.toString() ?? '';
    String tTo = _filterYearTo?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tune),
                        SizedBox(width: 10),
                        Expanded(child: Text(context.tr('Filtros'))),
                        TextButton(
                          onPressed: () {
                            setLocal(() {
                              tArtist = '';
                              tGenre = '';
                              tCountry = '';
                              tFrom = '';
                              tTo = '';
                            });
                          },
                          child: Text(context.tr('Limpiar')),
                        )
                      ],
                    ),
                    SizedBox(height: 10),
                    TextField(
                      decoration: InputDecoration(labelText: context.tr('Artista o álbum')),
                      controller: TextEditingController(text: tArtist),
                      onChanged: (v) => setLocal(() => tArtist = v),
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(labelText: context.tr('Año desde')),
                            controller: TextEditingController(text: tFrom),
                            onChanged: (v) => setLocal(() => tFrom = v),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(labelText: context.tr('Año hasta')),
                            controller: TextEditingController(text: tTo),
                            onChanged: (v) => setLocal(() => tTo = v),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    TextField(
                      decoration: InputDecoration(labelText: context.tr('Género (contiene)')),
                      controller: TextEditingController(text: tGenre),
                      onChanged: (v) => setLocal(() => tGenre = v),
                    ),
                    SizedBox(height: 10),
                    TextField(
                      decoration: InputDecoration(labelText: context.tr('País (contiene)')),
                      controller: TextEditingController(text: tCountry),
                      onChanged: (v) => setLocal(() => tCountry = v),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(context.tr('Cancelar')),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _filterArtistQ = tArtist;
                                _filterGenreQ = tGenre;
                                _filterCountryQ = tCountry;
                                _filterYearFrom = int.tryParse(tFrom.trim());
                                _filterYearTo = int.tryParse(tTo.trim());
                              });
                              Navigator.pop(ctx);
                            },
                            child: Text(context.tr('Aplicar')),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _niceEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionText,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 58),
            SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
            if (actionText != null && onAction != null) ...[
              SizedBox(height: 14),
              ElevatedButton(onPressed: onAction, child: Text(actionText)),
            ],
          ],
        ),
      ),
    );
  }

  // Compat: versiones anteriores usaban _emptyState().
  // Ahora centralizamos el diseño en _niceEmptyState().
  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionText,
    VoidCallback? onAction,
  }) {
    return _niceEmptyState(
      icon: icon,
      title: title,
      subtitle: subtitle,
      actionText: actionText,
      onAction: onAction,
    );
  }

  Widget _vinylListTopBar({required int shown, required int total}) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    final label = _hasAnyFilter ? AppStrings.shownOfTotal(context, shown, total) : '$total';

    List<Widget> chips() {
      final out = <Widget>[];

      void addChip(String label, VoidCallback onClear) {
        out.add(
          InputChip(
            label: Text(label, style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
            onDeleted: onClear,
            deleteIcon: const Icon(Icons.close, size: 18),
            backgroundColor: cs.surfaceVariant.withOpacity(0.55),
            side: BorderSide(color: cs.outlineVariant.withOpacity(0.55)),
            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
          ),
        );
      }

      final a = _filterArtistQ.trim();
      if (a.isNotEmpty) addChip('${context.tr('Artista')}: $a', () => setState(() => _filterArtistQ = ''));

      final g = _filterGenreQ.trim();
      if (g.isNotEmpty) addChip('${context.tr('Género')}: $g', () => setState(() => _filterGenreQ = ''));

      final c = _filterCountryQ.trim();
      if (c.isNotEmpty) addChip('${context.tr('País')}: $c', () => setState(() => _filterCountryQ = ''));

      if (_filterYearFrom != null || _filterYearTo != null) {
        final from = _filterYearFrom?.toString() ?? '—';
        final to = _filterYearTo?.toString() ?? '—';
        addChip('${context.tr('Año')}: $from–$to', () => setState(() {
              _filterYearFrom = null;
              _filterYearTo = null;
            }));
      }

      return out;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_hasAnyFilter)
                IconButton(
                  tooltip: context.tr('Quitar filtros'),
                  onPressed: () => setState(() {
                    _filterArtistQ = '';
                    _filterGenreQ = '';
                    _filterCountryQ = '';
                    _filterYearFrom = null;
                    _filterYearTo = null;
                  }),
                  icon: Icon(Icons.filter_alt_off),
                ),
              IconButton(
                tooltip: context.tr('Filtros'),
                onPressed: _openVinylFiltersSheet,
                icon: Icon(_hasAnyFilter ? Icons.filter_alt : Icons.filter_alt_outlined),
              ),
              PopupMenuButton<VinylSortMode>(
                tooltip: context.tr('Ordenar'),
                initialValue: _sortMode,
                onSelected: (m) {
                  setState(() => _sortMode = m);
                  _persistSortMode(m);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: VinylSortMode.code, child: Text(context.tr('Código'))),
                  PopupMenuItem(value: VinylSortMode.recent, child: Text(context.tr('Recientes'))),
                  PopupMenuItem(value: VinylSortMode.az, child: Text(context.tr('A–Z'))),
                  PopupMenuItem(value: VinylSortMode.yearDesc, child: Text(context.tr('Año'))),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.sort),
                      SizedBox(width: 6),
                      Text(vinylSortLabel(_sortMode)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_hasAnyFilter) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...chips().expand((w) sync* {
                    yield w;
                    yield const SizedBox(width: 8);
                  }),
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }

Widget listaCompleta({
  required bool conBorrar,
  required bool onlyFavorites,
  bool embedInScroll = true,
  String? artistKeyFilter,
}) {
  final Future<List<Map<String, dynamic>>> future;
  if (conBorrar) {
    future = _borrarPapelera ? _futureTrash : _futureAll;
  } else {
    future = onlyFavorites ? _futureFav : _futureAll;
  }

  return FutureBuilder<List<Map<String, dynamic>>>(
    key: ValueKey("list_${onlyFavorites ? 'fav' : 'all'}_${conBorrar ? (_borrarPapelera ? 'trash' : 'pick') : 'keep'}"),
    future: future,
    builder: (context, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return Center(child: CircularProgressIndicator());
      }
      if (snap.hasError) {
        return _emptyState(
          icon: Icons.error_outline,
          title: context.tr('Error cargando'),
          subtitle: context.tr('Algo falló al leer la base de datos. Cierra y vuelve a abrir la app.'),
        );
      }
      if (!snap.hasData) return Center(child: CircularProgressIndicator());
      final rawItems = snap.data ?? const <Map<String, dynamic>>[];
      // En Favoritos filtramos por el estado real (DB + cache) para que al desmarcar ⭐
      // el item desaparezca al instante, incluso si el FutureBuilder aún muestra datos antiguos.
      final items0 = onlyFavorites ? rawItems.where(_isFav).toList() : rawItems;

      // Filtro por artista (desde la sub-vista "Artistas")
      final fKey = (artistKeyFilter ?? '').trim();
      final items = fKey.isEmpty
          ? items0
          : items0.where((v) => (v['artistKey'] ?? '').toString().trim() == fKey).toList();

      // ✅ En "Vinilos" aplicamos filtros y orden (A–Z, Año, Recientes, Código).
      // En Favoritos/Borrar mantenemos el orden actual para no sorprender (y porque ahí no mostramos
      // la barra de filtros/orden).
      final baseList = (!conBorrar && !onlyFavorites && vista == Vista.lista && _vinylScope == VinylScope.vinilos)
          ? _applyListFiltersAndSort(items)
          : List<Map<String, dynamic>>.from(items);

      // Cache de artistas para autocompletar en el buscador (solo local, sin web).
      // Lo actualizamos desde el snapshot actual para que sea consistente en Vinilos/Favoritos.
      final setA = <String>{};
      for (final v in baseList) {
        final a = (v['artista'] as String?)?.trim() ?? '';
        if (a.isNotEmpty) setA.add(a);
      }
      _artistSuggestions = setA.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      final qNorm = _norm(_localQuery);
      final visibleItems = qNorm.isEmpty
          ? baseList
          : baseList.where((v) => _matchesLocal(v, qNorm)).toList();

      if (visibleItems.isEmpty) {
        // Caso: hay vinilos, pero el filtro/búsqueda no encontró nada.
        if (qNorm.isNotEmpty && items.isNotEmpty) {
          return _emptyState(
            icon: Icons.search_off,
            title: context.tr('Sin resultados'),
            subtitle: context.tr('No encontré coincidencias en tu lista.'),
            actionText: context.tr('Limpiar búsqueda'),
            onAction: () {
              setState(() {
                _localSearchCtrl.clear();
                _localQuery = '';
              });
              FocusScope.of(context).requestFocus(_localSearchFocus);
            },
          );
        }

        if (conBorrar && _borrarPapelera) {
          return _emptyState(
            icon: Icons.delete_sweep_outlined,
            title: context.tr('Papelera vacía'),
            subtitle: context.tr('Aquí aparecerán los vinilos que borres para que puedas recuperarlos.'),
          );
        }
        return _emptyState(
          icon: onlyFavorites ? Icons.star_outline : Icons.library_music_outlined,
          title: onlyFavorites ? context.tr('No hay favoritos') : context.tr('No hay vinilos'),
          subtitle: onlyFavorites
              ? context.tr('Marca un vinilo como favorito y aparecerá aquí.')
              : context.tr('Agrega tu primer vinilo desde Discografía o Buscar.'),
        );
      }

      // 📄 Paginación: 20 vinilos por página (en lista / grid / carátulas).
      final int total = visibleItems.length;
      final int totalPages = (total <= 0) ? 1 : ((total + _pageSize - 1) ~/ _pageSize);
      final int currentStored = _getPageForList(conBorrar: conBorrar, onlyFavorites: onlyFavorites);
      final int page = currentStored.clamp(1, totalPages);
      if (page != currentStored) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _setPageForList(conBorrar: conBorrar, onlyFavorites: onlyFavorites, page: page);
        });
      }
      final int start = (page - 1) * _pageSize;
      final int end = (start + _pageSize < total) ? (start + _pageSize) : total;
      final List<Map<String, dynamic>> pageItems = (total <= 0 || start >= total)
          ? const <Map<String, dynamic>>[]
          : visibleItems.sublist(start, end);

      Widget wrapWithPager(Widget listWidget) {
        final pager = AppPager(
          page: page,
          totalPages: totalPages,
          onPrev: () => _setPageForList(conBorrar: conBorrar, onlyFavorites: onlyFavorites, page: page - 1),
          onNext: () => _setPageForList(conBorrar: conBorrar, onlyFavorites: onlyFavorites, page: page + 1),
        );
        if (totalPages <= 1) return listWidget;
        if (embedInScroll) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [listWidget, pager],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Expanded(child: listWidget), pager],
        );
      }

      if (_viewMode == VinylViewMode.grid) {
        return wrapWithPager(GridView.builder(
          // ⚠️ Esta pantalla vive dentro de un SingleChildScrollView.
          // Sin shrinkWrap/physics el Grid puede quedar sin altura
          // (o lanzar "unbounded height") y verse como "lista vacía".
          shrinkWrap: embedInScroll,
          physics: embedInScroll ? NeverScrollableScrollPhysics() : AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // Un poco más vertical para dar protagonismo a la carátula
            childAspectRatio: 0.68,
          ),
          itemCount: pageItems.length,
          itemBuilder: (context, i) {
            final v = pageItems[i];
            return _gridTile(v, conBorrar: conBorrar);
          },
        ));
      }

      if (_viewMode == VinylViewMode.cover) {
        final w = MediaQuery.of(context).size.width;
        final int cols = ((w / 140).floor()).clamp(2, 5).toInt();
        return wrapWithPager(GridView.builder(
          shrinkWrap: embedInScroll,
          physics: embedInScroll ? NeverScrollableScrollPhysics() : AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.0,
          ),
          itemCount: pageItems.length,
          itemBuilder: (context, i) {
            final v = pageItems[i];
            return _coverOnlyTile(v, conBorrar: conBorrar);
          },
        ));
      }

      // 📚 Cuando se ordena A–Z en "Vinilos", agrupamos por letra (A, B, C...) como en “Contactos”.
      final bool showAlphaHeaders = (!conBorrar && !onlyFavorites && vista == Vista.lista && _vinylScope == VinylScope.vinilos && _sortMode == VinylSortMode.az);
      if (showAlphaHeaders) {
        final rows = <_AlphaRow>[];
        String last = '';
        for (final v in pageItems) {
          final letter = _alphaBucketFromArtist((v['artista'] as String?) ?? '');
          if (letter != last) {
            rows.add(_AlphaRow.header(letter));
            last = letter;
          }
          rows.add(_AlphaRow.item(v));
        }
        return wrapWithPager(ListView.builder(
          shrinkWrap: embedInScroll,
          physics: embedInScroll ? NeverScrollableScrollPhysics() : AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final r = rows[i];
            if (r.isHeader) {
              return _alphaHeader(r.header!);
            }
            return _vinylListCard(r.payload!, conBorrar: conBorrar);
          },
        ));
      }

      return wrapWithPager(ListView.builder(
        // ⚠️ Esta pantalla vive dentro de un SingleChildScrollView.
        // Sin shrinkWrap/physics el ListView puede quedar sin altura
        // y verse como "lista vacía".
        shrinkWrap: embedInScroll,
        physics: embedInScroll ? NeverScrollableScrollPhysics() : AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: pageItems.length,
        itemBuilder: (context, i) {
          final v = pageItems[i];
          return _vinylListCard(v, conBorrar: conBorrar);
        },
      ));
    },
  );
}

  String _viewModeLabel(VinylViewMode m) {
    switch (m) {
      case VinylViewMode.list:
        return 'LISTA';
      case VinylViewMode.grid:
        return 'GRID';
      case VinylViewMode.cover:
        return 'CARÁTULA';
    }
  }

  IconData _viewModeIcon(VinylViewMode m) {
    switch (m) {
      case VinylViewMode.list:
        return Icons.view_list;
      case VinylViewMode.grid:
        return Icons.grid_view;
      case VinylViewMode.cover:
        return Icons.photo;
    }
  }

  VinylViewMode _nextViewMode(VinylViewMode m) {
    final next = (m.index + 1) % VinylViewMode.values.length;
    return VinylViewMode.values[next];
  }

  /// IconButton compacto para AppBar (menos ancho), para que el título no se corte.
  ///
  /// En Vinilos/Favoritos (pantallas con logo grande en el leading) el título
  /// quedaba con muy poco espacio cuando había 2–3 acciones en la fila superior.
  /// Para solucionarlo, usamos botones más compactos y los renderizamos en una
  /// segunda fila (AppBar.bottom).
  Widget _compactAppBarIconButton({
    required String tooltip,
    required Widget icon,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: icon,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 42, height: 42),
    );
  }


  PreferredSizeWidget? _buildAppBar() {
    if (vista == Vista.inicio) return null;

    final localSearchAllowed = (vista == Vista.lista || vista == Vista.favoritos);

    String title;
    switch (vista) {
      case Vista.lista:
        title = 'Vinilos';
        break;
      case Vista.favoritos:
        title = 'Favoritos';
        break;
      case Vista.borrar:
        title = 'Borrar';
        break;
      default:
        title = 'GaBoLP';
    }

    // Importante: el buscador local (Vinilos/Favoritos) NO va en el AppBar.
    // Si lo metemos ahí, queda apretado por el logo/leading y se “corta”.
    // El AppBar queda solo con título; el input se dibuja debajo (en el body)
    // cuando el usuario activa la búsqueda.
    // Un poquito más de aire entre el leading (logo + back) y el título,
    // para que la flecha no quede “pegada” (por ejemplo en “Borrar”).
    final titleWidget = appBarTitleTextScaled(title, padding: const EdgeInsets.only(left: 10));

    // Acciones en una segunda fila para que el título (Vinilos/Favoritos)
    // se vea completo y no quede como "Vi..." / "Fav..." en pantallas angostas.
    final List<Widget> bottomActions = [];

    if (vista == Vista.lista && _vinylScope == VinylScope.vinilos) {
      bottomActions.add(
        _compactAppBarIconButton(
          tooltip: context.tr('Agregar vinilo'),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: _openAddVinylMenu,
        ),
      );
    }
    if (localSearchAllowed && !(vista == Vista.lista && _vinylScope == VinylScope.artistas)) {
      bottomActions.add(
        _compactAppBarIconButton(
          tooltip:
              'Vista: ${_viewModeLabel(_viewMode)} · tocar para ${_viewModeLabel(_nextViewMode(_viewMode))}',
          icon: Icon(_viewModeIcon(_viewMode)),
          onPressed: () async {
            await ViewModeService.setMode(_nextViewMode(_viewMode));
          },
        ),
      );
    }
    if (localSearchAllowed) {
      bottomActions.add(
        _compactAppBarIconButton(
          tooltip: _localSearchActive ? 'Cerrar búsqueda' : 'Buscar en mi lista',
          icon: Icon(_localSearchActive ? Icons.close : Icons.search),
          onPressed: _toggleLocalSearch,
        ),
      );
    }

    final PreferredSizeWidget? bottom = (localSearchAllowed && bottomActions.isNotEmpty)
        ? PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.max,
                children: [
                  for (int i = 0; i < bottomActions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    bottomActions[i],
                  ],
                ],
              ),
            ),
          )
        : null;

    return AppBar(
      toolbarHeight: kAppBarToolbarHeight,
      leadingWidth: appBarLeadingWidthForLogoBack(logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
      leading: Center(
        child: appBarLeadingLogoBack(
          context,
          logoSize: kAppBarLogoSize,
          gap: kAppBarGapLogoBack,
          onBack: () {
            if (localSearchAllowed && _localSearchActive) {
              _toggleLocalSearch();
              return;
            }
            _setVista(Vista.inicio);
          },
        ),
      ),
      title: titleWidget,
      titleSpacing: 12,
      actions: const [],
      bottom: bottom,
    );
  }

  Widget _localSearchBar() {
    // Buscador local con autocompletado de artistas.
    // Se muestra debajo del AppBar (Vinilos/Favoritos) para que se abra completo.
    return SizedBox(
      height: 56,
      child: RawAutocomplete<String>(
        textEditingController: _localSearchCtrl,
        focusNode: _localSearchFocus,
        optionsBuilder: (TextEditingValue value) {
          final q = _norm(value.text);
          if (q.isEmpty) return const Iterable<String>.empty();
          return _artistSuggestions.where((a) => _norm(a).contains(q)).take(8);
        },
        displayStringForOption: (s) => s,
        onSelected: (s) {
          _localSearchCtrl.text = s;
          _localSearchCtrl.selection = TextSelection.collapsed(offset: s.length);
          _onLocalSearchChanged(s);
          setState(() {});
        },
        fieldViewBuilder: (context, ctrl, focusNode, onFieldSubmitted) {
          final cs = Theme.of(context).colorScheme;
          return TextField(
            controller: ctrl,
            focusNode: focusNode,
            onChanged: (v) {
              _onLocalSearchChanged(v);
              if (mounted) setState(() {});
            },
            textAlignVertical: TextAlignVertical.center,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: context.tr('Buscar en tu colección…'),
              filled: true,
              fillColor: cs.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: cs.primary, width: 2),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              // Lupa un poquito más abajo para que el texto se vea completo.
              prefixIcon: Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.search),
              ),
              prefixIconConstraints: BoxConstraints(minWidth: 44, minHeight: 44),
              suffixIcon: (ctrl.text.trim().isNotEmpty)
                  ? IconButton(
                      tooltip: context.tr('Limpiar texto'),
                      icon: Icon(Icons.close, size: 18),
                      onPressed: () {
                        ctrl.clear();
                        setState(() => _localQuery = '');
                        FocusScope.of(context).requestFocus(_localSearchFocus);
                      },
                    )
                  : null,
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          final list = options.toList(growable: false);
          if (list.isEmpty) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 260, maxWidth: 420),
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => Divider(height: 1),
                  itemBuilder: (context, i) {
                    final s = list[i];
                    return ListTile(
                      dense: true,
                      title: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => onSelected(s),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _vinylScopeSelector() {
    // Los labels de SegmentButtons a veces se parten en 2 líneas en pantallas angostas.
    // Forzamos 1 línea + un tamaño un poco más compacto para que se lean completos.
    Widget _segLabel(String s) => Text(
          context.tr(s),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        );

    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<VinylScope>(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: MaterialStatePropertyAll(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          padding: MaterialStatePropertyAll(
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
        ),
        segments: <ButtonSegment<VinylScope>>[
          ButtonSegment(
            value: VinylScope.vinilos,
            label: _segLabel('Vinilos'),
            icon: Icon(Icons.library_music_outlined),
          ),
          ButtonSegment(
            value: VinylScope.artistas,
            label: _segLabel('Artistas'),
            icon: Icon(Icons.groups_outlined),
          ),
          ButtonSegment(
            value: VinylScope.canciones,
            label: _segLabel('Canciones'),
            icon: Icon(Icons.favorite_outline),
          ),
        ],
        selected: <VinylScope>{_vinylScope},
        onSelectionChanged: (s) {
          if (s.isEmpty) return;
          _setVinylScope(s.first);
        },
        showSelectedIcon: false,
      ),
    );
  }

  Widget _artistFilterChipBar() {
    final name = (_artistFilterName ?? '').trim();
    if (_artistFilterKey == null || _artistFilterKey!.trim().isEmpty || name.isEmpty) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: InputChip(
        label: Text(
          AppStrings.labeled(context, 'Artista', name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onDeleted: () {
          setState(() {
            _artistFilterKey = null;
            _artistFilterName = null;
          });
        },
      ),
    );
  }

  bool _matchesArtistSummary(Map<String, dynamic> a, String qNorm) {
    if (qNorm.isEmpty) return true;
    final name = _norm((a['artista'] ?? '').toString());
    final country = _norm((a['country'] ?? '').toString());
    final total = _norm((a['total'] ?? '').toString());
    return name.contains(qNorm) || country.contains(qNorm) || total.contains(qNorm);
  }

  Widget _artistSummaryList({bool embedInScroll = true}) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('artists_summary'),
      future: _futureArtists,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _emptyState(
            icon: Icons.error_outline,
            title: 'Error cargando artistas',
            subtitle: 'No pude leer el resumen por artista. Cierra y vuelve a abrir la app.',
          );
        }
        final rows = snap.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty) {
          return _emptyState(
            icon: Icons.groups_outlined,
            title: context.tr('Sin artistas aún'),
            subtitle: context.tr('Cuando agregues vinilos, aquí verás tu colección agrupada por artista.'),
          );
        }

        // Autocomplete: en "Artistas" sugerimos nombres de artista.
        final setA = <String>{};
        for (final r in rows) {
          final n = (r['artista'] ?? '').toString().trim();
          if (n.isNotEmpty) setA.add(n);
        }
        _artistSuggestions = setA.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        final qNorm = _norm(_localQuery);
        final visible0 = qNorm.isEmpty ? rows : rows.where((a) => _matchesArtistSummary(a, qNorm)).toList();

        if (visible0.isEmpty) {
          return _emptyState(
            icon: Icons.search_off,
            title: context.tr('Sin resultados'),
            subtitle: context.tr('No encontré artistas que coincidan con tu búsqueda.'),
          );
        }

        // Orden A–Z + encabezados por letra (A, B, C...).
        final visible = List<Map<String, dynamic>>.from(visible0)
          ..sort((x, y) {
            final ax = _normalizeArtistForSort((x['artista'] ?? '').toString());
            final ay = _normalizeArtistForSort((y['artista'] ?? '').toString());
            return ax.compareTo(ay);
          });

        final alphaRows = <_AlphaRow>[];
        String last = '';
        for (final a in visible) {
          final letter = _alphaBucketFromArtist((a['artista'] ?? '').toString());
          if (letter != last) {
            alphaRows.add(_AlphaRow.header(letter));
            last = letter;
          }
          alphaRows.add(_AlphaRow.item(a));
        }

        return ListView.builder(
          shrinkWrap: embedInScroll,
          physics: embedInScroll ? NeverScrollableScrollPhysics() : AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: alphaRows.length,
          itemBuilder: (context, i) {
            final r = alphaRows[i];
            if (r.isHeader) {
              return _alphaHeader(r.header!);
            }
            final a = r.payload!;
            final name = (a['artista'] ?? '').toString().trim();
            final key = (a['artistKey'] ?? '').toString().trim();
            final country = (a['country'] ?? '').toString().trim();
            final total = _asInt(a['total']);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name.isEmpty ? '—' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 8),
                      SizedBox(
                        width: 54,
                        child: Text(
                          country.isEmpty ? '—' : country,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.70),
                        ),
                        child: Text(
                          total.toString(),
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    if (key.isEmpty) return;
                    setState(() {
                      _artistFilterKey = key;
                      _artistFilterName = name;
                    });
                    _setVinylScope(VinylScope.vinilos);
                  },
                ),
                Divider(height: 1),
              ],
            );
          },
        );
      },
    );
  }

  Widget? _buildFab() {
    if (vista == Vista.lista || vista == Vista.favoritos || vista == Vista.borrar) {
      // Solo icono (sin texto "Inicio")
      return FloatingActionButton(
        onPressed: () => _setVista(Vista.inicio),
        tooltip: context.tr('Inicio'),
        child: Icon(Icons.home),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      appBar: _buildAppBar(),
      floatingActionButton: _buildFab(),
      body: Container(
        // ✅ Respeta el “Fondo (1–10)” y la paleta global (no overlays fijos).
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              bg,
              Color.lerp(bg, cs.surfaceContainerHighest, 0.10) ?? bg,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
              key: ValueKey(vista),
              padding: const EdgeInsets.all(16),
              child: (vista == Vista.lista || vista == Vista.favoritos || vista == Vista.borrar)
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 🔁 Sub-vista: Vinilos | Artistas (solo en "Vinilos")
                        if (vista == Vista.lista) ...[
                          SizedBox(height: 8),
                          _vinylScopeSelector(),
                          SizedBox(height: 12),
                        ],

                        // 🔎 Buscador local (debajo del AppBar) para que se abra completo.
                        if ((vista == Vista.lista || vista == Vista.favoritos) && _localSearchActive) ...[
                          SizedBox(height: 8),
                          _localSearchBar(),
                          SizedBox(height: 12),
                        ],

                        // 🏷️ Filtro de artista (cuando vienes desde "Artistas")
                        if (vista == Vista.lista && _vinylScope == VinylScope.vinilos) ...[
                          _artistFilterChipBar(),
                          if (_artistFilterKey != null && (_artistFilterName ?? '').trim().isNotEmpty)
                            SizedBox(height: 12),
                        ],
                        if (vista == Vista.borrar) ...[
                          vistaBorrar(embedInScroll: false),
                          SizedBox(height: 12),
                          Expanded(
                            child: listaCompleta(
                              conBorrar: true,
                              onlyFavorites: false,
                              embedInScroll: false,
                            ),
                          ),
                        ],
                        if (vista == Vista.lista)
                          Expanded(
                            child: _vinylScope == VinylScope.artistas
                                ? _artistSummaryList(embedInScroll: false)
                                : (_vinylScope == VinylScope.canciones
                                    ? const LikedTracksView()
                                    : listaCompleta(
                                        conBorrar: false,
                                        onlyFavorites: false,
                                        embedInScroll: false,
                                        artistKeyFilter: _artistFilterKey,
                                      )),
                          ),
                        if (vista == Vista.favoritos)
                          Expanded(
                            child: listaCompleta(
                              conBorrar: false,
                              onlyFavorites: true,
                              embedInScroll: false,
                            ),
                          ),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (vista == Vista.inicio) ...[
                            encabezadoInicio(),
                            SizedBox(height: 14),
                            botonesInicio(),
                          ],
                        ],
                      ),
                    ),
          ),
      ),
    ));
  }
}