import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/discography_service.dart';
import 'discography_screen.dart';

class SimilarArtistsScreen extends StatefulWidget {
  final String? initialArtistName;
  final String? initialArtistId;

  const SimilarArtistsScreen({super.key, this.initialArtistName, this.initialArtistId});

  @override
  State<SimilarArtistsScreen> createState() => _SimilarArtistsScreenState();
}

class _SimilarArtistsScreenState extends State<SimilarArtistsScreen> {
  final TextEditingController _artistCtrl = TextEditingController();
  final FocusNode _artistFocus = FocusNode();
  Timer? _debounce;

  bool _searching = false;
  List<ArtistHit> _suggestions = <ArtistHit>[];

  ArtistHit? _selected;

  bool _loadingSimilar = false;
  String? _error;
  List<SimilarArtistHit> _similar = <SimilarArtistHit>[];

  String _normQ(String s) {
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
    out = out.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (out.startsWith('the ')) out = out.substring(4);
    return out;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapInitial();
    });
  }

  Future<void> _bootstrapInitial() async {
    final id = widget.initialArtistId?.trim();
    final name0 = (widget.initialArtistName ?? '').trim();

    if ((id ?? '').isNotEmpty) {
      // Si ya vienen ID+nombre (p. ej. desde Discografía), evitamos un resolve extra.
      final a = ArtistHit(id: id!, name: name0.isEmpty ? id! : name0);
      await _pickArtist(a);
      return;
    }

    if (name0.isEmpty) return;

    // Auto-resolver por nombre y escoger el mejor match.
    setState(() {
      _artistCtrl.text = name0;
      _artistCtrl.selection = TextSelection.collapsed(offset: name0.length);
      _searching = true;
      _suggestions = <ArtistHit>[];
    });

    try {
      final hits = await DiscographyService.searchArtists(name0);
      if (!mounted) return;

      if (hits.isEmpty) {
        setState(() => _searching = false);
        return;
      }

      final qNorm = _normQ(name0);
      ArtistHit best = hits.first;
      for (final h in hits) {
        if (_normQ(h.name) == qNorm) {
          best = h;
          break;
        }
      }
      await _pickArtist(best);
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }


  void _clearAll({bool keepFocus = true}) {
    _debounce?.cancel();
    _artistCtrl.clear();
    setState(() {
      _searching = false;
      _suggestions = <ArtistHit>[];
      _selected = null;
      _loadingSimilar = false;
      _error = null;
      _similar = <SimilarArtistHit>[];
    });
    if (keepFocus) {
      FocusScope.of(context).requestFocus(_artistFocus);
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  void _onTextChanged(String _) {
    _debounce?.cancel();

    final q = _artistCtrl.text.trim();
    final qNorm = _normQ(q);

    // Si el usuario edita después de haber seleccionado un artista, volvemos al modo "sugerencias".
    if (_selected != null && qNorm != _normQ(_selected!.name)) {
      setState(() {
        _selected = null;
        _similar = <SimilarArtistHit>[];
        _error = null;
        _loadingSimilar = false;
      });
    }

    if (q.isEmpty) {
      setState(() {
        _searching = false;
        _suggestions = <ArtistHit>[];
        _error = null;
      });
      return;
    }

    // Modo 1: sugerencias mientras escribe
    if (_selected == null) {
      _debounce = Timer(const Duration(milliseconds: 260), () async {
        if (!mounted) return;
        setState(() => _searching = true);
        try {
          final hits = await DiscographyService.searchArtists(q);
          if (!mounted) return;
          setState(() {
            _suggestions = hits;
            _searching = false;
          });
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _suggestions = <ArtistHit>[];
            _searching = false;
          });
        }
      });
    }
  }

  Future<void> _pickArtist(ArtistHit a) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _selected = a;
      _artistCtrl.text = a.name;
      _artistCtrl.selection = TextSelection.collapsed(offset: a.name.length);
      _suggestions = <ArtistHit>[];
      _searching = false;
      _loadingSimilar = true;
      _error = null;
      _similar = <SimilarArtistHit>[];
    });

    try {
      final sim = await DiscographyService.getSimilarArtistsByArtistId(a.id, limit: 25);
      if (!mounted) return;
      setState(() {
        _similar = sim;
        _loadingSimilar = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.tr('No se pudo calcular similitudes. Intenta de nuevo.');
        _similar = <SimilarArtistHit>[];
        _loadingSimilar = false;
      });
    }
  }

  void _openDiscography(ArtistHit a) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiscographyScreen(initialArtist: a),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _artistCtrl.dispose();
    _artistFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selected != null;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.hub_outlined),
            const SizedBox(width: 10),
            Text(context.tr('Similares')),
          ],
        ),
        actions: [
          IconButton(
            tooltip: context.tr('Buscar'),
            icon: const Icon(Icons.search),
            onPressed: () => FocusScope.of(context).requestFocus(_artistFocus),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _artistCtrl,
              focusNode: _artistFocus,
              textInputAction: TextInputAction.search,
              onChanged: (v) {
                setState(() {}); // refresca X
                _onTextChanged(v);
              },
              decoration: InputDecoration(
                labelText: context.tr('Artista'),
                hintText: context.tr('Ej: King Crimson'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _artistCtrl.text.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.tr('Limpiar'),
                        icon: const Icon(Icons.close),
                        onPressed: () => _clearAll(),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            if (_searching) const LinearProgressIndicator(),

            if (hasSelection) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(
                          avatar: const Icon(Icons.person_outline),
                          label: Text(_selected!.name),
                        ),
                        TextButton.icon(
                          onPressed: () => _clearAll(),
                          icon: const Icon(Icons.swap_horiz),
                          label: Text(context.tr('Cambiar')),
                        ),
                        TextButton.icon(
                          onPressed: () => _openDiscography(_selected!),
                          icon: const Icon(Icons.library_music_outlined),
                          label: Text(context.tr('Discografía')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (_loadingSimilar) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],

            const SizedBox(height: 8),

            Expanded(
              child: (!hasSelection)
                  ? (_suggestions.isEmpty
                      ? Center(
                          child: Text(
                            _artistCtrl.text.trim().isEmpty
                                ? context.tr('Escribe un artista para ver sugerencias.')
                                : context.tr('Sin coincidencias'),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _suggestions.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final a = _suggestions[i];
                            return ListTile(
                              title: Text(a.name),
                              subtitle: Text((a.country ?? '').trim().isEmpty ? '—' : (a.country ?? '').trim()),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _pickArtist(a),
                            );
                          },
                        ))
                  : (_loadingSimilar
                      ? Center(child: Text(context.tr('Buscando similares…')))
                      : (_similar.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(context.tr('Sin resultados')),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: (_selected == null)
                                            ? null
                                            : () => _pickArtist(_selected!),
                                        icon: const Icon(Icons.refresh),
                                        label: Text(context.tr('Reintentar')),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () => _clearAll(),
                                        icon: const Icon(Icons.swap_horiz),
                                        label: Text(context.tr('Cambiar')),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: _similar.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final it = _similar[i];
                                final subtitleParts = <String>[];
                                final c = (it.country ?? '').trim();
                                if (c.isNotEmpty) subtitleParts.add(c);
                                if (it.tags.isNotEmpty) subtitleParts.add(it.tags.take(2).join(' · '));
                                final subtitle = subtitleParts.isEmpty ? '—' : subtitleParts.join('  —  ');

                                return ListTile(
                                  leading: const Icon(Icons.person_outline),
                                  title: Text(it.name),
                                  subtitle: Text(subtitle),
                                  trailing: IconButton(
                                    tooltip: context.tr('Abrir discografía'),
                                    icon: const Icon(Icons.library_music_outlined),
                                    onPressed: () => _openDiscography(
                                      ArtistHit(id: it.id, name: it.name, country: it.country, score: null),
                                    ),
                                  ),
                                  onTap: () => _pickArtist(
                                    ArtistHit(id: it.id, name: it.name, country: it.country, score: null),
                                  ),
                                );
                              },
                            ))),
            ),
          ],
        ),
      ),
    );
  }
}
