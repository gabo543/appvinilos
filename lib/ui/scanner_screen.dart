import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/barcode_lookup_service.dart';
import '../services/backup_service.dart';
import '../services/vinyl_add_service.dart';
import '../services/add_defaults_service.dart';
import 'app_logo.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

enum ScannerMode { codigo, caratula }

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  static const _stopwords = <String>{
    'stereo',
    'mono',
    'remastered',
    'remaster',
    'deluxe',
    'edition',
    'limited',
    'side',
    'a',
    'b',
    'lp',
    'vinyl',
    'record',
  };

  ScannerMode _mode = ScannerMode.codigo;

  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  StreamSubscription<BarcodeCapture>? _subscription;

  bool _locked = false; // evita múltiples detecciones antes de mostrar resultados
  String? _barcode;
  bool _searching = false;
  String? _error;
  List<BarcodeReleaseHit> _hits = [];

  // --- Modo carátula ---
  final ImagePicker _picker = ImagePicker();
  File? _coverFile;
  bool _coverSearching = false;
  String? _coverError;
  String? _coverOcr;
  String? _coverQuery;
  List<BarcodeReleaseHit> _coverHits = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = _controller.barcodes.listen(_handleCapture);
    unawaited(_safeStartController());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final sub = _subscription;
    if (sub != null) unawaited(sub.cancel());
    _subscription = null;
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Si no hay permisos (por ejemplo, diálogo), no hacemos start/stop.
    if (!_controller.value.hasCameraPermission) return;

    // En modo carátula no necesitamos mantener la cámara activa.
    if (_mode == ScannerMode.caratula) return;

    switch (state) {
      case AppLifecycleState.resumed:
        if (!_locked) {
          _subscription ??= _controller.barcodes.listen(_handleCapture);
          unawaited(_safeStartController());
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        final sub = _subscription;
        if (sub != null) unawaited(sub.cancel());
        _subscription = null;
        unawaited(_controller.stop());
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_mode != ScannerMode.codigo) return;
    if (_locked) return;
    if (capture.barcodes.isEmpty) return;

    final raw = capture.barcodes.first.rawValue;
    final code = (raw ?? '').trim();
    if (code.isEmpty) return;

    _locked = true;
    unawaited(_controller.stop());
    _searchByBarcode(code);
  }

  Future<void> _searchByBarcode(String code) async {
    setState(() {
      _barcode = code;
      _searching = true;
      _error = null;
      _hits = [];
    });

    try {
      final hits = await BarcodeLookupService.searchReleasesByBarcode(code);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _searching = false;
        _error = hits.isEmpty ? 'No encontré coincidencias para este código.' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = 'Error buscando el código. Revisa tu conexión.';
        _hits = [];
      });
    }
  }

  void _reset() {
    setState(() {
      _barcode = null;
      _searching = false;
      _error = null;
      _hits = [];
    });
    _locked = false;
    if (_mode == ScannerMode.codigo) {
      // En algunos dispositivos el start puede fallar si el permiso aún no está concedido.
      // No queremos que eso rompa la pantalla.
      unawaited(_safeStartController());
    }
  }

  Future<void> _safeStartController() async {
    try {
      await _controller.start();
    } catch (_) {
      // ignore: evitamos crash por permisos/estado de cámara.
    }
  }

  Future<void> _setMode(ScannerMode m) async {
    if (_mode == m) return;

    setState(() {
      _mode = m;
      // Limpieza suave de estado al cambiar.
      _barcode = null;
      _searching = false;
      _error = null;
      _hits = [];
      _locked = false;
      _coverError = null;
      _coverOcr = null;
      _coverQuery = null;
      _coverHits = [];
      _coverSearching = false;
      _coverFile = null;
    });

    if (m == ScannerMode.codigo) {
      _subscription ??= _controller.barcodes.listen(_handleCapture);
      await _safeStartController();
    } else {
      final sub = _subscription;
      if (sub != null) await sub.cancel();
      _subscription = null;
      await _controller.stop();
    }
  }

  Future<void> _pickCover({required bool fromCamera}) async {
    try {
      final XFile? x = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1600,
      );
      if (x == null) return;
      final f = File(x.path);
      if (!mounted) return;
      setState(() {
        _coverFile = f;
        _coverSearching = true;
        _coverError = null;
        _coverOcr = null;
        _coverQuery = null;
        _coverHits = [];
      });
      await _runOcrAndSearch(f);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _coverSearching = false;
        _coverError = 'No pude abrir la cámara/galería.';
      });
    }
  }

  Future<void> _runOcrAndSearch(File f) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(f.path);
      final recognized = await recognizer.processImage(input);
      final raw = recognized.text.trim();

      final candidates = _extractOcrCandidates(raw);
      final query = candidates.isEmpty ? '' : candidates.join(' ');

      if (!mounted) return;
      setState(() {
        _coverOcr = raw;
        _coverQuery = query.isEmpty ? null : query;
      });

      if (query.isEmpty) {
        if (!mounted) return;
        setState(() {
          _coverSearching = false;
          _coverError = 'No pude leer texto claro en la carátula. Prueba con más luz o más cerca.';
        });
        return;
      }

      // Query precisa si tenemos 2 líneas fuertes.
      String q1 = query;
      String? q2;
      if (candidates.length >= 2) {
        final a = _escapeForMb(candidates[0]);
        final b = _escapeForMb(candidates[1]);
        q1 = 'artist:"$a" AND release:"$b"';
        q2 = '${candidates[0]} ${candidates[1]}';
      }

      var hits = await BarcodeLookupService.searchReleasesByText(q1);
      if (hits.isEmpty && q2 != null) {
        hits = await BarcodeLookupService.searchReleasesByText(q2);
      }
      if (!mounted) return;
      setState(() {
        _coverHits = hits;
        _coverSearching = false;
        _coverError = hits.isEmpty ? 'No encontré coincidencias. Prueba otra foto o más cerca del texto.' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _coverSearching = false;
        _coverError = 'Error leyendo la carátula. Revisa permisos y conexión.';
      });
    } finally {
      await recognizer.close();
    }
  }

  static String _escapeForMb(String s) => s.replaceAll('"', '\\"');

  static List<String> _extractOcrCandidates(String raw) {
    if (raw.trim().isEmpty) return [];
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.length >= 3 && e.length <= 45)
        .map((e) => e.replaceAll(RegExp(r'\s+'), ' '))
        .where((e) => !RegExp(r'^\d+$').hasMatch(e))
        .toList();

    final cleaned = <String>[];
    final seen = <String>{};
    for (final l in lines) {
      final low = l.toLowerCase();
      if (_stopwords.any((w) => low == w || low.contains(' $w ') || low.startsWith('$w ') || low.endsWith(' $w'))) {
        // Solo filtramos líneas que sean básicamente ruido.
        if (low.split(' ').every((p) => _stopwords.contains(p))) continue;
      }
      final key = low.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      if (key.isEmpty) continue;
      if (seen.contains(key)) continue;
      seen.add(key);
      cleaned.add(l);
      if (cleaned.length >= 2) break;
    }
    return cleaned;
  }

  Future<void> _openAddFlow(BarcodeReleaseHit h) async {
    final rgid = (h.releaseGroupId ?? '').trim();
    final rid = (h.releaseId ?? '').trim();

    // Prepara metadata.
    // - Si tenemos releaseGroupId: optimizamos y además dejamos fallback de carátula por releaseId.
    // - Si no tenemos releaseGroupId: hacemos la ruta normal (puede ser más lenta, pero funciona).
    _snack('Preparando…');
    PreparedVinylAdd prepared;
    try {
      if (rgid.isNotEmpty) {
        prepared = await VinylAddService.prepareFromReleaseGroup(
          artist: h.artist,
          album: h.album,
          releaseGroupId: rgid,
          releaseId: rid.isEmpty ? null : rid,
          year: h.year,
          artistId: h.artistId,
        );
      } else {
        prepared = await VinylAddService.prepare(
          artist: h.artist,
          album: h.album,
          artistId: h.artistId,
        );
      }
    } catch (_) {
      _snack('No pude preparar la info.');
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddPreparedSheet(prepared: prepared),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final panelBg = cs.surface.withOpacity(0.92);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kAppBarToolbarHeight,
        leadingWidth: appBarLeadingWidthForLogoBack(logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        leading: appBarLeadingLogoBack(context, logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        title: const Text('Escanear'),
        titleSpacing: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SegmentedButton<ScannerMode>(
              segments: const [
                ButtonSegment<ScannerMode>(value: ScannerMode.codigo, label: Text('Código'), icon: Icon(Icons.qr_code_2)),
                ButtonSegment<ScannerMode>(value: ScannerMode.caratula, label: Text('Carátula'), icon: Icon(Icons.image_search)),
              ],
              selected: <ScannerMode>{_mode},
              onSelectionChanged: (s) => unawaited(_setMode(s.first)),
              showSelectedIcon: false,
            ),
          ),
        ),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              final torchOn = state.torchState == TorchState.on;
              return IconButton(
                tooltip: torchOn ? 'Apagar luz' : 'Encender luz',
                icon: Icon(torchOn ? Icons.flash_on : Icons.flash_off),
                onPressed: _mode == ScannerMode.codigo ? () => unawaited(_controller.toggleTorch()) : null,
              );
            },
          ),
          IconButton(
            tooltip: 'Cambiar cámara',
            icon: const Icon(Icons.cameraswitch),
            onPressed: _mode == ScannerMode.codigo ? () => unawaited(_controller.switchCamera()) : null,
          ),
        ],
      ),
      body: _mode == ScannerMode.codigo
          ? _buildBarcodeBody(panelBg: panelBg, cs: cs)
          : _buildCoverBody(panelBg: panelBg, cs: cs),
    );
  }

  Widget _buildBarcodeBody({required Color panelBg, required ColorScheme cs}) {
    return Stack(
      children: [
        MobileScanner(
          controller: _controller,
          errorBuilder: (context, error) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No se pudo abrir la cámara.\n${error.errorDetails?.message ?? ''}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          },
        ),

        // Overlay simple (marco)
        IgnorePointer(
          child: Center(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.75), width: 2),
              ),
            ),
          ),
        ),

        // Panel inferior con estado/resultados
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: panelBg,
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
              child: _buildPanelContent(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCoverBody({required Color panelBg, required ColorScheme cs}) {
    final f = _coverFile;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: panelBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Lee la carátula (foto)', style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                      if (_coverSearching) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        color: cs.surfaceContainerHighest,
                        child: f == null
                            ? Center(
                                child: Text(
                                  'Toma una foto de la portada\n(con buen texto y buena luz)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: cs.onSurface.withOpacity(0.8)),
                                ),
                              )
                            : Image.file(f, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: _coverSearching ? null : () => unawaited(_pickCover(fromCamera: true)),
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Tomar foto'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _coverSearching ? null : () => unawaited(_pickCover(fromCamera: false)),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Galería'),
                      ),
                      if (f != null)
                        TextButton.icon(
                          onPressed: _coverSearching
                              ? null
                              : () {
                                  setState(() {
                                    _coverFile = null;
                                    _coverOcr = null;
                                    _coverQuery = null;
                                    _coverHits = [];
                                    _coverError = null;
                                  });
                                },
                          icon: const Icon(Icons.clear),
                          label: const Text('Limpiar'),
                        ),
                    ],
                  ),
                  if ((_coverQuery ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Búsqueda: ${_coverQuery!}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  if (_coverError != null) ...[
                    const SizedBox(height: 10),
                    Text(_coverError!, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: panelBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: _buildCoverResults(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverResults() {
    if (_coverSearching) {
      return const Center(child: Text('Leyendo carátula y buscando…'));
    }
    if (_coverHits.isEmpty) {
      return Center(
        child: Text(
          'Cuando tomes una foto, aquí aparecerán los resultados.\n\nTip: enfoca el texto (artista y álbum) y evita reflejos.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      itemCount: _coverHits.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final h = _coverHits[i];
        final rgid = (h.releaseGroupId ?? '').trim();
        final rid = (h.releaseId ?? '').trim();
        final coverRG = rgid.isEmpty ? null : 'https://coverartarchive.org/release-group/$rgid/front-250';
        final coverRel = rid.isEmpty ? null : 'https://coverartarchive.org/release/$rid/front-250';
        return ListTile(
          leading: _CoverThumb(primary: coverRG, fallback: coverRel),
          title: Text('${h.artist} — ${h.album}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [if ((h.year ?? '').isNotEmpty) h.year, if ((h.country ?? '').isNotEmpty) h.country].join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openAddFlow(h),
        );
      },
    );
  }

  Widget _buildPanelContent() {
    final code = _barcode;

    if (code == null) {
      return Row(
        key: const ValueKey('idle'),
        children: [
          const Expanded(
            child: Text(
              'Apunta al código de barras del vinilo.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh),
            label: const Text('Listo'),
          ),
        ],
      );
    }

    if (_searching) {
      return Row(
        key: const ValueKey('searching'),
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Buscando en MusicBrainz…', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('Código: $code', style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      );
    }

    if (_error != null) {
      return Column(
        key: const ValueKey('error'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Text('Código: $code', style: const TextStyle(fontSize: 14))),
              TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Escanear otro'),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      key: const ValueKey('results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Resultados (${_hits.length}) — $code',
                style: const TextStyle(fontWeight: FontWeight.w900),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Otro'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _hits.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final h = _hits[i];
              final rgid = (h.releaseGroupId ?? '').trim();
              final rid = (h.releaseId ?? '').trim();
              final coverRG = rgid.isEmpty ? null : 'https://coverartarchive.org/release-group/$rgid/front-250';
              final coverRel = rid.isEmpty ? null : 'https://coverartarchive.org/release/$rid/front-250';
              return ListTile(
                leading: _CoverThumb(primary: coverRG, fallback: coverRel),
                title: Text('${h.artist} — ${h.album}', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [if ((h.year ?? '').isNotEmpty) h.year, if ((h.country ?? '').isNotEmpty) h.country].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openAddFlow(h),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CoverThumb extends StatelessWidget {
  final String? primary;
  final String? fallback;

  const _CoverThumb({required this.primary, required this.fallback});

  @override
  Widget build(BuildContext context) {
    final p = (primary ?? '').trim();
    final f = (fallback ?? '').trim();
    if (p.isEmpty && f.isEmpty) {
      return const Icon(Icons.album);
    }

    Widget buildImg(String url, {Widget? onErr}) {
      return Image.network(
        url,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => onErr ?? const Icon(Icons.album),
      );
    }

    final img = p.isNotEmpty
        ? buildImg(
            p,
            onErr: f.isNotEmpty ? buildImg(f) : const Icon(Icons.album),
          )
        : buildImg(f);

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: img,
    );
  }
}

class _AddPreparedSheet extends StatefulWidget {
  final PreparedVinylAdd prepared;
  const _AddPreparedSheet({required this.prepared});

  @override
  State<_AddPreparedSheet> createState() => _AddPreparedSheetState();
}

class _AddPreparedSheetState extends State<_AddPreparedSheet> {
  late final TextEditingController _yearCtrl;
  bool _saving = false;

  String _condition = 'VG+';
  String _format = 'LP';

  @override
  void initState() {
    super.initState();
    _yearCtrl = TextEditingController(text: widget.prepared.year ?? '');
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    try {
      final c = await AddDefaultsService.getLastCondition(fallback: _condition);
      final f = await AddDefaultsService.getLastFormat(fallback: _format);
      if (!mounted) return;
      setState(() {
        _condition = c;
        _format = f;
      });
    } catch (_) {
      // no-op: si falla prefs, dejamos defaults
    }
  }

  @override
  void dispose() {
    _yearCtrl.dispose();
    super.dispose();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _add() async {
    if (_saving) return;
    setState(() => _saving = true);
    final res = await VinylAddService.addPrepared(
      widget.prepared,
      overrideYear: _yearCtrl.text.trim().isEmpty ? null : _yearCtrl.text.trim(),
      favorite: false,
      condition: _condition,
      format: _format,
    );

    // Guarda las últimas opciones para el próximo agregado.
    await BackupService.autoSaveIfEnabled();
    if (!mounted) return;
    setState(() => _saving = false);

    _snack(res.message);
    if (res.ok) {
      await AddDefaultsService.saveLast(condition: _condition, format: _format);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final p = widget.prepared;
    final cover = p.selectedCover500 ?? p.selectedCover250;
    final fallback = p.coverFallback500 ?? p.coverFallback250;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 6,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Agregar a tu lista',
                  style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              if (_saving) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 92,
                  height: 92,
                  color: cs.surfaceContainerHighest,
                  child: ((cover ?? '').trim().isEmpty && (fallback ?? '').trim().isEmpty)
                      ? const Icon(Icons.album, size: 34)
                      : Image.network(
                          ((cover ?? '').trim().isNotEmpty) ? cover! : fallback!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) {
                            final c = (cover ?? '').trim();
                            final f = (fallback ?? '').trim();

                            // Si falló el primary y existe fallback, lo intentamos.
                            if (c.isNotEmpty && f.isNotEmpty) {
                              return Image.network(
                                fallback!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.album, size: 34),
                              );
                            }
                            return const Icon(Icons.album, size: 34);
                          },
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.artist, style: const TextStyle(fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(p.album, style: const TextStyle(fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _yearCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Año',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ✅ Selector simple de carátula (máx 5 candidatos)
                    if (p.coverCandidates.length > 1)
                      SizedBox(
                        height: 54,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: p.coverCandidates.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 10),
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
                                  child: (url.isEmpty)
                                      ? const Center(child: Icon(Icons.album, size: 20))
                                      : Image.network(
                                          url,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.album, size: 20)),
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _condition,
                            decoration: const InputDecoration(
                              labelText: 'Condición',
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(value: 'M', child: Text('M (Mint)')),
                              DropdownMenuItem(value: 'NM', child: Text('NM (Near Mint)')),
                              DropdownMenuItem(value: 'VG+', child: Text('VG+')),
                              DropdownMenuItem(value: 'VG', child: Text('VG')),
                              DropdownMenuItem(value: 'G', child: Text('G')),
                            ],
                            onChanged: (v) => setState(() => _condition = v ?? _condition),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _format,
                            decoration: const InputDecoration(
                              labelText: 'Formato',
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(value: 'LP', child: Text('LP')),
                              DropdownMenuItem(value: 'EP', child: Text('EP')),
                              DropdownMenuItem(value: 'Single', child: Text('Single')),
                              DropdownMenuItem(value: '2xLP', child: Text('2xLP')),
                            ],
                            onChanged: (v) => setState(() => _format = v ?? _format),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if ((p.genre ?? '').trim().isNotEmpty || (p.country ?? '').trim().isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if ((p.genre ?? '').trim().isNotEmpty)
                  Chip(
                    label: Text(p.genre!.trim(), style: const TextStyle(fontWeight: FontWeight.w800)),
                    visualDensity: VisualDensity.compact,
                  ),
                if ((p.country ?? '').trim().isNotEmpty)
                  Chip(
                    label: Text(p.country!.trim(), style: const TextStyle(fontWeight: FontWeight.w800)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _add,
            icon: const Icon(Icons.check),
            label: const Text('Aceptar'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }
}
