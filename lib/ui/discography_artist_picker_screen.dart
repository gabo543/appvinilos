import 'dart:async';

import 'package:flutter/material.dart';

import '../services/discography_service.dart';
import '../utils/normalize.dart';
import '../l10n/app_strings.dart';
import 'discography_screen.dart';

/// Pantalla 1 (como en el mock): selector de artista.
///
/// - Muestra el buscador + lista grande de artistas.
/// - Al tocar un artista, abre la Pantalla 2 (DiscographyScreen) con su discografía.
class DiscographyArtistPickerScreen extends StatefulWidget {
  const DiscographyArtistPickerScreen({super.key});

  @override
  State<DiscographyArtistPickerScreen> createState() => _DiscographyArtistPickerScreenState();
}

class _DiscographyArtistPickerScreenState extends State<DiscographyArtistPickerScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  bool _searching = false;
  List<ArtistHit> _results = <ArtistHit>[];

  String _normQ(String s) => normBasic(s);

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    final q = _ctrl.text.trim();
    if (q.isEmpty) {
      setState(() {
        _searching = false;
        _results = <ArtistHit>[];
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 260), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final hits = await DiscographyService.searchArtists(q);
        if (!mounted) return;
        // Ordenar por score y luego por nombre para estabilidad.
        hits.sort((a, b) {
          final as = a.score ?? 0;
          final bs = b.score ?? 0;
          final c = bs.compareTo(as);
          if (c != 0) return c;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        setState(() {
          _results = hits;
          _searching = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _results = <ArtistHit>[];
          _searching = false;
        });
      }
    });
  }

  void _openArtist(ArtistHit a) {
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DiscographyScreen(initialArtist: a)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qNorm = _normQ(_ctrl.text.trim());

    return Scaffold(
      appBar: AppBar(
        title: Text(context.trSmart('Seleccionar Artista')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: context.trSmart('Buscar artista...'),
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : (_results.isEmpty && qNorm.isNotEmpty)
                      ? Center(
                          child: Text(
                            context.trSmart('Sin resultados'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final a = _results[i];
                            final initials = (a.name.isNotEmpty)
                                ? a.name.trim().substring(0, 1).toUpperCase()
                                : '?';
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(initials),
                              ),
                              title: Text(
                                a.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: a.country == null || a.country!.trim().isEmpty
                                  ? null
                                  : Text(
                                      a.country!.trim(),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                              onTap: () => _openArtist(a),
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
