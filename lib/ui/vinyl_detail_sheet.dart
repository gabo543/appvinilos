import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/discography_service.dart';
import '../services/price_range_service.dart';
import '../services/store_price_service.dart';
import '../services/country_service.dart';
import '../services/cover_cache_service.dart';
import '../services/backup_service.dart';
import '../db/vinyl_db.dart';
import '../l10n/app_strings.dart';
import '../utils/normalize.dart';
import 'widgets/app_cover_image.dart';

/// Bottom sheet con los precios (iMusic / Muziker).
///
/// - Si hay barcode (EAN/UPC), lo usa (más preciso).
/// - Si no, busca por texto (artista + álbum) en las mismas tiendas.
class _VinylStorePricesSheet extends StatefulWidget {
  final String artista;
  final String album;
  final String? barcode;

  const _VinylStorePricesSheet({
    required this.artista,
    required this.album,
    this.barcode,
  });

  @override
  State<_VinylStorePricesSheet> createState() => _VinylStorePricesSheetState();
}

class _VinylStorePricesSheetState extends State<_VinylStorePricesSheet> {
  late Future<List<StoreOffer>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<StoreOffer>> _fetch({bool forceRefresh = false}) {
    final b = (widget.barcode ?? '').trim();
    if (b.isNotEmpty) {
      return StorePriceService.fetchOffersByBarcodeCached(b, forceRefresh: forceRefresh);
    }
    return StorePriceService.fetchOffersByQueryCached(
      artist: widget.artista,
      album: widget.album,
      forceRefresh: forceRefresh,
    );
  }

  void _refresh() {
    setState(() {
      _future = _fetch(forceRefresh: true);
    });
  }

  String _fmt(double v) {
    // Formato simple para UI: 12.00 -> 12
    final r = v.roundToDouble();
    if ((v - r).abs() < 0.005) return r.toInt().toString();
    return v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final b = (widget.barcode ?? '').trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('Precios en tiendas'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.artista} — ${widget.album}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      b.isNotEmpty ? 'EAN/UPC: $b' : context.tr('Búsqueda por texto (sin EAN)'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.tr('Actualizar'),
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<StoreOffer>>(
            future: _future,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final offers = snap.data ?? const <StoreOffer>[];
              if (offers.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    context.tr('No pude obtener precios en las tiendas seleccionadas.'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              }

              final sorted = [...offers]..sort((a, b) => a.price.compareTo(b.price));
              final min = sorted.first.price;
              final max = sorted.last.price;
              final a = _fmt(min);
              final b = _fmt(max);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (a == b)
                        ? '${context.tr('Precio')}: €$a'
                        : '${context.tr('Rango')}: €$a - €$b',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  ...sorted.map(
                    (o) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(o.store, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(o.note == null || o.note!.trim().isEmpty ? o.url : '${o.note}\n${o.url}'),
                      trailing: Text('€${_fmt(o.price)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('Los precios pueden cambiar y algunas tiendas pueden bloquear la consulta automática.'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class VinylDetailSheet extends StatefulWidget {
  final Map<String, dynamic> vinyl;
  /// Si es false, oculta completamente todo lo relacionado a precios/alertas.
  /// Útil para "Vinilos" y "Favoritos" (ya los tienes, no aporta mostrar precios).
  final bool showPrices;

  VinylDetailSheet({
    super.key,
    required this.vinyl,
    this.showPrices = true,
  });

  @override
  State<VinylDetailSheet> createState() => _VinylDetailSheetState();
}

class _VinylDetailSheetState extends State<VinylDetailSheet> {
  bool loadingTracks = false;
  List<TrackItem> tracks = [];
  String? msg;

  // ❤️ canciones guardadas para este álbum (por trackKey)
  Set<String> _likedKeys = <String>{};

  bool loadingPrice = false;
  PriceRange? priceRange;

  Map<String, dynamic>? _priceAlert; // alerta de precio para este ítem

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(text))));
  }

  Future<void> _loadLikedKeys() async {
    final rg = (widget.vinyl['mbid'] as String?)?.trim() ?? '';
    if (rg.isEmpty) return;
    try {
      final keys = await VinylDb.instance.getLikedTrackKeysForReleaseGroup(rg);
      if (!mounted) return;
      setState(() => _likedKeys = keys);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _toggleLikeFromVinyl(TrackItem t) async {
    final rg = (widget.vinyl['mbid'] as String?)?.trim() ?? '';
    if (rg.isEmpty) {
      _snack('No hay ID (MBID) guardado para este LP.');
      return;
    }

    final key = normalizeKey(t.title);
    final artista = (widget.vinyl['artista'] as String?)?.trim() ?? '';
    final album = (widget.vinyl['album'] as String?)?.trim() ?? '';
    final year = (widget.vinyl['year'] as String?)?.trim();
    final cover = (widget.vinyl['coverPath'] as String?)?.trim();

    if (_likedKeys.contains(key)) {
      await VinylDb.instance.removeLikedTrack(releaseGroupId: rg, trackTitle: t.title);
      if (!mounted) return;
      setState(() => _likedKeys = {..._likedKeys}..remove(key));
      _snack('Quitada de canciones');
      // Si el auto-backup está activo, respalda cambios en canciones.
      try {
        await BackupService.autoSaveIfEnabled();
      } catch (_) {}
      return;
    }

    await VinylDb.instance.addLikedTrack(
      artista: artista,
      album: album,
      year: (year == null || year.isEmpty) ? null : year,
      releaseGroupId: rg,
      cover250: (cover == null || cover.isEmpty) ? null : cover,
      cover500: (cover == null || cover.isEmpty) ? null : cover,
      trackTitle: t.title,
      trackNo: t.number,
    );

    if (!mounted) return;
    setState(() => _likedKeys = {..._likedKeys}..add(key));
    _snack('Canción guardada ❤️');

    // Si el auto-backup está activo, respalda cambios en canciones.
    try {
      await BackupService.autoSaveIfEnabled();
    } catch (_) {}
  }

  Future<void> _openStorePrices() async {
    final artista = (widget.vinyl['artista'] as String?)?.trim() ?? '';
    final album = (widget.vinyl['album'] as String?)?.trim() ?? '';
    if (artista.isEmpty || album.isEmpty) return;

    final barcode = (widget.vinyl['barcode'] as String?)?.trim();

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _VinylStorePricesSheet(
        artista: artista,
        album: album,
        barcode: (barcode == null || barcode.isEmpty) ? null : barcode,
      ),
    );
  }

  Future<void> _editMeta() async {
    final id = int.tryParse((widget.vinyl['id'] ?? '').toString()) ?? 0;
    if (id <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('No puedo editar: falta ID.'))));
      return;
    }

    final artista0 = (widget.vinyl['artista'] as String?)?.trim() ?? '';
    final album0 = (widget.vinyl['album'] as String?)?.trim() ?? '';
    final year0 = (widget.vinyl['year'] as String?)?.trim() ?? '';
    final country0 = (widget.vinyl['country'] as String?)?.trim() ?? '';
    final cond0 = (widget.vinyl['condition'] as String?)?.trim() ?? 'VG+';
    final fmt0 = (widget.vinyl['format'] as String?)?.trim() ?? 'LP';
    final cover0 = (widget.vinyl['coverPath'] as String?)?.trim() ?? '';
    final mbid0 = (widget.vinyl['mbid'] as String?)?.trim() ?? '';
    final numero0 = int.tryParse((widget.vinyl['numero'] ?? '').toString()) ?? 0;

    final artistaCtrl = TextEditingController(text: artista0);
    final albumCtrl = TextEditingController(text: album0);
    final yearCtrl = TextEditingController(text: year0);
    final countryCtrl = TextEditingController(text: country0);
    final numeroCtrl = TextEditingController(text: (numero0 > 0) ? numero0.toString() : '');
    String condition = cond0.isEmpty ? 'VG+' : cond0;
    String format = fmt0.isEmpty ? 'LP' : fmt0;

    // Carátula editable
    String coverPath = cover0;
    bool savingCover = false;

    Future<void> pickAndSaveCover(StateSetter setD, ImageSource src) async {
      try {
        final picker = ImagePicker();
        final x = await picker.pickImage(source: src, imageQuality: 92);
        if (x == null) return;

        final prev = coverPath;
        try {
          setD(() => savingCover = true);
        } catch (_) {}

        final savedPath = await CoverCacheService.saveCustomCover(
          vinylId: id,
          mbid: mbid0.isEmpty ? null : mbid0,
          sourcePath: x.path,
        );

        if (savedPath == null || savedPath.trim().isEmpty) {
          _snack(src == ImageSource.camera
              ? 'No pude guardar la carátula desde la cámara.'
              : 'No pude guardar la carátula desde la galería.');
        } else {
          coverPath = savedPath;
          // Limpia el archivo anterior solo si era administrado por la app.
          if (prev.trim().isNotEmpty && prev.trim() != coverPath.trim()) {
            await CoverCacheService.deleteIfManaged(prev);
          }
        }
      } catch (_) {
        _snack(src == ImageSource.camera ? 'No pude abrir la cámara.' : 'No pude abrir la galería.');
      } finally {
        try {
          setD(() => savingCover = false);
        } catch (_) {}
      }
    }

    // Catálogo de países (para autocomplete). Si falla, igual permitimos texto libre.
    List<CountryOption> allCountries = const <CountryOption>[];
    try {
      allCountries = await CountryService.getAllCountries();
    } catch (_) {
      allCountries = const <CountryOption>[];
    }

    // Sugerencias (se mantiene dentro del StatefulBuilder).
    List<CountryOption> countrySuggestions = <CountryOption>[];

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            return AlertDialog(
              title: Text(context.tr('Editar vinilo')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Carátula editable (solo aquí, como pediste)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        context.tr('Carátula'),
                        style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppCoverImage(
                          pathOrUrl: coverPath,
                          width: 92,
                          height: 92,
                          borderRadius: BorderRadius.circular(12),
                          cacheWidth: 240,
                          cacheHeight: 240,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              OutlinedButton.icon(
                                onPressed: savingCover ? null : () => pickAndSaveCover(setD, ImageSource.gallery),
                                icon: const Icon(Icons.photo_library_outlined),
                                label: Text(context.tr('Elegir de galería')),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: savingCover ? null : () => pickAndSaveCover(setD, ImageSource.camera),
                                icon: const Icon(Icons.photo_camera_outlined),
                                label: Text(context.tr('Tomar foto')),
                              ),
                              if (savingCover)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: LinearProgressIndicator(minHeight: 3),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: numeroCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(labelText: context.tr('Número de vinilo')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: artistaCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: context.tr('Artista')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: albumCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: context.tr('Álbum')),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: yearCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: context.tr('Año (opcional)')),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: countryCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: context.tr('País (opcional)'),
                        hintText: context.tr('Ej: Finlandia'),
                      ),
                      onChanged: (v) {
                        if (allCountries.isEmpty) return;
                        final q = v.trim();
                        if (q.isEmpty) {
                          setD(() => countrySuggestions = <CountryOption>[]);
                          return;
                        }
                        final out = CountryService.suggest(allCountries, q, limit: 8).toList();
                        setD(() => countrySuggestions = out);
                      },
                    ),
                    if (allCountries.isNotEmpty && countrySuggestions.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          border: Border.all(color: Theme.of(ctx).dividerColor),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            itemCount: countrySuggestions.length,
                            separatorBuilder: (_, __) => Divider(height: 1),
                            itemBuilder: (_, i) {
                              final c = countrySuggestions[i];
                              return ListTile(
                                dense: true,
                                title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(c.code),
                                onTap: () {
                                  countryCtrl.text = c.name;
                                  setD(() => countrySuggestions = <CountryOption>[]);
                                  FocusScope.of(ctx).unfocus();
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    SizedBox(height: 12),
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
                      onChanged: (v) => setD(() => condition = v ?? condition),
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
                      onChanged: (v) => setD(() => format = v ?? format),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: savingCover ? null : () => Navigator.pop(ctx, false),
                  child: Text(context.tr('Cancelar')),
                ),
                FilledButton(
                  onPressed: savingCover ? null : () => Navigator.pop(ctx, true),
                  child: Text(context.tr('Guardar')),
                ),
              ],
            );
          },
        );
      },
    );

    // Limpia controllers
    final newArtist = artistaCtrl.text.trim();
    final newAlbum = albumCtrl.text.trim();
    final newYear = yearCtrl.text.trim();
    final newCountry = countryCtrl.text.trim();
    final newNumeroText = numeroCtrl.text.trim();
    artistaCtrl.dispose();
    albumCtrl.dispose();
    yearCtrl.dispose();
    countryCtrl.dispose();
    numeroCtrl.dispose();

    if (saved != true) return;

    final newCover = coverPath.trim();
    final coverChanged = newCover.toLowerCase() != cover0.trim().toLowerCase();

    int? numeroToSave;
    if (newNumeroText.isNotEmpty) {
      final n = int.tryParse(newNumeroText);
      if (n == null || n <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.trSmart('Número inválido'))));
        return;
      }
      if (n != numero0) numeroToSave = n;
    }

    try {
      await VinylDb.instance.updateVinylDetails(
        id: id,
        numero: numeroToSave,
        artista: newArtist,
        album: newAlbum,
        year: newYear,
        country: newCountry,
        condition: condition,
        format: format,
        coverPath: coverChanged ? newCover : null,
      );

      // Actualiza el mapa local para reflejar cambios sin recargar.
      if (numeroToSave != null) {
        widget.vinyl['numero'] = numeroToSave;
      }
      widget.vinyl['artista'] = newArtist;
      widget.vinyl['album'] = newAlbum;
      widget.vinyl['year'] = newYear;
      widget.vinyl['country'] = newCountry;
      widget.vinyl['condition'] = condition;
      widget.vinyl['format'] = format;
      if (coverChanged) {
        widget.vinyl['coverPath'] = newCover;
      }
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Actualizado ✅'))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${context.tr('No se pudo guardar')}: ${context.trSmart(e.toString())}")));
    }
  }

  @override
  void initState() {
    super.initState();
    _loadTracks();
    _loadLikedKeys();
    if (widget.showPrices) {
      _loadPrice();
      _loadAlert();
    }
  }

  Future<void> _loadAlert() async {
    final id = int.tryParse((widget.vinyl['id'] ?? '').toString()) ?? 0;
    if (id <= 0) return;
    try {
      final row = await VinylDb.instance.getPriceAlertFor(kind: 'vinyl', itemId: id);
      if (!mounted) return;
      setState(() => _priceAlert = row);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _editPriceAlert() async {
    final id = int.tryParse((widget.vinyl['id'] ?? '').toString()) ?? 0;
    if (id <= 0) return;

    final artista = (widget.vinyl['artista'] as String?)?.trim() ?? '';
    final album = (widget.vinyl['album'] as String?)?.trim() ?? '';
    final mbid = (widget.vinyl['mbid'] as String?)?.trim() ?? '';
    if (artista.isEmpty || album.isEmpty) return;

    final initial = (_priceAlert?['target'] as num?)?.toDouble();
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
            if (_priceAlert != null)
              TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: Text(context.tr('Quitar alerta'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(context.tr('Guardar alerta'))),
          ],
        );
      },
    );

    if (res == 'delete') {
      await VinylDb.instance.deletePriceAlert(kind: 'vinyl', itemId: id);
      if (!mounted) return;
      setState(() => _priceAlert = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.trSmart('Alerta eliminada ✅'))));
      return;
    }
    if (res != 'save') return;

    final target = double.tryParse(ctrl.text.replaceAll(',', '.').trim());
    if (target == null || target <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.trSmart('Precio inválido'))));
      return;
    }

    await VinylDb.instance.upsertPriceAlert(
      kind: 'vinyl',
      itemId: id,
      artista: artista,
      album: album,
      mbid: mbid,
      target: target,
      currency: 'EUR',
      isActive: true,
    );
    await _loadAlert();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.trSmart('Alerta guardada ✅'))));
  }

  String _fmtMoney(double v) {
    final r = v.round();
    if ((v - r).abs() < 0.001) return r.toString();
    return v.toStringAsFixed(2);
  }

  String _priceLabel() {
    if (loadingPrice) return '€ …';
    final pr = priceRange;
    if (pr == null) return '';

    final a = _fmtMoney(pr.min);
    final b = _fmtMoney(pr.max);

    if (a == b) return '€ $a';
    return '€ $a - $b';
  }

  String _priceUpdatedMini() {
    final pr = priceRange;
    if (loadingPrice || pr == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(pr.fetchedAtMs);
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 2) return '• 1m';
    if (diff.inMinutes < 60) return '• ${diff.inMinutes}m';
    if (diff.inHours < 48) return '• ${diff.inHours}h';
    return '• ${diff.inDays}d';
  }

  Future<void> _loadPrice({bool forceRefresh = false}) async {
    final artista = (widget.vinyl['artista'] as String?)?.trim() ?? '';
    final album = (widget.vinyl['album'] as String?)?.trim() ?? '';
    final mbid = (widget.vinyl['mbid'] as String?)?.trim() ?? '';
    if (artista.isEmpty || album.isEmpty) return;
    setState(() {
      loadingPrice = true;
      priceRange = null;
    });
    try {
      final pr = await PriceRangeService.getRange(
        artist: artista,
        album: album,
        mbid: mbid.isEmpty ? null : mbid,
        barcode: (widget.vinyl['barcode'] as String?)?.trim(),
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        priceRange = pr;
        loadingPrice = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        priceRange = null;
        loadingPrice = false;
      });
    }
  }

  Future<void> _loadTracks() async {
    final mbid = (widget.vinyl['mbid'] as String?)?.trim() ?? '';
    if (mbid.isEmpty) {
      setState(() {
        msg = 'No hay ID (MBID) guardado para este LP, no puedo buscar canciones.';
        tracks = [];
        loadingTracks = false;
        _likedKeys = <String>{};
      });
      return;
    }

    setState(() {
      loadingTracks = true;
      msg = null;
      tracks = [];
    });

    final list = await DiscographyService.getTracksFromReleaseGroup(mbid);

    if (!mounted) return;

    setState(() {
      tracks = list;
      loadingTracks = false;
      if (list.isEmpty) msg = 'No encontré canciones para este disco.';
    });

    // Refresca estado ❤️ para el álbum.
    await _loadLikedKeys();
  }

  Widget _cover() {
    final cp = (widget.vinyl['coverPath'] as String?)?.trim() ?? '';

    // Skeleton placeholder + manejo de error unificados.
    return AppCoverImage(
      pathOrUrl: cp,
      width: 120,
      height: 120,
      fit: BoxFit.cover,
      borderRadius: BorderRadius.circular(14),
      cacheWidth: 360,
      cacheHeight: 360,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final fg = dark ? Colors.white : Colors.black;
    final sub = dark ? const Color(0xFFBDBDBD) : Colors.black54;
    final artista = (widget.vinyl['artista'] as String?) ?? '';
    final album = (widget.vinyl['album'] as String?) ?? '';
    final aNo = int.tryParse((widget.vinyl['artistNo'] ?? '').toString()) ?? 0;
    final alNo = int.tryParse((widget.vinyl['albumNo'] ?? '').toString()) ?? 0;
    final code = (aNo > 0 && alNo > 0)
        ? '$aNo.$alNo'
        : ((widget.vinyl['numero'] ?? '').toString().trim().isEmpty
            ? '—'
            : (widget.vinyl['numero'] ?? '').toString());
    final year = (widget.vinyl['year'] as String?)?.trim() ?? '';
    final genre = (widget.vinyl['genre'] as String?)?.trim() ?? '';
    final country = (widget.vinyl['country'] as String?)?.trim() ?? '';
    final condition = (widget.vinyl['condition'] as String?)?.trim() ?? '';
    final format = (widget.vinyl['format'] as String?)?.trim() ?? '';
    final wishlistStatus = (widget.vinyl['status'] as String?)?.trim() ?? '';
    final bio = (widget.vinyl['artistBio'] as String?)?.trim() ?? '';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header (carátula + título + acciones)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cover(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.isEmpty ? '—' : album,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: fg),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        artista.isEmpty ? '—' : artista,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: sub),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip(context, icon: Icons.numbers, label: 'Orden', value: code),
                          if (year.isNotEmpty) _chip(context, icon: Icons.calendar_month, label: 'Año', value: year),
                          if (widget.showPrices) _pricePill(context),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      tooltip: context.tr('Editar'),
                      onPressed: _editMeta,
                      icon: Icon(Icons.edit, color: fg),
                    ),
                    IconButton(
                      tooltip: context.tr('Cerrar'),
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: fg),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            Expanded(
              child: ListView(
                children: [
                  // Ficha / Metadatos
                  _sectionCard(
                    context,
                    title: context.tr('Detalles'),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _pill(context, 'Género', genre.isEmpty ? '—' : genre),
                        _pill(context, 'País', country.isEmpty ? '—' : country),
                        if (condition.isNotEmpty) _pill(context, 'Condición', condition),
                        if (format.isNotEmpty) _pill(context, 'Formato', format),
                        if (wishlistStatus.isNotEmpty) _pill(context, 'Wishlist', wishlistStatus),
                      ],
                    ),
                  ),

                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _sectionCard(
                      context,
                      title: context.tr('Reseña'),
                      child: Text(
                        bio,
                        style: t.textTheme.bodyMedium?.copyWith(color: fg, height: 1.35),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  _sectionCard(
                    context,
                    title: context.tr('Canciones'),
                    trailing: TextButton.icon(
                      onPressed: _loadTracks,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(context.tr('Actualizar')),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (loadingTracks) const LinearProgressIndicator(),
                        if (!loadingTracks && msg != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(context.tr(msg!), style: TextStyle(color: sub)),
                          ),
                        if (!loadingTracks && tracks.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          ..._buildTrackTiles(context, tracks, fg: fg, sub: sub),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTrackTiles(BuildContext context, List<TrackItem> items, {required Color fg, required Color sub}) {
    final out = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      final tr = items[i];
      final liked = _likedKeys.contains(normalizeKey(tr.title));
      out.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '${tr.number}.',
                  textAlign: TextAlign.right,
                  style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr.title,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: liked ? 'Quitar de canciones' : 'Guardar canción',
                onPressed: () => _toggleLikeFromVinyl(tr),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                icon: Icon(liked ? Icons.favorite : Icons.favorite_border, size: 20),
              ),
              if ((tr.length ?? '').trim().isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(tr.length!.trim(), style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
      );
      if (i != items.length - 1) {
        out.add(Divider(height: 10, color: Theme.of(context).dividerColor.withValues(alpha: 0.5)));
      }
    }
    return out;
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final fg = dark ? Colors.white : Colors.black;
    final bg = dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05);
    final bd = dark ? Colors.white12 : Colors.black12;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: fg),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, {required IconData icon, required String label, required String value}) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final fg = dark ? Colors.white : Colors.black;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: dark ? Colors.white12 : Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text('${context.tr(label)}: $value', style: TextStyle(fontWeight: FontWeight.w800, color: fg)),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String k, String v) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final fg = dark ? Colors.white : Colors.black;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: dark ? Colors.white12 : Colors.black12),
      ),
      child: Text('${context.tr(k)}: $v', style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
    );
  }

  Widget _pricePill(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final fg = dark ? Colors.white : Colors.black;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: _openStorePrices,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: dark ? Colors.white12 : Colors.black12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.euro_symbol, size: 18, color: fg),
            const SizedBox(width: 6),
            Text('${_priceLabel()} ${_priceUpdatedMini()}'.trim(),
                style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }
}
