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

class _HomeScreenState extends State<HomeScreen> {
  // ⭐ Cache local para favoritos (cambio instantáneo)
  final Map<int, bool> _favCache = {};

  // ✅ fuerza rebuild de listas cuando hay cambios “silenciosos” (ej: toggle favorito optimista)
  int _reloadTick = 0;

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

  bool _gridView = false;
  late final VoidCallback _gridListener;

  // ✅ Contadores para badges en los botones del inicio
  Future<Map<String, int>>? _homeCountsFuture;
  Map<String, int> _homeCounts = const {'all': 0, 'fav': 0, 'wish': 0};

  // ✅ Cache de la lista completa (evita recargar en cada setState y permite favorito instantáneo)
  late Future<List<Map<String, dynamic>>> _futureAll;

  final artistaCtrl = TextEditingController();
  final albumCtrl = TextEditingController();
  final yearCtrl = TextEditingController();

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
  setState(() {
    _futureAll = VinylDb.instance.getAll();
  });
  _refreshHomeCounts();
}

Future<void> _loadViewMode() async {
    // Mantenemos por compatibilidad, pero hoy la app usa el notifier.
    final g = await ViewModeService.isGridEnabled();
    if (!mounted) return;
    ViewModeService.gridNotifier.value = g;
  }

  @override
  void dispose() {
    _debounceArtist?.cancel();
    _debounceAlbum?.cancel();
    ViewModeService.gridNotifier.removeListener(_gridListener);
    artistaCtrl.dispose();
    albumCtrl.dispose();
    yearCtrl.dispose();
    super.dispose();
  }

  void snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  bool _isFav(Map<String, dynamic> v) {
    final id = v['id'];
    final dbFav = (v['favorite'] ?? 0) == 1;
    if (id is int) return _favCache[id] ?? dbFav;
    return dbFav;
  }


  Future<void> _toggleFavorite(Map<String, dynamic> v) async {
    final id = v['id'];
    if (id is! int) return;

    final current = _isFav(v);
    final next = !current;

    // ✅ UI instantáneo (optimista)
    setState(() {
      _favCache[id] = next;
      v['favorite'] = next ? 1 : 0;
      _reloadTick++;

      // si estás en la vista de favoritos y lo desmarcas, lo ocultamos altiro
      if (vista == Vista.favoritos && !next) {
        // la lista se recalcula desde la DB, pero forzamos rebuild inmediato
      }
    });

    try {
      await VinylDb.instance.setFavorite(id: id, favorite: next);
      await BackupService.autoSaveIfEnabled();
      // refresca contadores (inicio)
      await _refreshHomeCounts();
    } catch (_) {
      // revertir si falla
      if (!mounted) return;
      setState(() {
        _favCache[id] = current;
        v['favorite'] = current ? 1 : 0;
        _reloadTick++;
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
            color: const Color(0xFF0B0B0B),
            child: VinylDetailSheet(vinyl: v),
          ),
        ),
      ),
    ).then((_) {
      if (!mounted) return;
      setState(() {}); // por si cambiaste favorito en el detalle
    });
  }

  Widget _numeroBadge(dynamic numero) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.70),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$numero',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _leadingCover(Map<String, dynamic> v) {
    final cp = (v['coverPath'] as String?)?.trim() ?? '';
    if (cp.isNotEmpty && _fileExistsCached(cp)) {
      final f = File(cp);
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          f,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          cacheWidth: 96,
          cacheHeight: 96,
        ),
      );
    }
    return const Icon(Icons.album);
  }

  Widget _gridCover(Map<String, dynamic> v) {
    final cp = (v['coverPath'] as String?)?.trim() ?? '';
    if (cp.isNotEmpty && _fileExistsCached(cp)) {
      final f = File(cp);
      return Image.file(
        f,
        fit: BoxFit.cover,
        cacheWidth: 600,
        cacheHeight: 600,
      );
    }
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: const Icon(Icons.album, size: 48),
    );
  }

  Widget _gridVinylCard(Map<String, dynamic> v, {required bool conBorrar}) {
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
                  ),
                  const SizedBox(height: 4),
                  Text(year.isEmpty ? '—' : year),
                ],
              ),
            ),

            // 🔢 número arriba derecha
            Positioned(
              right: 8,
              top: 8,
              child: _numeroBadge(v['numero']),
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
	                    color: fav ? Colors.grey : Colors.white,
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
                    await VinylDb.instance.deleteById(v['id'] as int);
                    await BackupService.autoSaveIfEnabled();
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

    // ✅ Contadores (ya calculados en _homeCounts)
    final all = _homeCounts['all'] ?? 0;
    final fav = _homeCounts['fav'] ?? 0;
    final wish = _homeCounts['wish'] ?? 0;

Widget _statPill({required String label, required int value}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF0F0F0F),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0xFF2A2A2A)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFFA7A7A7), fontWeight: FontWeight.w800, fontSize: 12)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFF2A2A2A)),
          ),
          child: Text(
            '$value',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
          ),
        ),
      ],
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
                style: t.textTheme.bodySmall?.copyWith(color: const Color(0xFFA7A7A7), fontWeight: FontWeight.w600),
              ),
            ]
          ],
        ),
      );
    }

    Widget quickAction({required IconData icon, required String label, required VoidCallback onTap}) {
      return ActionChip(
        onPressed: onTap,
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        avatar: Icon(icon, size: 18),
        backgroundColor: const Color(0xFF111111),
        side: const BorderSide(color: Color(0xFF2A2A2A)),
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
                      color: const Color(0xFFF1F1F1),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFEAEAEA)),
                    ),
                    child: Icon(icon, size: 24, color: const Color(0xFF0F0F0F)),
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
                          style: t.textTheme.bodySmall?.copyWith(color: const Color(0xFF6A6A6A), fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, size: 20, color: Color(0xFF6A6A6A)),
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
                          style: t.textTheme.bodySmall?.copyWith(color: const Color(0xFF9A9A9A), fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9A9A9A)),
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
                    color: const Color(0xFF0F0F0F),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
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
                        style: t.textTheme.bodySmall?.copyWith(color: const Color(0xFFA7A7A7)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, size: 20, color: Color(0xFFA7A7A7)),
              ],
            ),
          ),
        ),
      );
    }

Widget recentGrid() {
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: _futureAll,
        builder: (context, snap) {
          final items = (snap.data ?? const <Map<String, dynamic>>[]).toList();
          if (items.isEmpty) {
            return const Text(
              'Aún no has agregado vinilos. Usa “Buscar” o “Discografías”.',
              style: TextStyle(color: Color(0xFFA7A7A7), fontWeight: FontWeight.w600),
            );
          }

          // Mostramos 4 “últimos” de forma visual (sin cambiar lógica de guardado).
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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.05,
            ),
            itemBuilder: (_, i) {
              final v = top[i];
              final artista = (v['artista'] as String?)?.trim() ?? '';
              final album = (v['album'] as String?)?.trim() ?? '';
              final year = (v['year'] as String?)?.trim() ?? '';

              return InkWell(
                onTap: () => _openDetail(v),
                borderRadius: BorderRadius.circular(16),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
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
                          artista.isEmpty ? '—' : artista,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          album.isEmpty ? '—' : album,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFFA7A7A7), fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          year.isEmpty ? '—' : year,
                          style: const TextStyle(color: Color(0xFFA7A7A7), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
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
    border: Border.all(color: const Color(0xFF2A2A2A)),
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF1A1A1A),
        Color(0xFF0F0F0F),
      ],
    ),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F0F),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: const Icon(Icons.graphic_eq, size: 22, color: Colors.white),
          ),
          const SizedBox(width: 12),
	          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('GaBoLP', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                const SizedBox(height: 4),
                Text(
                  'Colección • favoritos • deseos',
                  style: t.textTheme.bodySmall?.copyWith(color: const Color(0xFFA7A7A7), fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
	          const SizedBox(width: 8),
	          IconButton(
	            tooltip: 'Actualizar',
	            onPressed: () {
	              _reloadAllData();
	            },
	            icon: const Icon(Icons.refresh, color: Colors.white),
	          ),
        ],
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
          quickAction(icon: Icons.search, label: 'Buscar', onTap: () => setState(() => vista = Vista.buscar)),
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
            setState(() => vista = Vista.lista);
          },
        ),
        menuRow(
          icon: Icons.star,
          title: 'Favoritos',
          subtitle: 'Tu selección destacada',          onTap: () {
            _reloadAllData();
            if (!mounted) return;
            setState(() => vista = Vista.favoritos);
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
          onTap: () => setState(() => vista = Vista.borrar),
        ),

        sectionTitle('Últimos agregados', subtitle: 'Acceso rápido a lo último que guardaste.'),
        recentGrid(),
        const SizedBox(height: 10),
      ],
    );
  }




  Widget vistaBuscar() {
    final p = prepared;
    final showXArtist = artistaCtrl.text.trim().isNotEmpty;
    final showXAlbum = albumCtrl.text.trim().isNotEmpty;

    Widget suggestionBox<T>({
      required List<T> items,
      required Widget Function(T) tile,
    }) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A2A)),
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
              color: const Color(0xFF0F0F0F),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ya lo tienes en tu colección:',
                  style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
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
                            style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
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
              color: const Color(0xFF0F0F0F),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Agregar este vinilo', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
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
                            Text('Artista: ${p.artist}', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                            Text('Álbum: ${p.album}', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                            const SizedBox(height: 6),
                            Text('Año: ${p.year ?? '—'}', style: const TextStyle(color: Color(0xFFBDBDBD))),
                            Text('Género: ${p.genre ?? '—'}', style: const TextStyle(color: Color(0xFFBDBDBD))),
                            Text('País: ${p.country ?? '—'}', style: const TextStyle(color: Color(0xFFBDBDBD))),
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
                      fillColor: const Color(0xFF151515),
                      labelStyle: const TextStyle(color: Color(0xFFBDBDBD)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.white),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
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
  final future = onlyFavorites ? VinylDb.instance.getFavorites() : VinylDb.instance.getAll();

  return FutureBuilder<List<Map<String, dynamic>>>(
    future: future,
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final items = snap.data ?? const <Map<String, dynamic>>[];

      if (items.isEmpty) {
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
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final v = items[i];
            final fav = _isFav(v);

            return GestureDetector(
              onTap: () => _openDetail(v),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _leadingCover(v),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        (v['album'] ?? '').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (v['artista'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: fav ? 'Quitar favorito' : 'Marcar favorito',
                            icon: Icon(
                              fav ? Icons.star : Icons.star_border,
                              color: fav ? Colors.black : Colors.grey,
                            ),
                            onPressed: () => _toggleFavorite(v),
                          ),
                          if (conBorrar)
                            IconButton(
                              tooltip: 'Borrar',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                await VinylDb.instance.deleteById(v['id'] as int);
                                await BackupService.autoSaveIfEnabled();
                                if (!mounted) return;
                                setState(() {});
                                snack('Borrado');
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final v = items[i];
          final fav = _isFav(v);

          final year = (v['year'] as String?)?.trim();
          final genre = (v['genre'] as String?)?.trim();
          final country = (v['country'] as String?)?.trim();

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              onTap: () => _openDetail(v),
              leading: _leadingCover(v),
              title: Text('${v['artista']} — ${v['album']}'),
              subtitle: Text(
                'Año: ${(year == null || year.isEmpty) ? '—' : year}  •  '
                'Género: ${(genre == null || genre.isEmpty) ? '—' : genre}  •  '
                'País: ${(country == null || country.isEmpty) ? '—' : country}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: fav ? 'Quitar favorito' : 'Marcar favorito',
                    icon: Icon(
                      fav ? Icons.star : Icons.star_border,
                      color: fav ? Colors.black : Colors.grey,
                    ),
                    onPressed: () => _toggleFavorite(v),
                  ),
                  if (conBorrar)
                    IconButton(
                      tooltip: 'Borrar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await VinylDb.instance.deleteById(v['id'] as int);
                        await BackupService.autoSaveIfEnabled();
                        if (!mounted) return;
                        setState(() {});
                        snack('Borrado');
                      },
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





  PreferredSizeWidget? _buildAppBar() {
    // Usamos vista explícito para evitar problemas de resolución de nombres
    if (vista == Vista.inicio) return null;

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

    return AppBar(
      title: Text(title),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => setState(() => vista = Vista.inicio),
      ),
    );
  }

  Widget? _buildFab() {
    if (vista == Vista.lista || vista == Vista.favoritos || vista == Vista.borrar) {
      // Solo icono (sin texto "Inicio")
      return FloatingActionButton(
        onPressed: () => setState(() => vista = Vista.inicio),
        tooltip: 'Inicio',
        child: const Icon(Icons.home),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      floatingActionButton: _buildFab(),
      body: Stack(
        children: [
          Positioned.fill(child: Container(color: Colors.grey.shade300)),
          Positioned.fill(child: Container(color: Colors.black.withOpacity(0.35))),
          SafeArea(
            child: Padding(
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
                    if (vista == Vista.borrar) listaCompleta(conBorrar: true, onlyFavorites: false),
                  ],
                ),
              ),
            ),
          ),
          gabolpMarca(),
        ],
      ),
    );
  }
}
