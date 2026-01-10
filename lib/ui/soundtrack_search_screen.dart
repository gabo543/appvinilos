import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/discography_service.dart';
import 'album_tracks_screen.dart';
import 'app_logo.dart';
import 'widgets/app_cover_image.dart';
import 'widgets/app_state_view.dart';

/// 🎬 Buscar bandas sonoras (Soundtracks) por título.
///
/// Mantiene el flujo actual: al tocar un resultado se abre la ficha
/// (canciones/detalle) y desde ahí puedes agregar a Lista o Deseos.
class SoundtrackSearchScreen extends StatefulWidget {
  const SoundtrackSearchScreen({super.key});

  @override
  State<SoundtrackSearchScreen> createState() => _SoundtrackSearchScreenState();
}

class _SoundtrackSearchScreenState extends State<SoundtrackSearchScreen> {
  final TextEditingController _titleCtrl = TextEditingController();
  final FocusNode _titleFocus = FocusNode();

  Timer? _debounce;
  Timer? _suggestDebounce;
  int _suggestReqSeq = 0;
  bool _suggestLoading = false;
  List<ExploreAlbumHit> _suggestions = <ExploreAlbumHit>[];

  bool _loading = false;
  String? _error;

  int _page = 0;
  static const int _pageSize = 30;
  int _total = 0;
  List<ExploreAlbumHit> _items = <ExploreAlbumHit>[];

  @override
  void dispose() {
    _debounce?.cancel();
    _suggestDebounce?.cancel();
    _titleCtrl.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _onChanged(String _) {
    // Refresca sufijo (X) del input
    if (mounted) setState(() {});

    final qNow = _titleCtrl.text.trim();

    // Autocompletado (desde 2 letras)
    _suggestDebounce?.cancel();
    if (qNow.length < 2) {
      if (mounted) {
        setState(() {
          _suggestions = <ExploreAlbumHit>[];
          _suggestLoading = false;
        });
      }
    } else {
      _suggestDebounce = Timer(const Duration(milliseconds: 360), () {
        if (!mounted) return;
        _runSuggestions();
      });
    }

    // Mantiene el comportamiento actual: búsqueda automática desde 3 letras.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 520), () {
      if (!mounted) return;
      final q = _titleCtrl.text.trim();
      if (q.length < 3) return;
      _runSearch(resetPage: true);
    });
  }

  Future<void> _runSuggestions() async {
    final q = _titleCtrl.text.trim();
    if (q.length < 2) return;

    final mySeq = ++_suggestReqSeq;

    setState(() {
      _suggestLoading = true;
    });

    try {
      final list = await DiscographyService.autocompleteSoundtracks(
        title: q,
        limit: 10,
      );
      if (!mounted) return;
      if (mySeq != _suggestReqSeq) return;
      setState(() {
        _suggestions = list;
      });
    } catch (_) {
      if (!mounted) return;
      if (mySeq != _suggestReqSeq) return;
      setState(() {
        _suggestions = <ExploreAlbumHit>[];
      });
    } finally {
      if (!mounted) return;
      if (mySeq != _suggestReqSeq) return;
      setState(() {
        _suggestLoading = false;
      });
    }
  }

  Future<void> _runSearch({bool resetPage = false}) async {
    final q = _titleCtrl.text.trim();
    if (q.isEmpty) {
      setState(() {
        _error = context.tr('Escribe un título para buscar.');
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
      // Oculta sugerencias mientras se muestran resultados.
      _suggestReqSeq++;
      _suggestions = <ExploreAlbumHit>[];
      _suggestLoading = false;
    });

    try {
      final page = await DiscographyService.searchSoundtracksByTitle(
        title: q,
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
        _error = context.tr('No se pudo buscar en MusicBrainz. Intenta de nuevo.');
        _items = <ExploreAlbumHit>[];
        _total = 0;
      });
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _clear() {
    _debounce?.cancel();
    _suggestDebounce?.cancel();
    _suggestReqSeq++;
    setState(() {
      _titleCtrl.clear();
      _items = <ExploreAlbumHit>[];
      _suggestions = <ExploreAlbumHit>[];
      _suggestLoading = false;
      _total = 0;
      _page = 0;
      _error = null;
    });
    _titleFocus.requestFocus();
  }

  Widget _suggestionsView(ThemeData t) {
    final q = _titleCtrl.text.trim();
    final show = _titleFocus.hasFocus && q.length >= 2 && (_suggestLoading || _suggestions.isNotEmpty);
    if (!show) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.colorScheme.outlineVariant.withOpacity(0.6)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  Text(
                    context.tr('Sugerencias'),
                    style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const Spacer(),
                  if (_suggestLoading)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ),
            if (_suggestions.isEmpty && !_suggestLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.tr('Sin sugerencias.'),
                    style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final hit = _suggestions[i];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      leading: const Icon(Icons.local_movies_outlined),
                      title: Text(
                        hit.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        '${hit.artistName}${hit.year != null ? ' · ${hit.year}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openDetails(hit),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openDetails(ExploreAlbumHit hit) {
    _dismissKeyboard();

    final album = AlbumItem(
      releaseGroupId: hit.releaseGroupId,
      title: hit.title,
      year: hit.year,
      cover250: hit.cover250,
      cover500: hit.cover500,
      primaryType: 'album',
      secondaryTypes: const ['soundtrack'],
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumTracksScreen(
          album: album,
          artistName: hit.artistName,
          artistId: null,
        ),
      ),
    );
  }

  Widget _pager() {
    if (_total <= _pageSize) return const SizedBox.shrink();
    final pages = (_total / _pageSize).ceil();
    final canPrev = _page > 0;
    final canNext = _page < pages - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: canPrev
                ? () {
                    setState(() => _page--);
                    _runSearch();
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
            label: Text(context.tr('Anterior')),
          ),
          Text(
            '${_page + 1} / $pages',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          TextButton.icon(
            onPressed: canNext
                ? () {
                    setState(() => _page++);
                    _runSearch();
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
            label: Text(context.tr('Siguiente')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kAppBarToolbarHeight,
        leadingWidth: appBarLeadingWidthForLogoBack(logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        leading: appBarLeadingLogoBack(context, logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        title: appBarTitleTextScaled(context.trSmart('Soundtracks'), padding: const EdgeInsets.only(left: 8)),
        titleSpacing: 12,
        actions: const <Widget>[],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _titleCtrl,
                    focusNode: _titleFocus,
                    textInputAction: TextInputAction.search,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _runSearch(resetPage: true),
                    decoration: InputDecoration(
                      hintText: context.trSmart('Ej: Interstellar, Dune, The Last of Us'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _titleCtrl.text.trim().isEmpty
                          ? null
                          : IconButton(
                              tooltip: context.tr('Limpiar'),
                              icon: const Icon(Icons.close),
                              onPressed: _clear,
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: context.tr('Buscar'),
                  icon: const Icon(Icons.search),
                  onPressed: () => _runSearch(resetPage: true),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (_loading)
              const LinearProgressIndicator(minHeight: 2),
            if (!_loading)
              const SizedBox(height: 2),

            // Autocompletado: aparece desde 2 letras (solo mientras el usuario escribe).
            _suggestionsView(t),

            if (_error != null)
              Expanded(
                child: AppStateView(
                  icon: Icons.error_outline,
                  title: context.tr('Error'),
                  subtitle: _error!,
                  actionText: context.tr('Buscar'),
                  onAction: () => _runSearch(resetPage: true),
                ),
              )
            else if (!_loading && _items.isEmpty)
              Expanded(
                child: AppStateView(
                  icon: Icons.local_movies_outlined,
                  title: context.trSmart('Soundtracks'),
                  subtitle: context.trSmart('Escribe un título para buscar bandas sonoras. Ej: Interstellar, Dune, GTA.'),
                ),
              )
            else
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                      child: Row(
                        children: [
                          Text(
                            '${context.tr('Resultados')}: ${_total > 0 ? _total : _items.length}',
                            style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const Spacer(),
                          if (_total > _items.length)
                            Text(
                              context.trSmart('Mostrando') + ' ${_items.length}',
                              style: t.textTheme.labelMedium,
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final hit = _items[i];
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _openDetails(hit),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: t.colorScheme.outlineVariant.withOpacity(0.6)),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: AppCoverImage(url250: hit.cover250, url500: hit.cover500, size: 56),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            hit.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${hit.artistName}${hit.year != null ? ' · ${hit.year}' : ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    _pager(),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
