import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/barcode_lookup_service.dart';
import '../services/itunes_search_service.dart';
import '../services/backup_service.dart';
import '../services/audio_recognition_service.dart';
import '../services/vinyl_add_service.dart';
import '../services/add_defaults_service.dart';
import '../db/vinyl_db.dart';
import 'app_logo.dart';
import 'add_vinyl_preview_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

enum ScannerMode { codigo, caratula, escuchar }

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
  String? _coverNote;
  String? _coverOcr;
  String? _coverQuery;
  String? _coverFallbackTerm;
  List<_CoverQueryOption> _coverSuggestions = const [];
  int _coverSuggestionIndex = 0;
  List<BarcodeReleaseHit> _coverHits = [];
  bool _coverAutoPrompted = false;

  // --- Modo escuchar ---
  final Record _recorder = Record();
  bool _listening = false;
  bool _listenIdentifying = false;
  String? _listenError;
  AudioRecognitionResult? _listenResult;
  File? _listenFile;
  List<_ListenQueryOption> _listenSuggestions = const [];
  int _listenSuggestionIndex = 0;
  String? _listenQuery;
  String? _listenNote;
  List<BarcodeReleaseHit> _listenHits = [];
  bool _listenAutoPrompted = false;

  int _scoreHit(BarcodeReleaseHit h) {
    int s = 0;
    if (h.isVinyl) s += 4;
    final mf = (h.mediaFormat ?? '').toLowerCase();
    if (mf.contains('vinyl')) s += 1;
    if (h.hasFrontCover) s += 3;
    if ((h.year ?? '').trim().isNotEmpty) s += 1;
    if ((h.country ?? '').trim().isNotEmpty) s += 1;
    return s;
  }

  List<BarcodeReleaseHit> _rankHits(List<BarcodeReleaseHit> hits) {
    final list = [...hits];
    list.sort((a, b) {
      final sa = _scoreHit(a);
      final sb = _scoreHit(b);
      if (sa != sb) return sb.compareTo(sa);
      // Desempates suaves: preferimos título más corto (suele ser el álbum "principal")
      return (a.album.length).compareTo(b.album.length);
    });
    return list;
  }

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
    // Limpieza modo escuchar
    unawaited(_recorder.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Modo escuchar: cortamos grabación si la app se va a segundo plano.
    if (_mode == ScannerMode.escuchar) {
      switch (state) {
        case AppLifecycleState.resumed:
          break;
        case AppLifecycleState.inactive:
        case AppLifecycleState.paused:
        case AppLifecycleState.hidden:
          if (_listening) unawaited(_stopListening());
          break;
        case AppLifecycleState.detached:
          break;
      }
      return;
    }

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
      final ranked = _rankHits(hits);
      if (!mounted) return;
      setState(() {
        _hits = ranked;
        _searching = false;
        _error = ranked.isEmpty ? 'No encontré coincidencias para este código.' : null;
      });

      // Auto-selección si hay una coincidencia muy clara.
      if (ranked.isNotEmpty) {
        final best = ranked.first;
        final bestScore = _scoreHit(best);
        final secondScore = ranked.length >= 2 ? _scoreHit(ranked[1]) : -999;
        final strong = ranked.length == 1 || (bestScore >= 7 && (bestScore - secondScore) >= 3);
        if (strong) {
          Future.microtask(() async {
            if (!mounted) return;
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) {
                return AlertDialog(
                  title: const Text('Coincidencia encontrada'),
                  content: Text('${best.artist}\n${best.album}'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuar')),
                  ],
                );
              },
            );
            if (ok == true) {
              await _openAddFlow(best);
            } else {
              _reset();
            }
          });
        }
      }
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

    // Si estábamos grabando audio, detenemos antes de cambiar de modo.
    if (_mode == ScannerMode.escuchar && _listening) {
      try {
        await _recorder.stop();
      } catch (_) {
        // ignore
      }
    }

    // Si el usuario salió de la pantalla mientras esperábamos, evitamos setState.
    if (!mounted) return;

    setState(() {
      _mode = m;
      // Limpieza suave de estado al cambiar.
      _barcode = null;
      _searching = false;
      _error = null;
      _hits = [];
      _locked = false;
      _coverError = null;
      _coverNote = null;
      _coverOcr = null;
      _coverQuery = null;
      _coverFallbackTerm = null;
      _coverSuggestions = const [];
      _coverSuggestionIndex = 0;
      _coverHits = [];
      _coverSearching = false;
      _coverFile = null;
      _coverAutoPrompted = false;

      _listening = false;
      _listenIdentifying = false;
      _listenError = null;
      _listenResult = null;
      _listenFile = null;
      _listenSuggestions = const [];
      _listenSuggestionIndex = 0;
      _listenQuery = null;
      _listenNote = null;
      _listenHits = [];
      _listenAutoPrompted = false;
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
        // Mejor OCR: más resolución (sin pasarnos para evitar OOM).
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
        _coverHits = [];
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

      // 1) Extraemos líneas "buenas" usando geometría (tamaño/posición), pero si no encontramos
      //    hits reintentamos con el OCR "crudo" (texto completo). En muchos covers el OCR
      //    grande puede tomar ruido (sellos/"STEREO") y dejar fuera artista/álbum.
      final geomLines = _extractOcrCandidatesFromRecognized(recognized);
      final rawCandidates = _extractOcrCandidates(raw);

      final primaryCandidates = geomLines.isNotEmpty ? geomLines : rawCandidates;
      final primaryTerm = primaryCandidates.join(' ').trim();
      final fallbackCandidates = (geomLines.isNotEmpty && rawCandidates.isNotEmpty && !sameCandidates(geomLines, rawCandidates))
          ? rawCandidates
          : const <String>[];
      final fallbackTerm = fallbackCandidates.join(' ').trim();

      // Termino "de respaldo" para iTunes: si el primario queda vacío, usamos el crudo.
      final itunesTerm0 = (primaryTerm.isNotEmpty ? primaryTerm : fallbackTerm).trim();

      if (!mounted) return;
      final suggestions = _buildCoverSuggestionsSmart(primaryCandidates);
      if (!mounted) return;
      setState(() {
        _coverOcr = raw;
        _coverSuggestions = suggestions;
        _coverSuggestionIndex = 0;
        _coverFallbackTerm = itunesTerm0;
        _coverQuery = (suggestions.isNotEmpty ? suggestions.first.query : itunesTerm0).trim().isEmpty
            ? null
            : (suggestions.isNotEmpty ? suggestions.first.query : itunesTerm0);
      });

      // ✅ En algunos teléfonos, mostrar todas las opciones debajo de la foto deja el "menú" fuera
      // de pantalla. En vez de eso, ofrecemos las opciones en un Bottom Sheet.
      int startIndex = 0;
      if (!_coverAutoPrompted && suggestions.length > 1) {
        _coverAutoPrompted = true;
        final picked = await _showCoverSearchOptionsSheet(
          options: suggestions,
          selectedIndex: 0,
        );
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

      // 2) Pipeline automático (Exacto → Simple → Álbum → Amplio). Si no hay hits o MB falla,
      //    hacemos fallback a iTunes (sin API key).
      final opts = (suggestions.isNotEmpty)
          ? [
              ...suggestions.sublist(startIndex),
              ...suggestions.sublist(0, startIndex),
            ]
          : [
              _CoverQueryOption(label: 'Buscar', query: itunesTerm0),
            ];

      var outcome = await _searchCoverPipeline(
        options: opts,
        itunesTerm: itunesTerm0,
      );

      // 3) Si no hubo resultados con la lectura por geometría, reintentamos con el OCR crudo.
      if (outcome.hits.isEmpty && fallbackCandidates.isNotEmpty && fallbackTerm.isNotEmpty) {
        if (!mounted) return;
        final suggestions2 = _buildCoverSuggestionsSmart(fallbackCandidates);
        setState(() {
          _coverNote = 'Reintentando con texto completo…';
          _coverSuggestions = suggestions2;
          _coverSuggestionIndex = 0;
          _coverFallbackTerm = fallbackTerm;
          _coverQuery = (suggestions2.isNotEmpty ? suggestions2.first.query : fallbackTerm).trim().isEmpty
              ? null
              : (suggestions2.isNotEmpty ? suggestions2.first.query : fallbackTerm);
        });

        final opts2 = (suggestions2.isNotEmpty)
            ? suggestions2
            : [
                _CoverQueryOption(label: 'Buscar', query: fallbackTerm),
              ];

        outcome = await _searchCoverPipeline(
          options: opts2,
          itunesTerm: fallbackTerm,
        );

        // Si igual no hay hits, mantenemos la nota del reintento + nota del outcome si existe.
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
      final usedIdx = _matchCoverSuggestionIndex(outcome.usedQuery);
      setState(() {
        _coverHits = _rankHits(outcome.hits);
        _coverSearching = false;
        _coverError = outcome.error;
        _coverNote = outcome.note ?? _coverNote;
        _coverQuery = outcome.usedQuery;
        _coverSuggestionIndex = usedIdx;
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

  // ---------------------------
  // MODO ESCUCHAR (AUDIO)
  // ---------------------------

  Future<void> _startListening() async {
    if (_listening || _listenIdentifying) return;

    final token = await AudioRecognitionService.getToken();
    if (!mounted) return;
    if (token == null) {
      _snack('Configura el token en Ajustes → Reconocimiento (Escuchar).');
      return;
    }

    final hasPerm = await _recorder.hasPermission();
    if (!mounted) return;
    if (!hasPerm) {
      _snack('Permiso de micrófono denegado.');
      return;
    }

    final dir = await getTemporaryDirectory();
    if (!mounted) return;
    final path = '${dir.path}/gabolp_listen_${DateTime.now().millisecondsSinceEpoch}.m4a';

    setState(() {
      _listening = true;
      _listenIdentifying = false;
      _listenError = null;
      _listenResult = null;
      _listenFile = null;
      _listenSuggestions = const [];
      _listenSuggestionIndex = 0;
      _listenQuery = null;
      _listenNote = null;
      _listenHits = [];
      _listenAutoPrompted = false;
    });

    try {
    await _recorder.start(
      path: path,
      encoder: AudioEncoder.aacLc,
      bitRate: 128000,
      // record 4.x usa `samplingRate` (no `sampleRate`).
      samplingRate: 44100,
    );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _listening = false;
        _listenError = 'No pude iniciar la grabación.';
      });
      return;
    }

    // Auto-detener a los ~8s para que sea rápido y barato.
    unawaited(() async {
      await Future.delayed(const Duration(seconds: 8));
      if (!mounted) return;
      if (_mode != ScannerMode.escuchar) return;
      if (_listening) await _stopListening();
    }());
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    if (!mounted) return;
    setState(() {
      _listening = false;
      _listenIdentifying = true;
      _listenError = null;
    });

    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = null;
    }

    if (path == null || path.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _listenIdentifying = false;
        _listenError = 'No se pudo guardar el audio.';
      });
      return;
    }

    final f = File(path);
    if (!mounted) return;
    setState(() => _listenFile = f);

    final res = await AudioRecognitionService.identifyFromFile(f);
    if (!mounted) return;

    if (!res.ok) {
      setState(() {
        _listenIdentifying = false;
        _listenError = res.error ?? 'No se pudo reconocer.';
        _listenResult = null;
        _listenHits = [];
        _listenSuggestions = const [];
        _listenQuery = null;
      });
      return;
    }

    // Construimos sugerencias de búsqueda a partir del resultado.
    final suggestions = _buildListenSuggestions(res);
    final baseTerm = _buildListenItunesTerm(res);
    final fallbackQuery = baseTerm.isEmpty ? '${res.artist} ${res.title}'.trim() : baseTerm;

    final options = suggestions.isNotEmpty
        ? suggestions
        : [
            _ListenQueryOption(label: 'Buscar', query: fallbackQuery),
          ];

    setState(() {
      _listenResult = res;
      _listenSuggestions = options;
      _listenSuggestionIndex = 0;
      _listenQuery = null;
      _listenNote = null;
    });

    final firstQ = options.isNotEmpty ? options.first.query.trim() : '';
    if (firstQ.isEmpty) {
      setState(() {
        _listenIdentifying = false;
        _listenError = 'Reconocí la canción pero no pude armar una búsqueda.';
      });
      return;
    }

    final outcome = await _searchListenPipeline(
      options: options,
      itunesTerm: fallbackQuery,
    );
    if (!mounted) return;

    final ranked = _rankHits(outcome.hits);
    setState(() {
      _listenHits = ranked;
      _listenIdentifying = false;
      _listenError = outcome.error;
      _listenNote = outcome.note;
      _listenQuery = outcome.usedQuery.trim().isEmpty ? null : outcome.usedQuery;
      _listenSuggestionIndex = outcome.usedSuggestionIndex ?? 0;
    });

    // Si tenemos artista + álbum, ofrecemos abrir la ficha del álbum más probable.
    // Esto evita que el usuario tenga que tocar manualmente un resultado cada vez.
    unawaited(_maybePromptOpenListenFlow(res, ranked));
  }

  static List<_ListenQueryOption> _buildListenSuggestions(AudioRecognitionResult r) {
    final artist = (r.artist ?? '').trim();
    final title = (r.title ?? '').trim();
    final album = (r.album ?? '').trim();
    if (artist.isEmpty && title.isEmpty) return const [];

    final out = <_ListenQueryOption>[];

    if (artist.isNotEmpty && album.isNotEmpty) {
      final a = _escapeForMb(artist);
      final al = _escapeForMb(album);
      out.add(_ListenQueryOption(label: 'Álbum (Exacto)', query: 'artist:"$a" AND release:"$al"'));
      out.add(_ListenQueryOption(label: 'Álbum (Simple)', query: '$artist $album'));
      out.add(_ListenQueryOption(label: 'Solo álbum', query: album));
    }

    // Cuando no hay álbum, intentamos con artista + canción (puede encontrar singles/EPs)
    final base = [artist, title].where((e) => e.isNotEmpty).join(' ');
    if (base.isNotEmpty) {
      out.add(_ListenQueryOption(label: 'Canción', query: base));
      out.add(_ListenQueryOption(label: 'Canción (Vinyl)', query: '$base vinyl'));
    }

    // Evita duplicados
    final seen = <String>{};
    final dedup = <_ListenQueryOption>[];
    for (final o in out) {
      final k = o.query.toLowerCase().trim();
      if (k.isEmpty || seen.contains(k)) continue;
      seen.add(k);
      dedup.add(o);
    }
    return dedup;
  }

  static String _buildListenItunesTerm(AudioRecognitionResult r) {
    final artist = (r.artist ?? '').trim();
    final title = (r.title ?? '').trim();
    final album = (r.album ?? '').trim();

    if (artist.isNotEmpty && album.isNotEmpty) {
      return '$artist $album'.trim();
    }
    return [artist, title].where((e) => e.isNotEmpty).join(' ').trim();
  }

  Future<void> _maybePromptOpenListenFlow(AudioRecognitionResult res, List<BarcodeReleaseHit> rankedHits) async {
    if (!mounted) return;
    if (_mode != ScannerMode.escuchar) return;
    if (_listenAutoPrompted) return;

    final artist = (res.artist ?? '').trim();
    final album = (res.album ?? '').trim();
    if (artist.isEmpty || album.isEmpty) return;

    // Marcamos antes de abrir para no repetir el diálogo con el mismo resultado.
    _listenAutoPrompted = true;

    final hasHits = rankedHits.isNotEmpty;
    final best = hasHits ? rankedHits.first : null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Álbum encontrado'),
          content: Text(
            hasHits
                ? '${best!.artist}\n${best.album}'
                : '$artist\n$album\n\nNo encontré el release exacto, pero puedo abrir la ficha con esta info.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuar')),
          ],
        );
      },
    );
    if (!mounted) return;
    if (ok != true) return;

    if (best != null) {
      await _openAddFlow(best);
    } else {
      await _openAddFlowFromArtistAlbum(artist: artist, album: album);
    }
  }

  Future<void> _continueFromListenResult() async {
    final res = _listenResult;
    if (res == null) return;
    final artist = (res.artist ?? '').trim();
    final album = (res.album ?? '').trim();
    if (artist.isEmpty || album.isEmpty) {
      _snack('No tengo artista y álbum para continuar.');
      return;
    }

    if (_listenHits.isNotEmpty) {
      await _openAddFlow(_listenHits.first);
    } else {
      await _openAddFlowFromArtistAlbum(artist: artist, album: album);
    }
  }


  Future<void> _searchByListenQuery(String q, {int? suggestionIndex}) async {
    final query = q.trim();
    if (query.isEmpty) return;

    final itunesTerm = _listenResult != null ? _buildListenItunesTerm(_listenResult!) : query;

    setState(() {
      _listenIdentifying = true;
      _listenError = null;
      _listenNote = null;
      _listenHits = [];
      _listenQuery = query;
      if (suggestionIndex != null) _listenSuggestionIndex = suggestionIndex;
    });

    final outcome = await _searchListenPipeline(
      options: [
        _ListenQueryOption(label: 'Buscar', query: query),
      ],
      itunesTerm: itunesTerm.isEmpty ? query : itunesTerm,
      suggestionIndexBase: suggestionIndex,
    );
    if (!mounted) return;

    setState(() {
      _listenHits = _rankHits(outcome.hits);
      _listenIdentifying = false;
      _listenError = outcome.error;
      _listenNote = outcome.note;
      _listenQuery = outcome.usedQuery.trim().isEmpty ? null : outcome.usedQuery;
      if (outcome.usedSuggestionIndex != null) {
        _listenSuggestionIndex = outcome.usedSuggestionIndex!;
      }
    });
  }

  Future<String?> _askWishlistStatus() async {
    String picked = 'Por comprar';
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Estado (wishlist)'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    value: 'Por comprar',
                    groupValue: picked,
                    title: const Text('Por comprar'),
                    onChanged: (v) => setStateDialog(() => picked = v ?? picked),
                  ),
                  RadioListTile<String>(
                    value: 'Buscando',
                    groupValue: picked,
                    title: const Text('Buscando'),
                    onChanged: (v) => setStateDialog(() => picked = v ?? picked),
                  ),
                  RadioListTile<String>(
                    value: 'Comprado',
                    groupValue: picked,
                    title: const Text('Comprado'),
                    onChanged: (v) => setStateDialog(() => picked = v ?? picked),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                ElevatedButton(onPressed: () => Navigator.pop(ctx, picked), child: const Text('Aceptar')),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addHitToWishlist(BarcodeReleaseHit h) async {
    final status = await _askWishlistStatus();
    if (status == null) return;

    PreparedVinylAdd prepared;
    try {
      prepared = await _prepareHit(h);
    } catch (_) {
      _snack('No pude preparar la info.');
      return;
    }

    final cover250 = prepared.selectedCover250 ?? prepared.coverFallback250;
    final cover500 = prepared.selectedCover500 ?? prepared.coverFallback500;

    await VinylDb.instance.addToWishlist(
      artista: prepared.artist,
      album: prepared.album,
      year: prepared.year,
      cover250: cover250,
      cover500: cover500,
      artistId: prepared.artistId,
      status: status,
    );

    await BackupService.autoSaveIfEnabled();
    _snack('Agregado a wishlist ✅');
  }

  Future<PreparedVinylAdd> _prepareHit(BarcodeReleaseHit h) async {
    final rgid = (h.releaseGroupId ?? '').trim();
    final rid = (h.releaseId ?? '').trim();
    if (rgid.isNotEmpty) {
      return VinylAddService.prepareFromReleaseGroup(
        artist: h.artist,
        album: h.album,
        releaseGroupId: rgid,
        releaseId: rid.isEmpty ? null : rid,
        year: h.year,
        artistId: h.artistId,
      );
    }
    return VinylAddService.prepare(
      artist: h.artist,
      album: h.album,
      artistId: h.artistId,
    );
  }

  static String _escapeForMb(String s) => s.replaceAll('"', '\\"');

  /// Extrae mejores candidatos de OCR usando geometría (líneas más grandes) para evitar
  /// que el OCR meta ruido (sellos, "stereo", etc.) en la búsqueda.
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

    // Elegimos las líneas "más grandes" primero (típicamente artista/álbum),
    // luego las ordenamos por posición vertical para mantener lectura natural.
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
      // Filtra líneas que sean básicamente ruido.
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

  /// Construye sugerencias más "inteligentes" para el caso típico de carátulas:
  /// a veces el artista viene partido en 2 líneas ("PINK" / "FLOYD").
  static List<_CoverQueryOption> _buildCoverSuggestionsSmart(List<String> candidates) {
    if (candidates.isEmpty) return const [];

    String join2(int a, int b) => [candidates[a], candidates[b]].where((e) => e.trim().isNotEmpty).join(' ').trim();

    final out = <_CoverQueryOption>[];

    // Caso 2+ líneas: lo clásico (artista + álbum)
    if (candidates.length >= 2) {
      final artist = candidates[0];
      final album = candidates[1];
      out.add(_CoverQueryOption(label: 'Exacto', query: 'artist:"${_escapeForMb(artist)}" AND release:"${_escapeForMb(album)}"'));
      out.add(_CoverQueryOption(label: 'Simple', query: '$artist $album'));
      out.add(_CoverQueryOption(label: 'Álbum', query: album));
    }

    // Caso 3+ líneas: artista partido o álbum partido
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

    // Caso 1 línea: búsqueda simple
    if (candidates.length == 1) {
      out.add(_CoverQueryOption(label: 'Buscar', query: candidates[0]));
    }

    // Amplio final (3 líneas máx)
    final wide = candidates.take(3).join(' ').trim();
    if (wide.isNotEmpty) {
      out.add(_CoverQueryOption(label: 'Amplio', query: wide));
      out.add(_CoverQueryOption(label: 'Amplio (vinyl)', query: '$wide vinyl'));
    }

    // Dedup
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

  static List<_CoverQueryOption> _buildCoverSuggestions(List<String> candidates) {
    if (candidates.isEmpty) return const [];
    // 1) query exacta (si tenemos 2 líneas: artista + álbum)
    if (candidates.length >= 2) {
      final a = _escapeForMb(candidates[0]);
      final b = _escapeForMb(candidates[1]);
      final qExact = 'artist:"$a" AND release:"$b"';
      final qSimple = '${candidates[0]} ${candidates[1]}';
      final qAlbum = candidates[1];
      return [
        _CoverQueryOption(label: 'Exacto', query: qExact),
        _CoverQueryOption(label: 'Simple', query: qSimple),
        _CoverQueryOption(label: 'Álbum', query: qAlbum),
      ];
    }
    // Solo 1 línea: damos 2 variantes
    return [
      _CoverQueryOption(label: 'Buscar', query: candidates[0]),
      _CoverQueryOption(label: 'Buscar (amplio)', query: '${candidates[0]} vinyl'),
    ];
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
        // Solo filtramos líneas que sean básicamente ruido.
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

  Future<void> _searchCoverFromSuggestion(int suggestionIndex) async {
    await _runCoverSearchFromSuggestions(startIndex: suggestionIndex);
  }

  int _matchCoverSuggestionIndex(String usedQuery) {
    final uq = usedQuery.trim().toLowerCase();
    if (uq.isEmpty) return _coverSuggestionIndex;
    for (int i = 0; i < _coverSuggestions.length; i++) {
      if (_coverSuggestions[i].query.trim().toLowerCase() == uq) return i;
    }
    return _coverSuggestionIndex;
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
      _coverHits = [];
      _coverQuery = _coverSuggestions[startIndex].query;
    });

    final outcome = await _searchCoverPipeline(
      options: rotated,
      itunesTerm: term.isEmpty ? rotated.first.query : term,
    );
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

  Future<int?> _showCoverSearchOptionsSheet({
    required List<_CoverQueryOption> options,
    required int selectedIndex,
  }) async {
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
                Text(
                  'Opciones de búsqueda',
                  style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  'Elige la opción que mejor coincida con el texto de la carátula.',
                  style: t.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final opt = options[i];
                      final selected = i == selectedIndex;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(opt.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(opt.query, maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: selected ? Icon(Icons.check, color: cs.primary) : null,
                        onTap: () => Navigator.pop(ctx, i),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCoverSearchOptions() async {
    if (_coverSuggestions.isEmpty) return;
    final picked = await _showCoverSearchOptionsSheet(
      options: _coverSuggestions,
      selectedIndex: _coverSuggestionIndex,
    );
    if (!mounted) return;
    if (picked == null) return;
    await _runCoverSearchFromSuggestions(startIndex: picked);
  }

  Future<void> _editCoverQuery() async {
    final initial = ((_coverQuery ?? _coverFallbackTerm) ?? '').trim();
    if (!mounted) return;
    final ctrl = TextEditingController(text: initial);
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Editar búsqueda'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Ej: Pink Floyd Animals'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Buscar')),
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
      _coverHits = [];
      _coverQuery = q;
    });

    final outcome = await _searchCoverPipeline(
      options: [_CoverQueryOption(label: 'Buscar', query: q)],
      itunesTerm: q,
    );
    if (!mounted) return;
    setState(() {
      _coverHits = _rankHits(outcome.hits);
      _coverSearching = false;
      _coverError = outcome.error;
      _coverNote = outcome.note;
      _coverQuery = outcome.usedQuery;
    });
  }

  
  Future<void> _searchListenFromSuggestion(int suggestionIndex) async {
    if (suggestionIndex < 0 || suggestionIndex >= _listenSuggestions.length) return;
    final opt = _listenSuggestions[suggestionIndex];
    final itunesTerm = _listenResult != null ? _buildListenItunesTerm(_listenResult!) : opt.query;

    setState(() {
      _listenSuggestionIndex = suggestionIndex;
      _listenIdentifying = true;
      _listenError = null;
      _listenNote = null;
      _listenHits = [];
      _listenQuery = opt.query;
    });

    final outcome = await _searchListenPipeline(
      options: [opt],
      itunesTerm: itunesTerm.trim().isEmpty ? opt.query : itunesTerm,
      suggestionIndexBase: suggestionIndex,
    );
    if (!mounted) return;

    setState(() {
      _listenHits = _rankHits(outcome.hits);
      _listenIdentifying = false;
      _listenError = outcome.error;
      _listenNote = outcome.note;
      _listenQuery = outcome.usedQuery.trim().isEmpty ? null : outcome.usedQuery;
      if (outcome.usedSuggestionIndex != null) {
        _listenSuggestionIndex = outcome.usedSuggestionIndex!;
      }
    });
  }

  Future<void> _editListenQuery() async {
    final base = _listenResult != null ? _buildListenItunesTerm(_listenResult!) : '';
    final initial = (_listenQuery ?? base).trim();
    if (!mounted) return;
    final ctrl = TextEditingController(text: initial);

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Editar búsqueda'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Ej: Pink Floyd Animals'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Buscar')),
          ],
        );
      },
    );

    final q = (picked ?? '').trim();
    if (q.isEmpty) return;

    await _searchByListenQuery(q);
  }

  Future<_CoverSearchOutcome> _searchListenPipeline({
    required List<_ListenQueryOption> options,
    required String itunesTerm,
    int? suggestionIndexBase,
  }) async {
    final mapped = options.map((o) => _CoverQueryOption(label: o.label, query: o.query)).toList();
    return _searchCoverPipeline(
      options: mapped,
      itunesTerm: itunesTerm,
      suggestionIndexBase: suggestionIndexBase,
    );
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

  Future<_CoverSearchOutcome> _searchCoverPipeline({
    required List<_CoverQueryOption> options,
    required String itunesTerm,
    int? suggestionIndexBase,
  }) async {
    MbErrorKind lastErrKind = MbErrorKind.none;
    int? lastStatus;

    for (int i = 0; i < options.length; i++) {
      final opt = options[i];
      final res = await BarcodeLookupService.searchReleasesByTextDetailed(opt.query);
      if (res.hits.isNotEmpty) {
        return _CoverSearchOutcome(
          hits: res.hits,
          usedQuery: opt.query,
          usedSuggestionIndex: suggestionIndexBase != null ? suggestionIndexBase + i : i,
        );
      }
      if (!res.ok) {
        lastErrKind = res.errorKind;
        lastStatus = res.statusCode;
        break;
      }
    }

    // Sin resultados (o MusicBrainz falló): fallback a iTunes.
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
        usedSuggestionIndex: suggestionIndexBase,
      );
    }

    // Nada en iTunes tampoco.
    final extra = lastErrKind == MbErrorKind.none ? '' : ' ${_mbErrorToHuman(lastErrKind, lastStatus)}';
    return _CoverSearchOutcome(
      hits: const [],
      usedQuery: (term.isEmpty ? (options.isNotEmpty ? options.first.query : '') : term),
      error: 'No encontré coincidencias. Prueba otra foto o acércate al texto.$extra',
      usedSuggestionIndex: suggestionIndexBase,
    );
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

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddVinylPreviewScreen(prepared: prepared),
      ),
    );
  }

  Future<void> _openAddFlowFromArtistAlbum({required String artist, required String album, String? artistId}) async {
    final a = artist.trim();
    final al = album.trim();
    if (a.isEmpty || al.isEmpty) {
      _snack('Falta artista o álbum.');
      return;
    }

    _snack('Preparando…');
    PreparedVinylAdd prepared;
    try {
      prepared = await VinylAddService.prepare(artist: a, album: al, artistId: artistId);
    } catch (_) {
      _snack('No pude preparar la info.');
      return;
    }
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddVinylPreviewScreen(prepared: prepared),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final panelBg = cs.surface.withOpacity(0.92);

    Widget modeButton({
      required ScannerMode mode,
      required IconData icon,
      required String title,
      required String subtitle,
    }) {
      final selected = _mode == mode;
      final textColor = selected ? cs.onPrimary : cs.onSurface;
      final subColor = selected ? cs.onPrimary.withOpacity(0.85) : cs.onSurface.withOpacity(0.72);

      final label = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: textColor)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: subColor)),
        ],
      );

      final style = ButtonStyle(
        alignment: Alignment.centerLeft,
        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
        shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      );

      return selected
          ? FilledButton.icon(
              style: style,
              onPressed: null,
              icon: Icon(icon),
              label: label,
            )
          : FilledButton.tonalIcon(
              style: style,
              onPressed: () => unawaited(_setMode(mode)),
              icon: Icon(icon),
              label: label,
            );
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kAppBarToolbarHeight,
        leadingWidth: appBarLeadingWidthForLogoBack(logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        leading: appBarLeadingLogoBack(context, logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        // Más aire entre la flecha (leading) y el título.
        title: const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Text('Escáner', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        titleSpacing: 12,
        bottom: PreferredSize(
          // Más alto: los 3 botones van vertical para que siempre se lean completos.
          preferredSize: Size.fromHeight(_mode == ScannerMode.codigo ? 212 : 196),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Acciones de cámara solo en modo código.
                if (_mode == ScannerMode.codigo)
                  Row(
                    children: [
                      const Spacer(),
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
                if (_mode == ScannerMode.codigo) const SizedBox(height: 6) else const SizedBox(height: 2),
                modeButton(
                  mode: ScannerMode.codigo,
                  icon: Icons.qr_code_2,
                  title: 'Código de barras',
                  subtitle: 'Busca el álbum por UPC/EAN.',
                ),
                const SizedBox(height: 8),
                modeButton(
                  mode: ScannerMode.caratula,
                  icon: Icons.image_search,
                  title: 'Carátula',
                  subtitle: 'Lee artista y álbum desde la portada.',
                ),
                const SizedBox(height: 8),
                modeButton(
                  mode: ScannerMode.escuchar,
                  icon: Icons.hearing_outlined,
                  title: 'Escuchar',
                  subtitle: 'Reconoce una canción con el micrófono.',
                ),
              ],
            ),
          ),
        ),
      ),
      body: _mode == ScannerMode.codigo
          ? _buildBarcodeBody(panelBg: panelBg, cs: cs)
          : (_mode == ScannerMode.caratula
              ? _buildCoverBody(panelBg: panelBg, cs: cs)
              : _buildListenBody(panelBg: panelBg, cs: cs)),
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
                                    _coverNote = null;
                                    _coverOcr = null;
                                    _coverQuery = null;
                                    _coverFallbackTerm = null;
                                    _coverSuggestions = const [];
                                    _coverSuggestionIndex = 0;
                                    _coverHits = [];
                                    _coverError = null;
                                    _coverAutoPrompted = false;
                                  });
                                },
                          icon: const Icon(Icons.clear),
                          label: const Text('Limpiar'),
                        ),
                    ],
                  ),
                  // En vez de mostrar un "menú" grande debajo de la foto (que en algunos móviles queda
                  // cortado), ofrecemos las opciones en un Bottom Sheet.
                  if (_coverSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _coverSearching ? null : () => unawaited(_openCoverSearchOptions()),
                      icon: const Icon(Icons.tune),
                      label: const Text('Opciones de búsqueda'),
                    ),
                  ],
                  if ((_coverQuery ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text('Búsqueda: ${_coverQuery!}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Editar búsqueda',
                          onPressed: _coverSearching ? null : () => unawaited(_editCoverQuery()),
                          icon: const Icon(Icons.edit),
                        ),
                      ],
                    ),
                  ],
                  if ((_coverNote ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      _coverNote!,
                      style: TextStyle(color: cs.onSurface.withOpacity(0.8), fontWeight: FontWeight.w700),
                    ),
                  ],
                  if ((_coverOcr ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Texto detectado'),
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
        final coverRG250 = rgid.isEmpty ? null : 'https://coverartarchive.org/release-group/$rgid/front-250';
        final coverRG500 = rgid.isEmpty ? null : 'https://coverartarchive.org/release-group/$rgid/front-500';
        final coverRel250 = rid.isEmpty ? null : 'https://coverartarchive.org/release/$rid/front-250';
        final coverRel500 = rid.isEmpty ? null : 'https://coverartarchive.org/release/$rid/front-500';
        final primary = (h.coverUrl250 ?? coverRG250 ?? coverRel250);
        final fallback = (h.coverUrl500 ?? coverRG500 ?? coverRel500 ?? coverRel250);
        return ListTile(
          leading: _CoverThumb(primary: primary, fallback: fallback),
          title: Text('${h.artist} — ${h.album}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              if ((h.mediaFormat ?? '').trim().isNotEmpty) h.mediaFormat,
              if ((h.year ?? '').isNotEmpty) h.year,
              if ((h.country ?? '').isNotEmpty) h.country,
            ].join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => unawaited(_openAddFlow(h)),
        );
      },
    );
  }

  // ---------------------------
  // UI: MODO ESCUCHAR
  // ---------------------------

  Widget _buildListenBody({required Color panelBg, required ColorScheme cs}) {
    final t = Theme.of(context);
    final res = _listenResult;
    final hasRes = res != null && res.ok;
    final isBusy = _listening || _listenIdentifying;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
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
                    const Icon(Icons.hearing_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Escuchar y reconocer',
                        style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Toca “Escuchar” para grabar ~8 segundos y reconocer la canción.\n'
                  'Luego te muestro el álbum más probable para abrir su ficha y agregarlo a tu Lista o a Deseos.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _listenIdentifying
                          ? null
                          : (_listening
                              ? () => unawaited(_stopListening())
                              : () => unawaited(_startListening())),
                      icon: Icon(_listening ? Icons.stop : Icons.mic),
                      label: Text(_listening ? 'Detener' : 'Escuchar'),
                    ),
                    if (isBusy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    TextButton.icon(
                      onPressed: isBusy ? null : _clearListen,
                      icon: const Icon(Icons.clear),
                      label: const Text('Limpiar'),
                    ),
                  ],
                ),

                if (_listenError != null) ...[
                  const SizedBox(height: 10),
                  Text(_listenError!, style: const TextStyle(fontWeight: FontWeight.w800)),
                ],

                if (hasRes) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${res!.artist ?? ''} — ${res.title ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if ((res.album ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('Álbum: ${res.album}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ],
                    ),
                  ),
                  if ((res.album ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: isBusy ? null : () => unawaited(_continueFromListenResult()),
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('Continuar'),
                    ),
                  ],
                ],

                if (_listenSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: List.generate(_listenSuggestions.length, (i) {
                      final opt = _listenSuggestions[i];
                      return ChoiceChip(
                        label: Text(opt.label),
                        selected: _listenSuggestionIndex == i,
                        onSelected: _listenIdentifying
                            ? null
                            : (v) {
                                if (!v) return;
                                unawaited(_searchListenFromSuggestion(i));
                              },
                      );
                    }),
                  ),
                ],
                if ((_listenQuery ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Búsqueda: ${_listenQuery!}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Editar búsqueda',
                        onPressed: _listenIdentifying ? null : () => unawaited(_editListenQuery()),
                        icon: const Icon(Icons.edit),
                      ),
                    ],
                  ),
                ],
                if ((_listenNote ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    _listenNote!,
                    style: TextStyle(color: cs.onSurface.withOpacity(0.8), fontWeight: FontWeight.w700),
                  ),
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
              child: _buildListenResults(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListenResults() {
    if (_listening) {
      return const Center(child: Text('Escuchando…'));
    }
    if (_listenIdentifying) {
      return const Center(child: Text('Reconociendo y buscando…'));
    }
    if (_listenHits.isEmpty) {
      return Center(
        child: Text(
          (_listenResult == null)
              ? 'Presiona “Escuchar” para reconocer una canción.\n\nTip: pon el celular cerca del parlante y evita ruido fuerte.'
              : 'Reconocí la canción, pero no encontré el álbum.\nPrueba otra sugerencia o escucha de nuevo.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      itemCount: _listenHits.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final h = _listenHits[i];
        final rgid = (h.releaseGroupId ?? '').trim();
        final rid = (h.releaseId ?? '').trim();
        final coverRG = rgid.isEmpty ? null : 'https://coverartarchive.org/release-group/$rgid/front-250';
        final coverRel = rid.isEmpty ? null : 'https://coverartarchive.org/release/$rid/front-250';
        return ListTile(
          leading: _CoverThumb(primary: coverRG, fallback: coverRel),
          title: Text('${h.artist} — ${h.album}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              if ((h.mediaFormat ?? '').trim().isNotEmpty) h.mediaFormat,
              if ((h.year ?? '').isNotEmpty) h.year,
              if ((h.country ?? '').isNotEmpty) h.country,
            ].join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => unawaited(_openAddFlow(h)),
        );
      },
    );
  }

  void _clearListen() {
    if (_listening) {
      unawaited(_recorder.stop());
    }
    setState(() {
      _listening = false;
      _listenIdentifying = false;
      _listenError = null;
      _listenResult = null;
      _listenFile = null;
      _listenSuggestions = const [];
      _listenSuggestionIndex = 0;
      _listenQuery = null;
      _listenNote = null;
      _listenHits = [];
      _listenAutoPrompted = false;
    });
  }

  // Antes había un selector "Vinilos/Favoritos/Deseos".
  // Ahora el flujo se maneja dentro de la ficha del disco (botón "Agregar").

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
                  [
                    if ((h.mediaFormat ?? '').trim().isNotEmpty) h.mediaFormat,
                    if ((h.year ?? '').isNotEmpty) h.year,
                    if ((h.country ?? '').isNotEmpty) h.country,
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(_openAddFlow(h)),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CoverQueryOption {
  final String label;
  final String query;
  const _CoverQueryOption({required this.label, required this.query});
}

class _CoverSearchOutcome {
  final List<BarcodeReleaseHit> hits;
  final String? error;
  final String? note;
  final String usedQuery;
  final int? usedSuggestionIndex;

  const _CoverSearchOutcome({
    required this.hits,
    required this.usedQuery,
    this.error,
    this.note,
    this.usedSuggestionIndex,
  });
}

class _ListenQueryOption {
  final String label;
  final String query;
  const _ListenQueryOption({required this.label, required this.query});
}

enum _AddTarget { collection, favorites, wishlist }

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
  final bool favorite;
  const _AddPreparedSheet({required this.prepared, this.favorite = false});

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
      favorite: widget.favorite,
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
