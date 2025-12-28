import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
import '../services/backup_service.dart';
import '../services/discography_service.dart';
import '../services/add_defaults_service.dart';
import '../services/price_alert_service.dart';
import 'album_tracks_screen.dart';
import 'vinyl_detail_sheet.dart';
import 'app_logo.dart';
import '../l10n/app_strings.dart';
import 'widgets/app_cover_image.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _grid = false;

  // price alerts (wishlist)
  final Map<int, Map<String, dynamic>> _wishAlerts = {};

  @override
  void initState() {
    super.initState();
    _future = VinylDb.instance.getWishlist();
    _loadWishAlerts();
  }

  Future<void> _loadWishAlerts() async {
    try {
      final rows = await VinylDb.instance.getPriceAlerts(kind: 'wish');
      _wishAlerts.clear();
      for (final r in rows) {
        final itemId = (r['itemId'] as int?) ?? 0;
        if (itemId > 0) _wishAlerts[itemId] = r;
      }
      if (mounted) setState(() {});
    } catch (_) {
      // ignore
    }
  }

  void _reload() {
    setState(() {
      _future = VinylDb.instance.getWishlist();
    });
    _loadWishAlerts();
  }

  /// Badge de estado para Wishlist (se ve bien tanto en tema claro como oscuro).
  Widget _statusChip(BuildContext context, String status) {
    final s = status.trim().toLowerCase();
    final scheme = Theme.of(context).colorScheme;

    Color bg;
    Color fg;
    IconData icon;

    if (s.contains('busc')) {
      // Buscando
      bg = scheme.secondaryContainer;
      fg = scheme.onSecondaryContainer;
      icon = Icons.search;
    } else if (s.contains('compr')) {
      // Por comprar / Comprar
      bg = scheme.tertiaryContainer;
      fg = scheme.onTertiaryContainer;
      icon = Icons.shopping_cart_outlined;
    } else if (s.contains('esper') || s.contains('pend') || s.contains('en lista')) {
      // En espera / Pendiente
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
      icon = Icons.hourglass_bottom;
    } else {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
      icon = Icons.bookmark_border;
    }

    final textStyle = (Theme.of(context).textTheme.labelMedium ?? TextStyle())
        .copyWith(color: fg, fontWeight: FontWeight.w800);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          SizedBox(width: 6),
          Text(context.tr(status), style: textStyle),
        ],
      ),
    );
  }

  

Future<Map<String, String>?> _askConditionAndFormat() async {
  String condition = 'VG+';
  String format = 'LP';

  try {
    condition = await AddDefaultsService.getLastCondition(fallback: condition);
    format = await AddDefaultsService.getLastFormat(fallback: format);
  } catch (_) {}

  if (!mounted) return null;

  final res = await showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            title: Text(context.tr('Agregar a tu lista')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: condition,
                  key: ValueKey(condition),
                  decoration: InputDecoration(labelText: context.tr('Condición')),
                  items: [
                    DropdownMenuItem(value: 'M', child: Text(context.tr('M (Mint)'))),
                    DropdownMenuItem(value: 'NM', child: Text(context.tr('NM (Near Mint)'))),
                    DropdownMenuItem(value: 'VG+', child: Text(context.tr('VG+'))),
                    DropdownMenuItem(value: 'VG', child: Text(context.tr('VG'))),
                    DropdownMenuItem(value: 'G', child: Text('G')),
                  ],
                  onChanged: (v) => setSt(() => condition = v ?? condition),
                ),
                SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: format,
                  key: ValueKey(format),
                  decoration: InputDecoration(labelText: context.tr('Formato')),
                  items: [
                    DropdownMenuItem(value: 'LP', child: Text(context.tr('LP'))),
                    DropdownMenuItem(value: 'EP', child: Text(context.tr('EP'))),
                    DropdownMenuItem(value: 'Single', child: Text(context.tr('Single'))),
                    DropdownMenuItem(value: '2xLP', child: Text(context.tr('2xLP'))),
                    DropdownMenuItem(value: 'Boxset', child: Text(context.tr('Boxset'))),
                  ],
                  onChanged: (v) => setSt(() => format = v ?? format),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('Cancelar'))),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, {'condition': condition, 'format': format}),
                child: Text(context.tr('Aceptar')),
              ),
            ],
          );
        },
      );
    },
  );

  if (res != null) {
    await AddDefaultsService.saveLast(condition: res['condition'] ?? condition, format: res['format'] ?? format);
  }
  return res;
}
void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.trSmart(t))));
  }

  Future<void> _editWishAlert(Map<String, dynamic> w) async {
    final id = w['id'];
    if (id is! int) return;

    final artista = (w['artista'] ?? '').toString().trim();
    final album = (w['album'] ?? '').toString().trim();
    if (artista.isEmpty || album.isEmpty) return;

    final existing = _wishAlerts[id];
    final initial = (existing?['target'] as num?)?.toDouble();
    final ctrl = TextEditingController(text: initial == null ? '' : initial.toStringAsFixed(0));

    final res = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(context.tr('Alertas de precio')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('Avísame si baja de')),
              SizedBox(height: 10),
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  prefixText: '€ ',
                  labelText: context.tr('Precio objetivo'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('Cancelar'))),
            if (existing != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: Text(context.tr('Quitar alerta')),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: Text(context.tr('Guardar alerta')),
            ),
          ],
        );
      },
    );

    if (res == 'delete') {
      await VinylDb.instance.deletePriceAlert(kind: 'wish', itemId: id);
      _snack('Alerta eliminada ✅');
      _loadWishAlerts();
      return;
    }
    if (res != 'save') return;

    final target = double.tryParse(ctrl.text.replaceAll(',', '.').trim());
    if (target == null || target <= 0) {
      _snack('Precio inválido');
      return;
    }

    await VinylDb.instance.upsertPriceAlert(
      kind: 'wish',
      itemId: id,
      artista: artista,
      album: album,
      target: target,
      currency: 'EUR',
      isActive: true,
    );
    _snack('Alerta guardada ✅');
    _loadWishAlerts();
  }

  Future<void> _checkAlertsNow() async {
    _snack('Buscando');
    final hits = await PriceAlertService.checkNow();
    if (!mounted) return;
    if (hits.isEmpty) {
      _snack('Sin coincidencias');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(context.tr('Alertas de precio')),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: hits.length,
              itemBuilder: (_, i) {
                final h = hits[i];
                final cur = h.range.currency;
                final min = h.range.min.toStringAsFixed(0);
                final max = h.range.max.toStringAsFixed(0);
                final target = h.target.toStringAsFixed(0);
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: Text('${h.artista} — ${h.album}'),
                  subtitle: Text('$cur $min–$max  ·  ${context.tr('Precio objetivo')}: $cur $target'),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('Cerrar'))),
          ],
        );
      },
    );
  }

  Future<void> _removeItem(Map<String, dynamic> w) async {
    final id = w['id'];
    if (id is! int) return;

    await VinylDb.instance.removeWishlistById(id);
    await BackupService.autoSaveIfEnabled();

    _snack('Eliminado de la lista de deseos');
    _reload();
  }

  
  Widget _metaPill(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = text.trim().isEmpty ? '—' : text.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.35 : 0.65),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: isDark ? 0.55 : 0.35)),
      ),
      child: Text(
        t,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

Widget _placeholder() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.library_music, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  Widget _leadingCover(Map<String, dynamic> w, {double size = 56}) {
    final cover = ((size >= 120 ? (w['cover500'] as String?) : null) ?? (w['cover250'] as String?))?.trim() ?? '';

    if (cover.isEmpty) return _placeholder();

    return AppCoverImage(
      pathOrUrl: cover,
      width: size,
      height: size,
      fit: BoxFit.cover,
      borderRadius: BorderRadius.circular(10),
    );
  }

  Widget _wishListCard(Map<String, dynamic> w) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final artista = (w['artista'] ?? '').toString().trim();
    final album = (w['album'] ?? '').toString().trim();
    final year = (w['year'] ?? '').toString().trim();
    final wid = w['id'];
    final hasAlert = (wid is int) && _wishAlerts.containsKey(wid);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: isDark ? 0.55 : 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openDetail(w),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                height: 92,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.30 : 0.60),
                    child: _leadingCover(w, size: 92),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, right: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _metaPill(context, year),
                          if (status.isNotEmpty) _statusChip(context, status),
                        ],
                      ),
                      SizedBox(height: 10),
                      Text(
                        artista.isEmpty ? '—' : artista,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 2),
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
              SizedBox(width: 6),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: context.tr('Alertas de precio'),
                    icon: Icon(
                      hasAlert ? Icons.notifications_active_outlined : Icons.notifications_none_outlined,
                      color: cs.onSurfaceVariant,
                      size: 22,
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _editWishAlert(w),
                  ),
                  IconButton(
                    tooltip: context.tr('Agregar a vinilos'),
                    icon: Icon(Icons.playlist_add, color: cs.onSurfaceVariant, size: 22),
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      final opts = await _askConditionAndFormat();
                      if (!mounted || opts == null) return;

                      final a = (w['artista'] ?? '').toString().trim();
                      final al = (w['album'] ?? '').toString().trim();
                      if (a.isEmpty || al.isEmpty) return;

                      try {
                        await VinylDb.instance.insertVinyl(
                          artista: a,
                          album: al,
                          condition: opts['condition'],
                          format: opts['format'],
                          year: (w['year'] ?? '').toString().trim().isEmpty ? null : w['year'].toString().trim(),
                          coverPath: (w['cover250'] ?? '').toString(),
                        );
                        final id = w['id'];
                        if (id is int) {
                          await VinylDb.instance.removeWishlistById(id);
                        }
                        await BackupService.autoSaveIfEnabled();
                        _snack('Agregado a tu lista de vinilos');
                        _reload();
                      } catch (_) {
                        _snack('No se pudo agregar');
                      }
                    },
                  ),
                  IconButton(
                    tooltip: context.tr('Eliminar'),
                    icon: Icon(Icons.delete_outline, color: cs.onSurfaceVariant, size: 22),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _removeItem(w),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wishGridCard(Map<String, dynamic> w) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final artista = (w['artista'] ?? '').toString().trim();
    final album = (w['album'] ?? '').toString().trim();
    final year = (w['year'] ?? '').toString().trim();
    final wid = w['id'];
    final hasAlert = (wid is int) && _wishAlerts.containsKey(wid);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: isDark ? 0.55 : 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openDetail(w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      color: cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.30 : 0.60),
                      child: _leadingCover(w, size: 220),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artista.isEmpty ? '—' : artista,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 2),
                  Text(
                    album.isEmpty ? '—' : album,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      _metaPill(context, year),
                      SizedBox(width: 8),
                      if (status.isNotEmpty)
                        Expanded(child: Align(alignment: Alignment.centerLeft, child: _statusChip(context, status))),
                      Spacer(),
                      IconButton(
                        tooltip: context.tr('Alertas de precio'),
                        icon: Icon(
                          hasAlert ? Icons.notifications_active_outlined : Icons.notifications_none_outlined,
                          color: cs.onSurfaceVariant,
                          size: 20,
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _editWishAlert(w),
                      ),
                      IconButton(
                        tooltip: context.tr('Agregar a vinilos'),
                        icon: Icon(Icons.playlist_add, color: cs.onSurfaceVariant, size: 20),
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          final opts = await _askConditionAndFormat();
                          if (!mounted || opts == null) return;

                          final a = (w['artista'] ?? '').toString().trim();
                          final al = (w['album'] ?? '').toString().trim();
                          if (a.isEmpty || al.isEmpty) return;

                          try {
                            await VinylDb.instance.insertVinyl(
                              artista: a,
                              album: al,
                              condition: opts['condition'],
                              format: opts['format'],
                              year: (w['year'] ?? '').toString().trim().isEmpty ? null : w['year'].toString().trim(),
                              coverPath: (w['cover250'] ?? '').toString(),
                            );
                            final id = w['id'];
                            if (id is int) {
                              await VinylDb.instance.removeWishlistById(id);
                            }
                            await BackupService.autoSaveIfEnabled();
                            _snack('Agregado a tu lista de vinilos');
                            _reload();
                          } catch (_) {
                            _snack('No se pudo agregar');
                          }
                        },
                      ),
                      IconButton(
                        tooltip: context.tr('Eliminar'),
                        icon: Icon(Icons.delete_outline, color: cs.onSurfaceVariant, size: 20),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _removeItem(w),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDetail(Map<String, dynamic> w) async {
    final artistName = (w['artista'] ?? '').toString().trim();
    final albumTitle = (w['album'] ?? '').toString().trim();
    final year = (w['year'] ?? '').toString().trim();
    final cover250 = (w['cover250'] ?? '').toString().trim();
    final cover500 = (w['cover500'] ?? '').toString().trim();
    final artistId = (w['artistId'] ?? '').toString().trim();

    // ✅ Si tenemos artistId, intentamos abrir igual que Discografías (con canciones)
    if (artistId.isNotEmpty && artistName.isNotEmpty && albumTitle.isNotEmpty) {
      try {
        final discog = await DiscographyService.getDiscographyByArtistId(artistId);
        AlbumItem? match;
        for (final a in discog) {
          if (a.title.trim().toLowerCase() == albumTitle.toLowerCase()) {
            match = a;
            break;
          }
        }
        if (match != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AlbumTracksScreen(album: match!, artistName: artistName),
            ),
          );
          return;
        }
      } catch (_) {
        // fallback abajo
      }
    }

    // Fallback: mostramos detalle básico (sin tracks)
    final cover = cover500.isNotEmpty ? cover500 : cover250;
    final vinylLike = <String, dynamic>{
      'mbid': '',
      'coverPath': cover,
      'artista': artistName,
      'album': albumTitle,
      'year': year,
      'genre': '',
      'country': '',
      'artistBio': '',
    };

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VinylDetailSheet(vinyl: vinylLike),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kAppBarToolbarHeight,
        leadingWidth: appBarLeadingWidthForLogoBack(logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        leading: appBarLeadingLogoBack(context, logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        // Más aire entre el leading (logo + back) y el título.
        title: appBarTitleTextScaled(context.tr('Deseos'), padding: const EdgeInsets.only(left: 8)),
        titleSpacing: 12,
        actions: [
          IconButton(
            tooltip: context.tr('Revisar alertas'),
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: _checkAlertsNow,
          ),
          IconButton(
            tooltip: _grid ? 'Vista lista' : 'Vista grid',
            icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _grid = !_grid),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text("${context.tr('Error cargando wishlist')}: ${snap.error}"),
              ),
            );
          }

          final items = snap.data ?? const [];

          if (items.isEmpty) {
            return Center(child: Text(context.tr('Tu lista de deseos está vacía')));
          }

          return _grid
              ? GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _wishGridCard(items[i]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _wishListCard(items[i]),
                );
        },
      ),
    );
  }
}