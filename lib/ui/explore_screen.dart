import 'package:flutter/material.dart';

import '../services/discography_service.dart';
import '../l10n/app_strings.dart';
import 'album_tracks_screen.dart';
import 'widgets/app_cover_image.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final TextEditingController _genreCtrl = TextEditingController();
  final TextEditingController _fromCtrl = TextEditingController();
  final TextEditingController _toCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  int _page = 0;
  static const int _pageSize = 30;
  int _total = 0;
  List<ExploreAlbumHit> _items = <ExploreAlbumHit>[];

  int _parseYear(String s) {
    final v = int.tryParse(s.trim());
    if (v == null) return 0;
    if (v < 1500 || v > 2100) return 0;
    return v;
  }

  Future<void> _runSearch({bool resetPage = false}) async {
    final genre = _genreCtrl.text.trim();
    final y1 = _parseYear(_fromCtrl.text);
    final y2 = _parseYear(_toCtrl.text);

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
    });

    try {
      final page = await DiscographyService.exploreAlbumsByGenreAndYear(
        genre: genre,
        yearFrom: y1,
        yearTo: y2,
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

  @override
  void dispose() {
    _genreCtrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = (_total <= 0) ? 0 : ((_total - 1) ~/ _pageSize) + 1;
    final canPrev = _page > 0;
    final canNext = totalPages == 0 ? false : (_page + 1 < totalPages);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Explorar')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _genreCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runSearch(resetPage: true),
                    decoration: InputDecoration(
                      labelText: context.tr('Género'),
                      hintText: context.tr('Ej: Jazz, Rock, Metal'),
                      prefixIcon: const Icon(Icons.local_offer_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
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
                  flex: 2,
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
                              _fromCtrl.clear();
                              _toCtrl.clear();
                              _items = <ExploreAlbumHit>[];
                              _total = 0;
                              _page = 0;
                              _error = null;
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
                        _loading
                            ? context.tr('Buscando en MusicBrainz…')
                            : context.tr('Sin coincidencias'),
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
    );
  }
}
