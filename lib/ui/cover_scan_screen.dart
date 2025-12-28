import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../services/barcode_lookup_service.dart';
import '../services/itunes_search_service.dart';
import '../services/vinyl_add_service.dart';
import '../services/recent_scans_service.dart';
import 'add_vinyl_preview_screen.dart';
import 'app_logo.dart';
import '../l10n/app_strings.dart';

/// Escaneo por carátula en pantalla completa.
///
/// Motivación: en algunos teléfonos, al sacar la foto quedaba poco alto útil
/// (por el AppBar con botones) y se terminaban "cortando" botones/resultados.
/// Esta pantalla ocupa todo, con botón inferior siempre visible.
class CoverScanScreen extends StatefulWidget {
  CoverScanScreen({super.key});

  @override
  State<CoverScanScreen> createState() => _CoverScanScreenState();
}

class _CoverScanScreenState extends State<CoverScanScreen> {
  final ImagePicker _picker = ImagePicker();

  File? _coverFile;
  bool _coverSearching = false;
  String? _coverError;
  String? _coverNote;
  String? _coverOcr;
  String? _coverQuery;
  String? _coverFallbackTerm;
  List<_CoverQueryOption> _coverSuggestions = const [];
  int _coverSuggestionIndex = 0;
  List<BarcodeReleaseHit> _coverHits = const [];
  bool _coverAutoPrompted = false;

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _pickCover({required bool fromCamera}) async {
    try {
      final XFile? x = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 100,
        maxWidth: 2200,
      );
      if (x == null) return;
      final f = File(x.path);
      if (!mounted) return;
      setState(() {
        _coverFile = f;
        _coverSearching = true;
        _coverError = null;
        _coverNote = null;
        _coverOcr = null;
        _coverQuery = null;
        _coverFallbackTerm = null;
        _coverSuggestions = const [];
        _coverSuggestionIndex = 0;
        _coverHits = const [];
        _coverAutoPrompted = false;
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

      bool sameCandidates(List<String> a, List<String> b) {
        if (a.length != b.length) return false;
        for (int i = 0; i < a.length; i++) {
          if (a[i].trim().toLowerCase() != b[i].trim().toLowerCase()) return false;
        }
        return true;
      }

      // 1) Primera pasada: candidatos por geometría (tamaño/posición)
      final geomLines = _extractOcrCandidatesFromRecognized(recognized);
      final rawCandidates = _extractOcrCandidates(raw);

      final primaryCandidates = geomLines.isNotEmpty ? geomLines : rawCandidates;
      final primaryTerm = primaryCandidates.join(' ').trim();
      final fallbackCandidates = (geomLines.isNotEmpty && rawCandidates.isNotEmpty && !sameCandidates(geomLines, rawCandidates))
          ? rawCandidates
          : const <String>[];
      final fallbackTerm = fallbackCandidates.join(' ').trim();

      // Termino base para iTunes.
      final itunesTerm0 = (primaryTerm.isNotEmpty ? primaryTerm : fallbackTerm).trim();

      if (!mounted) return;
      final suggestions = _buildCoverSuggestionsSmart(primaryCandidates);
      setState(() {
        _coverOcr = raw;
        _coverSuggestions = suggestions;
        _coverSuggestionIndex = 0;
        _coverFallbackTerm = itunesTerm0;
        final q0 = (suggestions.isNotEmpty ? suggestions.first.query : itunesTerm0).trim();
        _coverQuery = q0.isEmpty ? null : q0;
      });

      // Si hay varias opciones, las mostramos en bottom sheet (para pantallas chicas).
      int startIndex = 0;
      if (!_coverAutoPrompted && suggestions.length > 1) {
        _coverAutoPrompted = true;
        final picked = await _showCoverSearchOptionsSheet(options: suggestions, selectedIndex: 0);
        if (!mounted) return;
        if (picked != null && picked >= 0 && picked < suggestions.length) {
          startIndex = picked;
          setState(() {
            _coverSuggestionIndex = startIndex;
            _coverQuery = suggestions[startIndex].query;
          });
        }
      }

      if (itunesTerm0.isEmpty) {
        if (!mounted) return;
        setState(() {
          _coverSearching = false;
          _coverError = 'No pude leer texto claro en la carátula. Prueba con más luz o más cerca.';
        });
        return;
      }

      final opts = (suggestions.isNotEmpty)
          ? [
              ...suggestions.sublist(startIndex),
              ...suggestions.sublist(0, startIndex),
            ]
          : [
              _CoverQueryOption(label: 'Buscar', query: itunesTerm0),
            ];

      var outcome = await _searchCoverPipeline(options: opts, itunesTerm: itunesTerm0);

      // 2) Segunda pasada: si no hay hits y teníamos candidatos alternativos (texto crudo), reintenta.
      if (outcome.hits.isEmpty && fallbackCandidates.isNotEmpty && fallbackTerm.isNotEmpty) {
        if (!mounted) return;
        final suggestions2 = _buildCoverSuggestionsSmart(fallbackCandidates);
        setState(() {
          _coverNote = 'Reintentando con texto completo…';
          _coverSuggestions = suggestions2;
          _coverSuggestionIndex = 0;
          _coverFallbackTerm = fallbackTerm;
          final q0 = (suggestions2.isNotEmpty ? suggestions2.first.query : fallbackTerm).trim();
          _coverQuery = q0.isEmpty ? null : q0;
        });

        final opts2 = (suggestions2.isNotEmpty)
            ? suggestions2
            : [
                _CoverQueryOption(label: 'Buscar', query: fallbackTerm),
              ];

        outcome = await _searchCoverPipeline(options: opts2, itunesTerm: fallbackTerm);

        if (!mounted) return;
        setState(() {
          if ((outcome.note ?? '').trim().isNotEmpty) {
            _coverNote = 'Reintento OCR: texto completo. ${outcome.note}'.trim();
          } else {
            _coverNote = 'Reintento OCR: texto completo.';
          }
        });
      }

      if (!mounted) return;
      setState(() {
        _coverHits = _rankHits(outcome.hits);
        _coverSearching = false;
        _coverError = outcome.error;
        _coverNote = outcome.note ?? _coverNote;
        _coverQuery = outcome.usedQuery;
        _coverSuggestionIndex = _matchCoverSuggestionIndex(outcome.usedQuery);
      });

      // Si encontramos hits, ofrecemos continuar con el mejor (botón inferior).
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

  Future<int?> _showCoverSearchOptionsSheet({required List<_CoverQueryOption> options, required int selectedIndex}) async {
    if (!mounted) return null;
    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final t = Theme.of(ctx);
        final cs = t.colorScheme;
        final maxH = MediaQuery.of(ctx).size.height * 0.62;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.tr('Opciones de búsqueda'), style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text(context.tr('Elige la opción que mejor coincida con el texto de la carátula.'), style: t.textTheme.bodySmall),
                SizedBox(height: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, __) => Divider(height: 1),
                    itemBuilder: (_, i) {
                      final opt = options[i];
                      final selected = i == selectedIndex;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(opt.label, style: TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(opt.query, maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: selected ? Icon(Icons.check, color: cs.primary) : null,
                        onTap: () => Navigator.pop(ctx, i),
                      );
                    },
                  ),
                ),
                SizedBox(height: 10),
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('Cerrar'))),
              ],
            ),
          ),
        );
      },
    );
  }

  int _matchCoverSuggestionIndex(String usedQuery) {
    final uq = usedQuery.trim().toLowerCase();
    if (uq.isEmpty) return _coverSuggestionIndex;
    for (int i = 0; i < _coverSuggestions.length; i++) {
      if (_coverSuggestions[i].query.trim().toLowerCase() == uq) return i;
    }
    return _coverSuggestionIndex;
  }

  Future<void> _openCoverSearchOptions() async {
    if (_coverSuggestions.isEmpty) return;
    final picked = await _showCoverSearchOptionsSheet(options: _coverSuggestions, selectedIndex: _coverSuggestionIndex);
    if (!mounted) return;
    if (picked == null) return;
    await _runCoverSearchFromSuggestions(startIndex: picked);
  }

  Future<void> _runCoverSearchFromSuggestions({required int startIndex}) async {
    if (_coverSuggestions.isEmpty) return;
    if (startIndex < 0 || startIndex >= _coverSuggestions.length) return;

    final term = (_coverFallbackTerm ?? _coverSuggestions[startIndex].query).trim();
    final rotated = [
      ..._coverSuggestions.sublist(startIndex),
      ..._coverSuggestions.sublist(0, startIndex),
    ];

    setState(() {
      _coverSuggestionIndex = startIndex;
      _coverSearching = true;
      _coverError = null;
      _coverNote = null;
      _coverHits = const [];
      _coverQuery = _coverSuggestions[startIndex].query;
    });

    final outcome = await _searchCoverPipeline(options: rotated, itunesTerm: term.isEmpty ? rotated.first.query : term);
    if (!mounted) return;

    setState(() {
      _coverHits = _rankHits(outcome.hits);
      _coverSearching = false;
      _coverError = outcome.error;
      _coverNote = outcome.note;
      _coverQuery = outcome.usedQuery;
      _coverSuggestionIndex = _matchCoverSuggestionIndex(outcome.usedQuery);
    });
  }

  Future<void> _editCoverQuery() async {
    final initial = ((_coverQuery ?? _coverFallbackTerm) ?? '').trim();
    if (!mounted) return;
    final ctrl = TextEditingController(text: initial);
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(context.tr('Editar búsqueda')),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(hintText: context.tr('Ej: Pink Floyd Animals')),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('Cancelar'))),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(context.tr('Buscar'))),
          ],
        );
      },
    );

    final q = (picked ?? '').trim();
    if (q.isEmpty) return;

    setState(() {
      _coverSearching = true;
      _coverError = null;
      _coverNote = null;
      _coverHits = const [];
      _coverQuery = q;
    });

    final outcome = await _searchCoverPipeline(options: [_CoverQueryOption(label: 'Buscar', query: q)], itunesTerm: q);
    if (!mounted) return;

    setState(() {
      _coverHits = _rankHits(outcome.hits);
      _coverSearching = false;
      _coverError = outcome.error;
      _coverNote = outcome.note;
      _coverQuery = outcome.usedQuery;
    });
  }

  void _clear() {
    setState(() {
      _coverFile = null;
      _coverSearching = false;
      _coverError = null;
      _coverNote = null;
      _coverOcr = null;
      _coverQuery = null;
      _coverFallbackTerm = null;
      _coverSuggestions = const [];
      _coverSuggestionIndex = 0;
      _coverHits = const [];
      _coverAutoPrompted = false;
    });
  }

  Future<void> _openAddFlow(BarcodeReleaseHit h) async {
    final rgid = (h.releaseGroupId ?? '').trim();
    final rid = (h.releaseId ?? '').trim();

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

    await RecentScansService.add(
      RecentScanEntry(
        artist: h.artist,
        album: h.album,
        releaseGroupId: rgid.isEmpty ? null : rgid,
        releaseId: rid.isEmpty ? null : rid,
        source: 'cover',
        tsMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddVinylPreviewScreen(prepared: prepared)),
    );
  }

  Future<void> _continueBest() async {
    if (_coverHits.isEmpty) return;
    // Pequeña confirmación para que el usuario no se salte el resultado.
    final best = _coverHits.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(context.tr('Abrir ficha del disco')),
          content: Text('${best.artist}\n${best.album}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('Cancelar'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('Continuar'))),
          ],
        );
      },
    );
    if (!mounted) return;
    if (ok != true) return;
    await _openAddFlow(best);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final panelBg = cs.surface.withOpacity(0.92);
    final f = _coverFile;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kAppBarToolbarHeight,
        leadingWidth: appBarLeadingWidthForLogoBack(logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        leading: appBarLeadingLogoBack(context, logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        title: appBarTitleTextScaled(context.tr('Carátula'), padding: const EdgeInsets.only(left: 8)),
        titleSpacing: 12,
        actions: [
          IconButton(
            tooltip: context.tr('Tomar foto'),
            onPressed: _coverSearching ? null : () => unawaited(_pickCover(fromCamera: true)),
            icon: Icon(Icons.photo_camera),
          ),
          IconButton(
            tooltip: context.tr('Galería'),
            onPressed: _coverSearching ? null : () => unawaited(_pickCover(fromCamera: false)),
            icon: Icon(Icons.photo_library),
          ),
          if (_coverSuggestions.isNotEmpty)
            IconButton(
              tooltip: context.tr('Opciones de búsqueda'),
              onPressed: _coverSearching ? null : () => unawaited(_openCoverSearchOptions()),
              icon: Icon(Icons.tune),
            ),
          if ((_coverQuery ?? '').trim().isNotEmpty)
            IconButton(
              tooltip: context.tr('Editar búsqueda'),
              onPressed: _coverSearching ? null : () => unawaited(_editCoverQuery()),
              icon: Icon(Icons.edit),
            ),
          if (f != null)
            IconButton(
              tooltip: context.tr('Limpiar'),
              onPressed: _coverSearching ? null : _clear,
              icon: Icon(Icons.clear),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: FilledButton.icon(
          onPressed: _coverSearching
              ? null
              : (_coverHits.isNotEmpty
                  ? () => unawaited(_continueBest())
                  : () => unawaited(_pickCover(fromCamera: true))),
          icon: Icon(_coverHits.isNotEmpty ? Icons.chevron_right : Icons.photo_camera),
          label: Text(_coverSearching ? 'Buscando…' : (_coverHits.isNotEmpty ? 'Continuar' : 'Tomar foto')),
        ),
      ),
      body: SafeArea(
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
                        Expanded(
                          child: Text(context.tr('Lee la carátula (foto)'), style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                        if (_coverSearching)
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    SizedBox(height: 10),
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          color: cs.surfaceContainerHighest,
                          child: f == null
                              ? Center(
                                  child: Text(
                                    'Toma una foto de la portada.\n\nTip: enfoca el texto (artista y álbum).',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: cs.onSurface.withOpacity(0.75)),
                                  ),
                                )
                              : Image.file(f, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                    if ((_coverQuery ?? '').trim().isNotEmpty) ...[
                      SizedBox(height: 10),
                      Text("${context.tr('Búsqueda')}: ${_coverQuery!}", maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                    if ((_coverNote ?? '').trim().isNotEmpty) ...[
                      SizedBox(height: 6),
                      Text(
                        _coverNote!,
                        style: TextStyle(color: cs.onSurface.withOpacity(0.8), fontWeight: FontWeight.w700),
                      ),
                    ],
                    if ((_coverError ?? '').trim().isNotEmpty) ...[
                      SizedBox(height: 10),
                      Text(_coverError!, style: TextStyle(fontWeight: FontWeight.w800)),
                    ],
                    if ((_coverOcr ?? '').trim().isNotEmpty) ...[
                      SizedBox(height: 8),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(context.tr('Texto detectado')),
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SelectableText(_coverOcr!),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: 12),
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
      ),
    );
  }

  Widget _buildCoverResults() {
    if (_coverSearching) {
      return Center(child: Text(context.tr('Leyendo carátula y buscando…')));
    }
    if (_coverHits.isEmpty) {
      return Center(
        child: Text(
          'Cuando tomes una foto, aquí aparecerán los resultados.\n\nTip: evita reflejos y saca la foto lo más derecha posible.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      itemCount: _coverHits.length,
      separatorBuilder: (_, __) => Divider(height: 1),
      itemBuilder: (context, i) {
        final h = _coverHits[i];
        final rgid = (h.releaseGroupId ?? '').trim();
        final rid = (h.releaseId ?? '').trim();
        final coverRG250 = rgid.isEmpty ? null : 'https://coverartarchive.org/release-group/$rgid/front-250';
        final coverRG500 = rgid.isEmpty ? null : 'https://coverartarchive.org/release-group/$rgid/front-500';
        final coverRel250 = rid.isEmpty ? null : 'https://coverartarchive.org/release/$rid/front-250';
        final coverRel500 = rid.isEmpty ? null : 'https://coverartarchive.org/release/$rid/front-500';
        final primary = (h.coverUrl250 ?? coverRG250 ?? coverRel250);
        final fallback = (h.coverUrl500 ?? coverRG500 ?? coverRel500 ?? coverRel250);

        return ListTile(
          leading: _CoverThumb(primary: primary, fallback: fallback),
          title: Text('${h.artist} — ${h.album}', maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              if ((h.mediaFormat ?? '').trim().isNotEmpty) h.mediaFormat,
              if ((h.year ?? '').isNotEmpty) h.year,
              if ((h.country ?? '').isNotEmpty) h.country,
            ].join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(Icons.chevron_right),
          onTap: () => unawaited(_openAddFlow(h)),
        );
      },
    );
  }

  // ---------------------------
  // Helpers de OCR + búsqueda
  // ---------------------------

  static const List<String> _stopwords = [
    'stereo',
    'mono',
    'remastered',
    'remaster',
    'limited',
    'edition',
    'deluxe',
    'vinyl',
    'lp',
    'record',
    'records',
    'side',
    'a',
    'b',
    'c',
    'd',
    'the',
  ];

  static String _escapeForMb(String s) => s.replaceAll('"', '\\"');

  static List<String> _extractOcrCandidatesFromRecognized(RecognizedText recognized) {
    final items = <({String text, double top, double height, double area})>[];
    for (final b in recognized.blocks) {
      for (final l in b.lines) {
        final t = l.text.trim();
        if (t.length < 3) continue;
        final rect = l.boundingBox;
        final area = rect.width * rect.height;
        items.add((text: t, top: rect.top, height: rect.height, area: area));
      }
    }
    if (items.isEmpty) return [];

    items.sort((a, b) {
      final h = b.height.compareTo(a.height);
      if (h != 0) return h;
      return b.area.compareTo(a.area);
    });
    final picked = items.take(8).toList();
    picked.sort((a, b) => a.top.compareTo(b.top));
    final lines = picked.map((e) => e.text).toList();
    return _cleanOcrLines(lines, limit: 4);
  }

  static List<String> _cleanOcrLines(List<String> lines, {int limit = 4}) {
    final cleaned = <String>[];
    final seen = <String>{};

    for (final raw in lines) {
      final l = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (l.length < 3 || l.length > 45) continue;
      if (RegExp(r'^\d+$').hasMatch(l)) continue;

      final low = l.toLowerCase();
      if (_stopwords.any((w) => low == w || low.contains(' $w ') || low.startsWith('$w ') || low.endsWith(' $w'))) {
        if (low.split(' ').every((p) => _stopwords.contains(p))) continue;
      }

      final key = low.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      if (key.isEmpty) continue;
      if (seen.contains(key)) continue;
      seen.add(key);

      cleaned.add(l);
      if (cleaned.length >= limit) break;
    }

    return cleaned;
  }

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
        if (low.split(' ').every((p) => _stopwords.contains(p))) continue;
      }
      final key = low.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      if (key.isEmpty) continue;
      if (seen.contains(key)) continue;
      seen.add(key);
      cleaned.add(l);
      if (cleaned.length >= 4) break;
    }
    return cleaned;
  }

  static List<_CoverQueryOption> _buildCoverSuggestionsSmart(List<String> candidates) {
    if (candidates.isEmpty) return const [];

    String join2(int a, int b) => [candidates[a], candidates[b]].where((e) => e.trim().isNotEmpty).join(' ').trim();

    final out = <_CoverQueryOption>[];

    if (candidates.length >= 2) {
      final artist = candidates[0];
      final album = candidates[1];
      out.add(_CoverQueryOption(label: 'Exacto', query: 'artist:"${_escapeForMb(artist)}" AND release:"${_escapeForMb(album)}"'));
      out.add(_CoverQueryOption(label: 'Simple', query: '$artist $album'));
      out.add(_CoverQueryOption(label: 'Álbum', query: album));
    }

    if (candidates.length >= 3) {
      final artist12 = join2(0, 1);
      final album3 = candidates[2];
      if (artist12.isNotEmpty && album3.isNotEmpty) {
        out.add(_CoverQueryOption(label: 'Exacto (1+2/3)', query: 'artist:"${_escapeForMb(artist12)}" AND release:"${_escapeForMb(album3)}"'));
        out.add(_CoverQueryOption(label: 'Simple (1+2/3)', query: '$artist12 $album3'));
      }
      final album23 = join2(1, 2);
      final artist1 = candidates[0];
      if (artist1.isNotEmpty && album23.isNotEmpty) {
        out.add(_CoverQueryOption(label: 'Exacto (1/2+3)', query: 'artist:"${_escapeForMb(artist1)}" AND release:"${_escapeForMb(album23)}"'));
        out.add(_CoverQueryOption(label: 'Simple (1/2+3)', query: '$artist1 $album23'));
      }
      out.add(_CoverQueryOption(label: 'Álbum (3)', query: candidates[2]));
    }

    if (candidates.length == 1) {
      out.add(_CoverQueryOption(label: 'Buscar', query: candidates[0]));
    }

    final wide = candidates.take(3).join(' ').trim();
    if (wide.isNotEmpty) {
      out.add(_CoverQueryOption(label: 'Amplio', query: wide));
      out.add(_CoverQueryOption(label: 'Amplio (vinyl)', query: '$wide vinyl'));
    }

    final seen = <String>{};
    final dedup = <_CoverQueryOption>[];
    for (final o in out) {
      final k = o.query.toLowerCase().trim();
      if (k.isEmpty || seen.contains(k)) continue;
      seen.add(k);
      dedup.add(o);
      if (dedup.length >= 8) break;
    }
    return dedup;
  }

  String _mbErrorToHuman(MbErrorKind kind, int? statusCode) {
    switch (kind) {
      case MbErrorKind.rateLimited:
        return 'MusicBrainz está con límite de velocidad (HTTP ${statusCode ?? 429}).';
      case MbErrorKind.serviceUnavailable:
        return 'MusicBrainz no está disponible (HTTP ${statusCode ?? 503}).';
      case MbErrorKind.network:
        return 'No pude conectar con MusicBrainz.';
      case MbErrorKind.unknown:
        return 'Error consultando MusicBrainz.';
      case MbErrorKind.none:
        return '';
    }
  }

  List<BarcodeReleaseHit> _itunesToBarcodeHits(List<ItunesAlbumHit> hits, {required String query}) {
    final out = <BarcodeReleaseHit>[];
    for (final h in hits) {
      out.add(
        BarcodeReleaseHit(
          barcode: query,
          artist: h.artist,
          album: h.album,
          year: h.year,
          country: h.country,
          coverUrl250: h.coverUrl250,
          coverUrl500: h.coverUrl500,
          hasFrontCover: (h.coverUrl250 ?? '').trim().isNotEmpty,
        ),
      );
    }
    return out;
  }

  Future<_CoverSearchOutcome> _searchCoverPipeline({required List<_CoverQueryOption> options, required String itunesTerm}) async {
    MbErrorKind lastErrKind = MbErrorKind.none;
    int? lastStatus;

    for (int i = 0; i < options.length; i++) {
      final opt = options[i];
      final res = await BarcodeLookupService.searchReleasesByTextDetailed(opt.query);
      if (res.hits.isNotEmpty) {
        return _CoverSearchOutcome(hits: res.hits, usedQuery: opt.query);
      }
      if (!res.ok) {
        lastErrKind = res.errorKind;
        lastStatus = res.statusCode;
        break;
      }
    }

    // Fallback iTunes.
    final term = itunesTerm.trim();
    final it = await ItunesSearchService.searchAlbums(term: term.isEmpty ? options.first.query : term, limit: 12);
    if (it.isNotEmpty) {
      final note = lastErrKind == MbErrorKind.none
          ? 'No encontré coincidencias en MusicBrainz. Mostrando resultados de iTunes.'
          : '${_mbErrorToHuman(lastErrKind, lastStatus)} Mostrando resultados de iTunes.';
      return _CoverSearchOutcome(
        hits: _itunesToBarcodeHits(it, query: term.isEmpty ? options.first.query : term),
        usedQuery: term.isEmpty ? options.first.query : term,
        note: note,
      );
    }

    final extra = lastErrKind == MbErrorKind.none ? '' : ' ${_mbErrorToHuman(lastErrKind, lastStatus)}';
    return _CoverSearchOutcome(
      hits: const [],
      usedQuery: (term.isEmpty ? (options.isNotEmpty ? options.first.query : '') : term),
      error: 'No encontré coincidencias. Prueba otra foto o acércate al texto.$extra',
    );
  }

  static int _scoreHit(BarcodeReleaseHit h) {
    int s = 0;
    if (h.isVinyl) s += 5;
    if ((h.mediaFormat ?? '').toLowerCase().contains('vinyl')) s += 3;
    if (h.hasFrontCover) s += 2;
    if ((h.releaseGroupId ?? '').trim().isNotEmpty) s += 2;
    if ((h.releaseId ?? '').trim().isNotEmpty) s += 1;
    if ((h.year ?? '').trim().isNotEmpty) s += 1;
    return s;
  }

  static List<BarcodeReleaseHit> _rankHits(List<BarcodeReleaseHit> hits) {
    final out = List<BarcodeReleaseHit>.from(hits);
    out.sort((a, b) => _scoreHit(b).compareTo(_scoreHit(a)));
    return out;
  }
}

class _CoverQueryOption {
  final String label;
  final String query;
  const _CoverQueryOption({required this.label, required this.query});
}

class _CoverSearchOutcome {
  final List<BarcodeReleaseHit> hits;
  final String usedQuery;
  final String? note;
  final String? error;
  const _CoverSearchOutcome({required this.hits, required this.usedQuery, this.note, this.error});
}

class _CoverThumb extends StatelessWidget {
  final String? primary;
  final String? fallback;
  const _CoverThumb({required this.primary, required this.fallback});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = (primary ?? '').trim();
    final f = (fallback ?? '').trim();
    final url = p.isNotEmpty ? p : (f.isNotEmpty ? f : '');

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 48,
        height: 48,
        color: cs.surfaceContainerHighest,
        child: url.isEmpty
            ? Icon(Icons.album)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  if (p.isNotEmpty && f.isNotEmpty && p != f) {
                    return Image.network(
                      f,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(Icons.album),
                    );
                  }
                  return Icon(Icons.album);
                },
              ),
      ),
    );
  }
}