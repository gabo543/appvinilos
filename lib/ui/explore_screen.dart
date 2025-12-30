import 'dart:async';

import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
import '../services/discography_service.dart';
import '../services/country_service.dart';
import '../services/backup_service.dart';
import '../l10n/app_strings.dart';
import 'album_tracks_screen.dart';
import 'app_logo.dart';
import 'widgets/app_cover_image.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final TextEditingController _genreCtrl = TextEditingController();
  final TextEditingController _countryCtrl = TextEditingController();
  final TextEditingController _fromCtrl = TextEditingController();
  final TextEditingController _toCtrl = TextEditingController();

  final FocusNode _genreFocus = FocusNode();
  final FocusNode _countryFocus = FocusNode();

  Timer? _debounceSuggest;

  bool _loading = false;
  String? _error;

  int _page = 0;
  static const int _pageSize = 30;
  int _total = 0;
  List<ExploreAlbumHit> _items = <ExploreAlbumHit>[];

  // Catálogos (internet + cache local)
  bool _loadingGenres = true;
  bool _loadingCountries = true;
  List<String> _allGenres = const <String>[];
  List<CountryOption> _allCountries = const <CountryOption>[];

  // Autocomplete (solo muestra el que corresponde al focus actual)
  String? _activeSuggest; // 'genre' | 'country'
  List<String> _genreSuggestions = const <String>[];
  List<CountryOption> _countrySuggestions = const <CountryOption>[];
  CountryOption? _pickedCountry;

  @override
  void initState() {
    super.initState();
    _genreFocus.addListener(() {
      if (_genreFocus.hasFocus) {
        setState(() => _activeSuggest = 'genre');
        _refreshSuggestions();
      }
    });
    _countryFocus.addListener(() {
      if (_countryFocus.hasFocus) {
        setState(() => _activeSuggest = 'country');
        _refreshSuggestions();
      }
    });

    // Cargar catálogos (géneros + países)
    Future.microtask(() async {
      await _loadCatalogs();
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<void> _loadCatalogs() async {
    // Géneros
    try {
      final list = await DiscographyService.getAllGenres();
      if (!mounted) return;
      _allGenres = list;
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingGenres = false);
    }

    // Países
    try {
      final list = await CountryService.getAllCountries();
      if (!mounted) return;
      _allCountries = list;
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingCountries = false);
    }
  }

  int _parseYear(String s) {
    final v = int.tryParse(s.trim());
    if (v == null) return 0;
    if (v < 1500 || v > 2100) return 0;
    return v;
  }

  void _refreshSuggestions() {
    _debounceSuggest?.cancel();
    _debounceSuggest = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;

      final active = _activeSuggest;
      if (active == 'genre') {
        final q = _genreCtrl.text.trim();
        if (q.isEmpty) {
          setState(() => _genreSuggestions = const <String>[]);
          return;
        }
        final nq = q.toLowerCase();
        final starts = <String>[];
        final contains = <String>[];
        for (final g in _allGenres) {
          final ng = g.toLowerCase();
          if (ng.startsWith(nq)) {
            starts.add(g);
          } else if (ng.contains(nq)) {
            contains.add(g);
          }
        }
        final out = [...starts, ...contains];
        setState(() => _genreSuggestions = out.take(14).toList());
      } else if (active == 'country') {
        final q = _countryCtrl.text.trim();
        if (q.isEmpty) {
          setState(() => _countrySuggestions = const <CountryOption>[]);
          return;
        }
        final out = CountryService.suggest(_allCountries, q, limit: 14).toList();
        setState(() => _countrySuggestions = out);
      } else {
        // nothing
      }
    });
  }

  String? _resolveCountryCode() {
    // Si el usuario seleccionó uno desde sugerencias, usamos ese.
    final picked = _pickedCountry;
    if (picked != null) return picked.code;

    final raw = _countryCtrl.text.trim();
    if (raw.isEmpty) return null;

    // Si escribe el código (2 letras), úsalo directo.
    if (raw.length == 2) return raw.toUpperCase();

    // Match exacto por nombre (ignora mayúsculas/minúsculas).
    final norm = raw.toLowerCase();
    for (final c in _allCountries) {
      if (c.name.toLowerCase() == norm) return c.code;
    }
    return null;
  }

  Future<void> _runSearch({bool resetPage = false}) async {
    final genre = _genreCtrl.text.trim();
    final y1 = _parseYear(_fromCtrl.text);
    final y2 = _parseYear(_toCtrl.text);
    final countryCode = _resolveCountryCode();

    if (genre.isEmpty) {
      setState(() {
        _error = context.tr('Escribe un género para explorar.');
        _items = <ExploreAlbumHit>[];
        _total = 0;
        _page = 0;
      });
      return;
    }

    if (resetPage) _page = 0;
    final offset = _page * _pageSize;

    setState(() {
      _loading = true;
      _error = null;
      _genreSuggestions = const <String>[];
      _countrySuggestions = const <CountryOption>[];
    });

    try {
      final page = await DiscographyService.exploreAlbumsByGenreAndYear(
        genre: genre,
        yearFrom: y1,
        yearTo: y2,
        countryCode: countryCode,
        limit: _pageSize,
        offset: offset,
      );
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _total = page.total;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.tr('No se pudo explorar en MusicBrainz. Intenta de nuevo.');
        _items = <ExploreAlbumHit>[];
        _total = 0;
      });
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _pickGenre(String g) {
    _genreCtrl.text = g;
    _genreCtrl.selection = TextSelection.fromPosition(TextPosition(offset: g.length));
    _genreSuggestions = const <String>[];
    _activeSuggest = null;
    FocusScope.of(context).unfocus();
    setState(() {});
  }

  void _pickCountry(CountryOption c) {
    _pickedCountry = c;
    _countryCtrl.text = c.name;
    _countryCtrl.selection = TextSelection.fromPosition(TextPosition(offset: c.name.length));
    _countrySuggestions = const <CountryOption>[];
    _activeSuggest = null;
    FocusScope.of(context).unfocus();
    setState(() {});
  }

  Future<void> _addToWishlist(ExploreAlbumHit it) async {
    final artista = it.artistName.trim();
    final album = it.title.trim();
    if (artista.isEmpty || album.isEmpty) return;

    try {
      await VinylDb.instance.addToWishlist(
        artista: artista,
        album: album,
        year: it.year,
        cover250: it.cover250,
        cover500: it.cover500,
        artistId: null,
        status: 'Por comprar',
        barcode: null,
      );
      await BackupService.autoSaveIfEnabled();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Agregado a deseos'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Ya está en deseos'))),
      );
    }
  }

  @override
  void dispose() {
    _debounceSuggest?.cancel();
    _genreCtrl.dispose();
    _countryCtrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _genreFocus.dispose();
    _countryFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = (_total <= 0) ? 0 : ((_total - 1) ~/ _pageSize) + 1;
    final canPrev = _page > 0;
    final canNext = totalPages == 0 ? false : (_page + 1 < totalPages);

    final cs = Theme.of(context).colorScheme;

    Widget suggestionsBox() {
      final showGenre = _activeSuggest == 'genre' && _genreSuggestions.isNotEmpty;
      final showCountry = _activeSuggest == 'country' && _countrySuggestions.isNotEmpty;
      if (!showGenre && !showCountry) return const SizedBox.shrink();

      final items = showGenre ? _genreSuggestions : _countrySuggestions;
      return Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.6)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: items.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Theme.of(context).dividerColor.withOpacity(0.4)),
            itemBuilder: (context, i) {
              if (showGenre) {
                final g = items[i] as String;
                return ListTile(
                  dense: true,
                  title: Text(g, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => _pickGenre(g),
                );
              } else {
                final c = items[i] as CountryOption;
                return ListTile(
                  dense: true,
                  title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(c.code, style: Theme.of(context).textTheme.labelMedium),
                  onTap: () => _pickCountry(c),
                );
              }
            },
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kAppBarToolbarHeight,
        leadingWidth: appBarLeadingWidthForLogoBack(logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        leading: appBarLeadingLogoBack(context, logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        title: appBarTitleTextScaled(context.tr('Explorar'), padding: const EdgeInsets.only(left: 8)),
        titleSpacing: 12,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _genreCtrl,
                      focusNode: _genreFocus,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) {
                        _pickedCountry = _pickedCountry; // no-op to keep state.
                        _activeSuggest = 'genre';
                        _refreshSuggestions();
                        setState(() {});
                      },
                      onSubmitted: (_) => _runSearch(resetPage: true),
                      decoration: InputDecoration(
                        labelText: context.tr('Género'),
                        hintText: _loadingGenres ? context.tr('Cargando…') : context.tr('Ej: Jazz, Rock, Metal'),
                        prefixIcon: const Icon(Icons.local_offer_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _countryCtrl,
                      focusNode: _countryFocus,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) {
                        // Si el usuario edita manualmente el texto, invalidamos selección previa.
                        _pickedCountry = null;
                        _activeSuggest = 'country';
                        _refreshSuggestions();
                        setState(() {});
                      },
                      decoration: InputDecoration(
                        labelText: context.tr('País'),
                        hintText: _loadingCountries ? context.tr('Cargando…') : context.tr('Ej: Chile, Finlandia'),
                        prefixIcon: const Icon(Icons.public),
                        suffixIcon: _countryCtrl.text.trim().isEmpty
                            ? null
                            : IconButton(
                                tooltip: context.tr('Limpiar'),
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setState(() {
                                    _pickedCountry = null;
                                    _countryCtrl.clear();
                                    _countrySuggestions = const <CountryOption>[];
                                  });
                                },
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              suggestionsBox(),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _fromCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.tr('Año desde'),
                        hintText: '1970',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _toCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.tr('Año hasta'),
                        hintText: '1980',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.search),
                      label: Text(context.tr('Buscar')),
                      onPressed: _loading ? null : () => _runSearch(resetPage: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close),
                      label: Text(context.tr('Limpiar')),
                      onPressed: _loading
                          ? null
                          : () {
                              setState(() {
                                _genreCtrl.clear();
                                _countryCtrl.clear();
                                _pickedCountry = null;
                                _fromCtrl.clear();
                                _toCtrl.clear();
                                _items = <ExploreAlbumHit>[];
                                _total = 0;
                                _page = 0;
                                _error = null;
                                _genreSuggestions = const <String>[];
                                _countrySuggestions = const <CountryOption>[];
                                _activeSuggest = null;
                              });
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const SizedBox(height: 8),
              if (_total > 0)
                Row(
                  children: [
                    Text(
                      '${context.tr('Resultados')}: $_total',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: context.tr('Anterior'),
                      onPressed: (!_loading && canPrev)
                          ? () {
                              setState(() => _page--);
                              _runSearch(resetPage: false);
                            }
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text(totalPages == 0 ? '—' : '${_page + 1}/$totalPages'),
                    IconButton(
                      tooltip: context.tr('Siguiente'),
                      onPressed: (!_loading && canNext)
                          ? () {
                              setState(() => _page++);
                              _runSearch(resetPage: false);
                            }
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Expanded(
                child: _items.isEmpty
                    ? Center(
                        child: Text(
                          _loading ? context.tr('Buscando en MusicBrainz…') : context.tr('Sin coincidencias'),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final it = _items[i];
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AlbumTracksScreen(
                                    album: AlbumItem(
                                      releaseGroupId: it.releaseGroupId,
                                      title: it.title,
                                      year: it.year,
                                      cover250: it.cover250,
                                      cover500: it.cover500,
                                    ),
                                    artistName: it.artistName,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.4)),
                              ),
                              child: Row(
                                children: [
                                  AppCoverImage(
                                    pathOrUrl: it.cover250,
                                    width: 54,
                                    height: 54,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                it.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context).textTheme.titleSmall,
                                              ),
                                            ),
                                            if (it.year != null)
                                              Padding(
                                                padding: const EdgeInsets.only(left: 8),
                                                child: Text(
                                                  it.year!,
                                                  style: Theme.of(context).textTheme.labelMedium,
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          it.artistName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          context.tr('Abrir ficha del disco'),
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                color: Theme.of(context).colorScheme.primary,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: context.tr('Agregar a deseos'),
                                        icon: Icon(Icons.bookmark_add_outlined, color: cs.onSurfaceVariant),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => _addToWishlist(it),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
