import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
import '../services/discography_service.dart';
import '../services/metadata_service.dart';
import '../services/vinyl_add_service.dart';
import '../services/backup_service.dart';
import '../services/view_mode_service.dart';
import '../services/app_theme_service.dart';
import 'discography_screen.dart';
import 'settings_screen.dart';
import 'vinyl_detail_sheet.dart';
import 'wishlist_screen.dart';

enum Vista { inicio, buscar, lista, favoritos, borrar }

enum VinylSortMode { az, yearDesc, recent }

String vinylSortLabel(VinylSortMode m) {
  switch (m) {
    case VinylSortMode.az:
      return 'A–Z';
    case VinylSortMode.yearDesc:
      return 'Año';
    case VinylSortMode.recent:
      return 'Recientes';
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

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
  // ⭐ Cache local para favoritos (cambio instantáneo)
  final Map<int, bool> _favCache = {};

  // 🔎 Filtros + orden (solo para "Vinilos")
  String _filterArtistQ = '';
  String _filterGenreQ = '';
  String _filterCountryQ = '';
  int? _filterYearFrom;
  int? _filterYearTo;
  VinylSortMode _sortMode = VinylSortMode.recent;

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

  // 🗑️ En vista borrar: false = 'Para borrar' (colección), true = 'Papelera' (recuperar/eliminar definitivo)
  bool _borrarPapelera = false;

  bool _gridView = false;
  late final VoidCallback _gridListener;

  // ✅ Contadores para badges en los botones del inicio
  Future<Map<String, int>>? _homeCountsFuture;
  Map<String, int> _homeCounts = const {'all': 0, 'fav': 0, 'wish': 0};

  // ✅ Cache de la lista completa (evita recargar en cada setState y permite favorito instantáneo)
  late Future<List<Map<String, dynamic>>> _futureAll;

  // ✅ Cache de favoritos / papelera (evita recargar en cada setState)
  late Future<List<Map<String, dynamic>>> _futureFav;
  late Future<List<Map<String, dynamic>>> _futureTrash;

  final artistaCtrl = TextEditingController();
  final albumCtrl = TextEditingController();
  final yearCtrl = TextEditingController();

  // ✅ Focus dedicado para poder abrir el buscador desde Home con un tap.
  final FocusNode _artistFocus = FocusNode();

  // 🔎 Búsqueda local (solo en tu colección) para Vinilos/Favoritos
  bool _localSearchActive = false;
  final TextEditingController _localSearchCtrl = TextEditingController();
  final FocusNode _localSearchFocus = FocusNode();
  Timer? _debounceLocalSearch;
  String _localQuery = '';

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
    // ✅ Vista grid/list instantánea (notifier en memoria)
    _gridView = ViewModeService.gridNotifier.value;
    _gridListener = () {
      if (!mounted) return;
      setState(() => _gridView = ViewModeService.gridNotifier.value);
    };
    ViewModeService.gridNotifier.addListener(_gridListener);
    _refreshHomeCounts();
    _futureAll = VinylDb.instance.getAll();
    _futureFav = VinylDb.instance.getFavorites();
    _futureTrash = VinylDb.instance.getTrash();
  }

  Future<void> _refreshHomeCounts() async {

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

  
void _reloadAllData() {
  if (!mounted) return;
  setState(() {
    _favCache.clear();
    _futureAll = VinylDb.instance.getAll();
    _futureFav = VinylDb.instance.getFavorites();
    _futureTrash = VinylDb.instance.getTrash();
    });
  _refreshHomeCounts();
}

Future<void> _loadViewMode() async {

    // Mantenemos por compatibilidad, pero hoy la app usa el notifier.
    final g = await ViewModeService.isGridEnabled();
    if (!mounted) return;
    ViewModeService.gridNotifier.value = g;
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

  void _onLocalSearchChanged(String _) {
    // Rebuild inmediato (para el botón de limpiar en el AppBar),
    // pero filtramos con debounce para no recalcular toda la lista a cada tecla.
    if (mounted) setState(() {});
    _debounceLocalSearch?.cancel();
    _debounceLocalSearch = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() => _localQuery = _localSearchCtrl.text);
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

  bool _matchesLocal(Map<String, dynamic> v, String qNorm) {
    if (qNorm.isEmpty) return true;

    final artista = _norm((v['artista'] ?? '').toString());
    final album = _norm((v['album'] ?? '').toString());
    final genre = _norm((v['genre'] ?? '').toString());
    final country = _norm((v['country'] ?? '').toString());
    final year = _norm((v['year'] ?? '').toString());
    final numero = _norm((v['numero'] ?? '').toString());

    if (artista.contains(qNorm)) return true;
    if (album.contains(qNorm)) return true;
    if (numero.contains(qNorm)) return true;
    if (year.contains(qNorm)) return true;
    if (genre.contains(qNorm)) return true;
    if (country.contains(qNorm)) return true;

    return false;
  }

  @override
  void dispose() {
    _debounceArtist?.cancel();
    _debounceAlbum?.cancel();
    _debounceLocalSearch?.cancel();
    ViewModeService.gridNotifier.removeListener(_gridListener);
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
            child: VinylDetailSheet(vinyl: v),
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

if (cp.startsWith('http://') || cp.startsWith('https://')) {
	  final cache = (size * 2).round().clamp(64, 512);
	  return ClipRRect(
	    borderRadius: BorderRadius.circular(8),
	    child: Container(
	      alignment: Alignment.center,
	      color: Colors.black12,
	      child: Image.network(
	        cp,
	        width: size,
	        height: size,
	        fit: fit,
	      cacheWidth: cache,
	      cacheHeight: cache,
	      errorBuilder: (_, __, ___) => const Icon(Icons.album),
	      loadingBuilder: (context, child, progress) {
	        if (progress == null) return child;
	        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
	      },
	      ),
	    ),
	  );
}
    if (cp.isNotEmpty && _fileExistsCached(cp)) {
      final f = File(cp);
      final cache = (size * 2).round().clamp(64, 512);
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          alignment: Alignment.center,
          color: Colors.black12,
          child: Image.file(
            f,
            width: size,
            height: size,
            fit: fit,
            cacheWidth: cache,
            cacheHeight: cache,
          ),
        ),
      );
    }
    return const Icon(Icons.album);
  }

  /// Carátula para cards tipo Grid.
  ///
  /// En Grid priorizamos que la carátula se vea **completa** (sin recorte).
  /// Por eso el `fit` por defecto es [BoxFit.contain].
  Widget _gridCover(Map<String, dynamic> v, {BoxFit fit = BoxFit.contain}) {
    final cp = (v['coverPath'] as String?)?.trim() ?? '';

    if (cp.startsWith('http://') || cp.startsWith('https://')) {
      return Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: Image.network(
          cp,
          fit: fit,
          cacheWidth: 700,
          cacheHeight: 700,
          errorBuilder: (_, __, ___) => const Icon(Icons.album, size: 48),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          },
        ),
      );
    }

    if (cp.isNotEmpty && _fileExistsCached(cp)) {
      final f = File(cp);
      return Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: Image.file(
          f,
          fit: fit,
          cacheWidth: 700,
          cacheHeight: 700,
        ),
      );
    }

    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: const Icon(Icons.album, size: 48),
    );
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

  Widget _vinylListCard(Map<String, dynamic> v, {required bool conBorrar}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final year = ((v['year'] ?? '').toString().trim());
    final genre = ((v['genre'] ?? '').toString().trim());
    final artista = ((v['artista'] ?? '').toString().trim());
    final album = ((v['album'] ?? '').toString().trim());
    final fav = _isFav(v);

    final actions = <Widget>[
      if (!conBorrar)
        IconButton(
          tooltip: fav ? 'Quitar favorito' : 'Marcar favorito',
          icon: Icon(
            fav ? Icons.star : Icons.star_border,
            color: fav ? Colors.amber : cs.onSurfaceVariant,
          ),
          onPressed: () => _toggleFavorite(v),
        ),
      if (conBorrar && !_borrarPapelera)
        IconButton(
          tooltip: 'Enviar a papelera',
          icon: Icon(Icons.delete_outline, color: cs.onSurfaceVariant),
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
        IconButton(
          tooltip: 'Restaurar',
          icon: Icon(Icons.restore_from_trash, color: cs.onSurfaceVariant),
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
        IconButton(
          tooltip: 'Eliminar definitivo',
          icon: Icon(Icons.delete_forever, color: cs.onSurfaceVariant),
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                width: 98,
                height: 98,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        color: cs.surfaceVariant.withOpacity(isDark ? 0.30 : 0.60),
                        child: _leadingCover(v, size: 98, fit: BoxFit.contain),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: _numeroBadge(context, v['numero'], compact: true),
                    ),
                  ],
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
                        children: [
                          _metaPill(context, year),
                          _metaPill(context, genre),
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
              if (actions.isNotEmpty)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: actions
                      .map((w) => Padding(padding: const EdgeInsets.only(bottom: 2), child: w))
                      .toList(growable: false),
                ),
            ],
          ),
        ),
      ),
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
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
          tooltip: 'Enviar a papelera',
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
            tooltip: 'Restaurar',
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
            tooltip: 'Eliminar definitivo',
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
                    color: cs.surfaceVariant.withOpacity(isDark ? 0.30 : 0.60),
                    child: _gridCover(v, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                artista.isEmpty ? '—' : artista,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                album.isEmpty ? '—' : album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Row(
                children: [
                  _numeroBadge(context, v['numero'], compact: true),
                  const SizedBox(width: 8),
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
                  const SizedBox(height: 8),
                  Text(
                    artista,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                          album,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                  const SizedBox(height: 4),
                  Text(year.isEmpty ? '—' : year),
                ],
              ),
            ),

            // 🔢 número arriba derecha
            Positioned(
              right: 6,
              top: 6,
              child: _numeroBadge(context, v['numero'], compact: true),
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
                  constraints: const BoxConstraints(),

                  icon: const Icon(Icons.delete),
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

    _debounceArtist = Timer(const Duration(milliseconds: 350), () async {
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

    _debounceAlbum = Timer(const Duration(milliseconds: 220), () async {
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
    );

    snack(res.message);
    if (!res.ok) return;

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
          return const SizedBox(width: 90, height: 70);
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
            style: const TextStyle(
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
    return const Positioned(
      right: 10,
      bottom: 8,
      child: IgnorePointer(
        child: Text(
          'GaBoLP',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget botonesInicio() {
    // ✅ Opción C: Home tipo “app de música” con secciones.
    // Mantiene EXACTAMENTE la misma lógica/callbacks.

    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isDark = t.brightness == Brightness.dark;

    // ✅ Contadores (ya calculados en _homeCounts)
    final all = _homeCounts['all'] ?? 0;
    final fav = _homeCounts['fav'] ?? 0;
    final wish = _homeCounts['wish'] ?? 0;

    void openBuscar() {
      // ✅ UX premium: al abrir el buscador desde Home, enfocamos Artista.
      _setVista(Vista.buscar);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        FocusScope.of(context).requestFocus(_artistFocus);
      });
    }

	Widget _statPill({required String label, required int value}) {
  final pillBg = cs.surface;
  final pillBorder = cs.outline.withOpacity(isDark ? 0.90 : 1.00);
  final labelColor = cs.onSurface.withOpacity(isDark ? 0.78 : 0.72);

  final badgeBg = isDark ? Colors.black : cs.primary;
  final badgeFg = isDark ? Colors.white : cs.onPrimary;

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: pillBg,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: pillBorder),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: labelColor, fontWeight: FontWeight.w800, fontSize: 12)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: badgeBg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: pillBorder),
          ),
          child: Text(
            '$value',
            style: TextStyle(color: badgeFg, fontSize: 11, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    ),
  );
}

	Widget _topNavPill({required String label, required VoidCallback onTap}) {
	  final bg = cs.surface;
	  final border = cs.outline.withOpacity(isDark ? 0.90 : 1.00);
	  final fg = cs.onSurface;
	  return InkWell(
	    onTap: onTap,
	    borderRadius: BorderRadius.circular(14),
	    child: Container(
	      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
	      decoration: BoxDecoration(
	        color: bg,
	        borderRadius: BorderRadius.circular(14),
	        border: Border.all(color: border),
	      ),
	      child: Center(
	        child: Text(
	          label,
	          maxLines: 1,
	          overflow: TextOverflow.ellipsis,
	          style: t.textTheme.labelLarge?.copyWith(
	            fontWeight: FontWeight.w900,
	            letterSpacing: -0.2,
	            color: fg,
	          ),
	        ),
	      ),
	    ),
	  );
	}

Widget sectionTitle(String title, {String? subtitle}) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t.textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: t.textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.70), fontWeight: FontWeight.w600),
              ),
            ]
          ],
        ),
      );
    }

    Widget quickAction({required IconData icon, required String label, required VoidCallback onTap}) {
      final bg = cs.surfaceVariant;
      final border = cs.outline.withOpacity(isDark ? 0.90 : 1.00);
      final fg = cs.onSurface;

      return ActionChip(
        onPressed: onTap,
        label: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: fg)),
        avatar: Icon(icon, size: 18, color: fg),
        backgroundColor: bg,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      );
    }


    
    Widget menuRow({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
      final themeId = AppThemeService.themeNotifier.value;

      // ✅ Diseño 2 (B3): tarjetas grandes claras, ícono con fondo suave y más “premium”.
      if (themeId == 2) {
        return Card(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(26),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Icon(icon, size: 24, color: cs.onSurface),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: t.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant.withOpacity(0.85), fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant.withOpacity(0.85)),
                ],
              ),
            ),
          ),
        );
      }

      // ✅ Diseño 3 (B1): minimal oscuro, filas compactas con borde fino (casi “lista”).
      if (themeId == 3) {
        return Card(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, size: 22, color: t.colorScheme.onSurface),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: t.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant.withOpacity(0.75), fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant.withOpacity(0.75)),
                ],
              ),
            ),
          ),
        );
      }

      // ✅ Diseño 1 (Vinyl Pro): el estilo actual (tarjeta con ícono en caja).
      return Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outline.withOpacity(isDark ? 0.90 : 1.00)),
                  ),
                  child: Icon(icon, size: 22, color: t.colorScheme.onSurface),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: t.textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.70)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 20, color: cs.onSurface.withOpacity(0.55)),
              ],
            ),
          ),
        ),
      );
    }


  Widget recentGrid() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _futureAll,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _emptyState(
            icon: Icons.wifi_off,
            title: 'Sin conexión',
            subtitle: 'No pude cargar tus vinilos ahora. Intenta de nuevo.',
            actionText: 'Reintentar',
            onAction: _reloadAllData,
          );
        }

        final items = (snap.data ?? const <Map<String, dynamic>>[]).toList();
        if (items.isEmpty) {
          return Text(
            'Aún no has agregado vinilos. Usa “Buscar” o “Discografías”.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.70),
                  fontWeight: FontWeight.w600,
                ),
          );
        }

        // 4 últimos por id descendente (visual)
        items.sort((a, b) {
          final ia = (a['id'] is int) ? a['id'] as int : 0;
          final ib = (b['id'] is int) ? b['id'] as int : 0;
          return ib.compareTo(ia);
        });
        final top = items.take(4).toList();

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: top.length,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          itemBuilder: (_, i) {
            final v = top[i];
            final artista = ((v['artista'] ?? '').toString().trim());
            final album = ((v['album'] ?? '').toString().trim());
            final year = ((v['year'] ?? '').toString().trim());

            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: cs.outlineVariant.withOpacity(isDark ? 0.55 : 0.35)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _openDetail(v),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 1.10,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Container(
                              color: cs.surfaceVariant.withOpacity(isDark ? 0.30 : 0.60),
                              child: _gridCover(v, fit: BoxFit.contain),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            bottom: 10,
                            child: _numeroBadge(context, v['numero'], compact: true),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            artista.isEmpty ? '—' : artista,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            album.isEmpty ? '—' : album,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            year.isEmpty ? '—' : year,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: cs.onSurface.withOpacity(0.70),
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
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



    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),

        // HERO
Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: cs.outline.withOpacity(isDark ? 0.90 : 1.00)),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark ? [cs.surfaceVariant, cs.surface] : [cs.surface, cs.surfaceVariant],
    ),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
	      Row(
	        children: [
	          // Marca pequeña en una esquina
	          Row(
	            mainAxisSize: MainAxisSize.min,
	            children: [
	              SizedBox(
	                width: 16,
	                height: 16,
	                child: CustomPaint(
	                  painter: _DiamondLogoPainter(
	                    cs.onSurface.withOpacity(isDark ? 0.92 : 0.85),
	                  ),
	                ),
	              ),
	              const SizedBox(width: 6),
	              Text(
	                'GaBoLP',
	                style: t.textTheme.labelLarge?.copyWith(
	                  fontWeight: FontWeight.w900,
	                  letterSpacing: -0.2,
	                  color: cs.onSurface.withOpacity(isDark ? 0.92 : 0.85),
	                ),
	              ),
	            ],
	          ),
	          const Spacer(),
	          IconButton(
	            tooltip: 'Actualizar',
	            onPressed: _reloadAllData,
	            icon: Icon(Icons.refresh, color: cs.onSurface),
	          ),
	        ],
	      ),
	      const SizedBox(height: 10),
	
	      // Navegación principal en una sola línea
	      Row(
	        children: [
	          Expanded(
	            child: _topNavPill(
	              label: 'Colección',
	              onTap: () {
	                _reloadAllData();
	                if (!mounted) return;
	                _setVista(Vista.lista);
	              },
	            ),
	          ),
	          const SizedBox(width: 8),
	          Expanded(
	            child: _topNavPill(
	              label: 'Favoritos',
	              onTap: () {
	                _reloadAllData();
	                if (!mounted) return;
	                _setVista(Vista.favoritos);
	              },
	            ),
	          ),
	          const SizedBox(width: 8),
	          Expanded(
	            child: _topNavPill(
	              label: 'Deseos',
	              onTap: () {
	                Navigator.push(context, MaterialPageRoute(builder: (_) => const WishlistScreen())).then((_) {
	                  if (!mounted) return;
	                  _reloadAllData();
	                });
	              },
	            ),
	          ),
	        ],
	      ),
	      const SizedBox(height: 12),

	      // 🔎 Barra de búsqueda “falsa” (abre la vista Buscar y enfoca Artista)
	      InkWell(
	        onTap: openBuscar,
	        borderRadius: BorderRadius.circular(16),
	        child: Container(
	          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
	          decoration: BoxDecoration(
	            color: cs.surfaceVariant.withOpacity(isDark ? 0.18 : 0.75),
	            borderRadius: BorderRadius.circular(16),
	            border: Border.all(color: cs.outline.withOpacity(isDark ? 0.75 : 1.0)),
	          ),
	          child: Row(
	            children: [
	              Icon(Icons.search, size: 20, color: cs.onSurface.withOpacity(0.85)),
	              const SizedBox(width: 10),
	              Expanded(
	                child: Text(
	                  'Buscar artista o álbum…',
	                  style: t.textTheme.bodyMedium?.copyWith(
	                    color: cs.onSurface.withOpacity(0.72),
	                    fontWeight: FontWeight.w700,
	                  ),
	                ),
	              ),
	              Icon(Icons.keyboard_arrow_right, color: cs.onSurface.withOpacity(0.55)),
	            ],
	          ),
	        ),
	      ),

	      const SizedBox(height: 12),

      // mini stats
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _statPill(label: 'Vinilos', value: all),
          _statPill(label: 'Favoritos', value: fav),
          _statPill(label: 'Deseos', value: wish),
        ],
      ),

      const SizedBox(height: 12),

      // acciones rápidas
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          quickAction(icon: Icons.search, label: 'Buscar', onTap: openBuscar),
          quickAction(
            icon: Icons.library_music,
            label: 'Discografías',
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscographyScreen())).then((_) {
                if (!mounted) return;
                _reloadAllData();
              });
            },
          ),
          quickAction(
            icon: Icons.settings,
            label: 'Ajustes',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
    ],
  ),
),

sectionTitle('Colección'
, subtitle: 'Accede rápido a tus listas.'),
        menuRow(
          icon: Icons.list,
          title: 'Vinilos',
          subtitle: 'Todos tus LPs guardados',          onTap: () {
            _reloadAllData();
            if (!mounted) return;
            _setVista(Vista.lista);
          },
        ),
        menuRow(
          icon: Icons.star,
          title: 'Favoritos',
          subtitle: 'Tu selección destacada',          onTap: () {
            _reloadAllData();
            if (!mounted) return;
            _setVista(Vista.favoritos);
          },
        ),
        menuRow(
          icon: Icons.shopping_cart,
          title: 'Deseos',
          subtitle: 'Pendientes por comprar',          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const WishlistScreen())).then((_) {
              if (!mounted) return;
              _reloadAllData();
            });
          },
        ),
        menuRow(
          icon: Icons.delete_outline,
          title: 'Borrar',
          subtitle: 'Eliminar de tu lista',
          onTap: () {
            _borrarPapelera = false;
            _reloadAllData();
            if (!mounted) return;
            _setVista(Vista.borrar);
          },
        ),

        sectionTitle('Últimos agregados', subtitle: 'Acceso rápido a lo último que guardaste.'),
        recentGrid(),
        const SizedBox(height: 10),
      ],
    );
  }



Widget vistaBorrar() {
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
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Para borrar'),
                  )
                : ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Para borrar'),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _borrarPapelera
                ? ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.restore),
                    label: const Text('Papelera'),
                  )
                : OutlinedButton.icon(
                    onPressed: () async {
                      // Carga rápida para mostrar papelera
                      setState(() {
                        _borrarPapelera = true;
                        _futureTrash = VinylDb.instance.getTrash();
                      });
                    },
                    icon: const Icon(Icons.restore),
                    label: const Text('Papelera'),
                  ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      listaCompleta(conBorrar: true, onlyFavorites: false),
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
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
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
            labelText: 'Artista',
            suffixIcon: showXArtist
                ? IconButton(
                    tooltip: 'Limpiar',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _limpiarArtista,
                  )
                : null,
          ),
        ),
        if (buscandoArtistas)
          const Padding(
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
                subtitle: c.isEmpty ? null : Text('País: $c'),
                onTap: () => _pickArtist(a),
              );
            },
          ),

        const SizedBox(height: 10),

        TextField(
          controller: albumCtrl,
          onChanged: _onAlbumChanged,
          decoration: InputDecoration(
            labelText: 'Álbum',
            suffixIcon: showXAlbum
                ? IconButton(
                    tooltip: 'Limpiar',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _limpiarAlbum,
                  )
                : null,
          ),
        ),
        if (buscandoAlbums)
          const Padding(
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
                subtitle: y.isEmpty ? null : Text('Año: $y'),
                onTap: () => _pickAlbum(al),
              );
            },
          ),

        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: buscar,
          child: const Text('Buscar'),
        ),

        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _cancelarBusqueda,
          child: const Text('Limpiar'),
        ),

        // ✅ Si lo tienes en la colección
        if (resultados.isNotEmpty) ...[
          const SizedBox(height: 12),
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
                Text(
                  'Ya lo tienes en tu colección:',
                  style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
                ),
                const SizedBox(height: 8),
                ...resultados.map((v) {
                  final y = (v['year'] as String?)?.trim() ?? '';
                  final yTxt = y.isEmpty ? '' : ' ($y)';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        _leadingCover(v),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${v['numero']} — ${v['artista']} — ${v['album']}$yTxt',
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
          const SizedBox(height: 12),
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
                Text('Agregar este vinilo', style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
                const SizedBox(height: 8),
                if (autocompletando) const LinearProgressIndicator(),
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
                                child: const Icon(Icons.album, size: 40),
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
                                  child: const Icon(Icons.broken_image),
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Artista: ${p.artist}', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
                            Text('Álbum: ${p.album}', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
                            const SizedBox(height: 6),
                            Text('Año: ${p.year ?? '—'}', style: TextStyle(color: cs.onSurface.withOpacity(0.72), fontWeight: FontWeight.w600)),
                            Text('Género: ${p.genre ?? '—'}', style: TextStyle(color: cs.onSurface.withOpacity(0.72), fontWeight: FontWeight.w600)),
                            Text('País: ${p.country ?? '—'}', style: TextStyle(color: cs.onSurface.withOpacity(0.72), fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // año editable (opcional)
                  TextField(
                    controller: yearCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Año (opcional: corregir)',
                      filled: true,
                      fillColor: cs.surfaceVariant.withOpacity(isDark ? 0.14 : 0.65),
                    ),
                    style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: agregar,
                    child: const Text('Agregar vinilo'),
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
          final c1 = safeCmp(ax, ay);
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
                        const Icon(Icons.tune),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('Filtros')),
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
                          child: const Text('Limpiar'),
                        )
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Artista o álbum'),
                      controller: TextEditingController(text: tArtist),
                      onChanged: (v) => setLocal(() => tArtist = v),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Año desde'),
                            controller: TextEditingController(text: tFrom),
                            onChanged: (v) => setLocal(() => tFrom = v),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Año hasta'),
                            controller: TextEditingController(text: tTo),
                            onChanged: (v) => setLocal(() => tTo = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Género (contiene)'),
                      controller: TextEditingController(text: tGenre),
                      onChanged: (v) => setLocal(() => tGenre = v),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: const InputDecoration(labelText: 'País (contiene)'),
                      controller: TextEditingController(text: tCountry),
                      onChanged: (v) => setLocal(() => tCountry = v),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 10),
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
                            child: const Text('Aplicar'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
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
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
            if (actionText != null && onAction != null) ...[
              const SizedBox(height: 14),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _hasAnyFilter ? '$shown de $total' : '$total',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (_hasAnyFilter)
            IconButton(
              tooltip: 'Quitar filtros',
              onPressed: () => setState(() {
                _filterArtistQ = '';
                _filterGenreQ = '';
                _filterCountryQ = '';
                _filterYearFrom = null;
                _filterYearTo = null;
              }),
              icon: const Icon(Icons.filter_alt_off),
            ),
          IconButton(
            tooltip: 'Filtros',
            onPressed: _openVinylFiltersSheet,
            icon: Icon(_hasAnyFilter ? Icons.filter_alt : Icons.filter_alt_outlined),
          ),
          PopupMenuButton<VinylSortMode>(
            tooltip: 'Ordenar',
            initialValue: _sortMode,
            onSelected: (m) => setState(() => _sortMode = m),
            itemBuilder: (_) => [
              PopupMenuItem(value: VinylSortMode.recent, child: Text('Recientes')),
              PopupMenuItem(value: VinylSortMode.az, child: Text('A–Z')),
              PopupMenuItem(value: VinylSortMode.yearDesc, child: Text('Año')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.sort),
                  const SizedBox(width: 6),
                  Text(vinylSortLabel(_sortMode)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

Widget listaCompleta({required bool conBorrar, required bool onlyFavorites}) {
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
        return const Center(child: CircularProgressIndicator());
      }
      if (snap.hasError) {
        return _emptyState(
          icon: Icons.error_outline,
          title: 'Error cargando',
          subtitle: 'Algo falló al leer la base de datos. Cierra y vuelve a abrir la app.',
        );
      }
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final rawItems = snap.data ?? const <Map<String, dynamic>>[];
      // En Favoritos filtramos por el estado real (DB + cache) para que al desmarcar ⭐
      // el item desaparezca al instante, incluso si el FutureBuilder aún muestra datos antiguos.
      final items = onlyFavorites ? rawItems.where(_isFav).toList() : rawItems;

      final qNorm = _norm(_localQuery);
      final visibleItems = qNorm.isEmpty
          ? items
          : items.where((v) => _matchesLocal(v, qNorm)).toList();

      if (visibleItems.isEmpty) {
        // Caso: hay vinilos, pero el filtro/búsqueda no encontró nada.
        if (qNorm.isNotEmpty && items.isNotEmpty) {
          return _emptyState(
            icon: Icons.search_off,
            title: 'Sin resultados',
            subtitle: 'No encontré coincidencias en tu lista.',
            actionText: 'Limpiar búsqueda',
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
            title: 'Papelera vacía',
            subtitle: 'Aquí aparecerán los vinilos que borres para que puedas recuperarlos.',
          );
        }
        return _emptyState(
          icon: onlyFavorites ? Icons.star_outline : Icons.library_music_outlined,
          title: onlyFavorites ? 'No hay favoritos' : 'No hay vinilos',
          subtitle: onlyFavorites
              ? 'Marca un vinilo como favorito y aparecerá aquí.'
              : 'Agrega tu primer vinilo desde Discografía o Buscar.',
        );
      }


      if (_gridView) {
        return GridView.builder(
          // ⚠️ Esta pantalla vive dentro de un SingleChildScrollView.
          // Sin shrinkWrap/physics el Grid puede quedar sin altura
          // (o lanzar "unbounded height") y verse como "lista vacía".
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // Un poco más vertical para dar protagonismo a la carátula
            childAspectRatio: 0.68,
          ),
          itemCount: visibleItems.length,
          itemBuilder: (context, i) {
            final v = visibleItems[i];
            return _gridTile(v, conBorrar: conBorrar);
          },
        );
      }

      return ListView.builder(
        // ⚠️ Esta pantalla vive dentro de un SingleChildScrollView.
        // Sin shrinkWrap/physics el ListView puede quedar sin altura
        // y verse como "lista vacía".
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: visibleItems.length,
        itemBuilder: (context, i) {
          final v = visibleItems[i];
          return _vinylListCard(v, conBorrar: conBorrar);
        },
      );
    },
  );
}

  PreferredSizeWidget? _buildAppBar() {
    if (vista == Vista.inicio) return null;

    final localSearchAllowed = (vista == Vista.lista || vista == Vista.favoritos);

    String title;
    switch (vista) {
      case Vista.buscar:
        title = 'Buscar vinilos';
        break;
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

    final titleWidget = (localSearchAllowed && _localSearchActive)
        ? TextField(
            controller: _localSearchCtrl,
            focusNode: _localSearchFocus,
            onChanged: _onLocalSearchChanged,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Buscar en tu colección…',
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: (_localSearchCtrl.text.trim().isNotEmpty)
                  ? IconButton(
                      tooltip: 'Limpiar texto',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _localSearchCtrl.clear();
                        setState(() => _localQuery = '');
                        FocusScope.of(context).requestFocus(_localSearchFocus);
                      },
                    )
                  : null,
            ),
          )
        : Text(title);

    return AppBar(
      title: titleWidget,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          if (localSearchAllowed && _localSearchActive) {
            _toggleLocalSearch();
            return;
          }
          _setVista(Vista.inicio);
        },
      ),
      actions: [
        if (localSearchAllowed)
          IconButton(
            tooltip: _localSearchActive ? 'Cerrar búsqueda' : 'Buscar en mi lista',
            icon: Icon(_localSearchActive ? Icons.close : Icons.search),
            onPressed: _toggleLocalSearch,
          ),
      ],
    );
  }

  Widget? _buildFab() {
    if (vista == Vista.lista || vista == Vista.favoritos || vista == Vista.borrar) {
      // Solo icono (sin texto "Inicio")
      return FloatingActionButton(
        onPressed: () => _setVista(Vista.inicio),
        tooltip: 'Inicio',
        child: const Icon(Icons.home),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
              cs.background,
              Color.lerp(cs.background, cs.surfaceVariant, 0.10) ?? cs.background,
            ],
          ),
        ),
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: Padding(
              key: ValueKey(vista),
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (vista == Vista.inicio) ...[
                      encabezadoInicio(),
                      const SizedBox(height: 14),
                      botonesInicio(),
                    ],
                    if (vista == Vista.buscar) vistaBuscar(),
                    if (vista == Vista.lista) listaCompleta(conBorrar: false, onlyFavorites: false),
                    if (vista == Vista.favoritos) listaCompleta(conBorrar: false, onlyFavorites: true),
                    if (vista == Vista.borrar) vistaBorrar(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}