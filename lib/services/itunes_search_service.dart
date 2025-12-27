import 'dart:convert';

import 'package:http/http.dart' as http;

class ItunesAlbumHit {
  final String artist;
  final String album;
  final String? year;
  final String? country;
  final String? coverUrl250;
  final String? coverUrl500;

  const ItunesAlbumHit({
    required this.artist,
    required this.album,
    this.year,
    this.country,
    this.coverUrl250,
    this.coverUrl500,
  });
}

/// Búsqueda simple de álbumes usando iTunes Search API (sin API key).
///
/// Útil como fallback cuando MusicBrainz no encuentra coincidencias
/// o cuando el OCR no quedó lo suficientemente "limpio".
class ItunesSearchService {
  static const _base = 'https://itunes.apple.com/search';

  static String? _yearFromReleaseDate(String? releaseDate) {
    final d = (releaseDate ?? '').trim();
    if (d.length >= 4) return d.substring(0, 4);
    return null;
  }

  static String? _upgradeArtworkUrl(String? url, {required int size}) {
    final u = (url ?? '').trim();
    if (u.isEmpty) return null;
    // iTunes suele traer ".../100x100bb.jpg". Lo subimos a 250/500 si aplica.
    final re = RegExp(r'/\d+x\d+bb\.(jpg|png)$', caseSensitive: false);
    if (re.hasMatch(u)) {
      return u.replaceAll(re, '/${size}x${size}bb.jpg');
    }
    // Algunos endpoints traen "100x100" sin /...bb.jpg; intentamos reemplazo simple.
    return u.replaceAll(RegExp(r'\b\d{2,4}x\d{2,4}\b'), '${size}x${size}');
  }

  static Future<List<ItunesAlbumHit>> searchAlbums({required String term, int limit = 12}) async {
    final t = term.trim();
    if (t.isEmpty) return [];

    final url = Uri.parse(
      '$_base?term=${Uri.encodeQueryComponent(t)}&media=music&entity=album&limit=$limit',
    );

    late http.Response res;
    try {
      res = await http.get(url).timeout(const Duration(seconds: 15));
    } catch (_) {
      return [];
    }
    if (res.statusCode != 200) return [];

    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (data['results'] as List?) ?? [];
      final out = <ItunesAlbumHit>[];
      final seen = <String>{};

      for (final r in results) {
        if (r is! Map<String, dynamic>) continue;
        final artist = (r['artistName'] as String?)?.trim() ?? '';
        final album = (r['collectionName'] as String?)?.trim() ?? '';
        if (artist.isEmpty || album.isEmpty) continue;

        final key = '${artist.toLowerCase()}||${album.toLowerCase()}';
        if (seen.contains(key)) continue;
        seen.add(key);

        final year = _yearFromReleaseDate(r['releaseDate'] as String?);
        final country = (r['country'] as String?)?.trim();
        final art100 = (r['artworkUrl100'] as String?)?.trim();
        final cover250 = _upgradeArtworkUrl(art100, size: 250);
        final cover500 = _upgradeArtworkUrl(art100, size: 500);

        out.add(
          ItunesAlbumHit(
            artist: artist,
            album: album,
            year: year,
            country: (country ?? '').isEmpty ? null : country,
            coverUrl250: cover250,
            coverUrl500: cover500,
          ),
        );

        if (out.length >= 10) break;
      }

      return out;
    } catch (_) {
      return [];
    }
  }
}
