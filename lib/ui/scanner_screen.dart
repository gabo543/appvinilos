import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/barcode_lookup_service.dart';
import '../services/backup_service.dart';
import '../services/vinyl_add_service.dart';
import 'app_logo.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = _controller.barcodes.listen(_handleCapture);
    unawaited(_controller.start());
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

    switch (state) {
      case AppLifecycleState.resumed:
        if (!_locked) {
          _subscription ??= _controller.barcodes.listen(_handleCapture);
          unawaited(_controller.start());
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
    unawaited(_controller.start());
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
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              final torchOn = state.torchState == TorchState.on;
              return IconButton(
                tooltip: torchOn ? 'Apagar luz' : 'Encender luz',
                icon: Icon(torchOn ? Icons.flash_on : Icons.flash_off),
                onPressed: () => unawaited(_controller.toggleTorch()),
              );
            },
          ),
          IconButton(
            tooltip: 'Cambiar cámara',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => unawaited(_controller.switchCamera()),
          ),
        ],
      ),
      body: Stack(
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
      ),
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
                Text('Código: $code', style: const TextStyle(fontSize: 12)),
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
              Expanded(child: Text('Código: $code', style: const TextStyle(fontSize: 12))),
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
    await BackupService.autoSaveIfEnabled();
    if (!mounted) return;
    setState(() => _saving = false);

    _snack(res.message);
    if (res.ok) {
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
