import 'dart:convert';
import 'package:http/http.dart' as http;

class ArtistHit {
  final String id;
  final String name;
  final String? country;
  final int? score;

  ArtistHit({
    required this.id,
    required this.name,
    this.country,
    this.score,
  });
}

class AlbumItem {
  final String releaseGroupId;
  final String title;
  final String? year;
  final String cover250;
  final String cover500;

  AlbumItem({
    required this.releaseGroupId,
    required this.title,
    required this.cover250,
    required this.cover500,
    this.year,
  });
}

class TrackItem {
  final int number;
  final String title;
  final String? length;

  TrackItem({
    required this.number,
    required this.title,
    this.length,
  });
}

class ArtistInfo {
  final String? country;
  final List<String> genres;
  final String? bio;

  ArtistInfo({
    this.country,
    required this.genres,
    this.bio,
  });
}

class DiscographyService {
  static const _mbBase = 'https://musicbrainz.org/ws/2';
  static DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<void> _throttle() async {
    final now = DateTime.now();
    final diff = now.difference(_lastCall);
    if (diff.inMilliseconds < 1100) {
      await Future.delayed(
        Duration(milliseconds: 1100 - diff.inMilliseconds),
      );
    }
    _lastCall = DateTime.now();
  }

  static Map<String, String> _headers() => {
        'User-Agent': 'GaBoLP/1.0 (contact: gabo.hachim@gmail.com)',
        'Accept': 'application/json',
      };

  static Future<http.Response> _get(Uri url) async {
    await _throttle();
    return http.get(url, headers: _headers());
  }

  // ===============================
  // 🔍 BUSCAR ARTISTAS (AUTOCOMPLETE)
  // ===============================
  static Future<List<ArtistHit>> searchArtists(String name) async {
    final q = name.trim();
    if (q.isEmpty) return [];

    final url = Uri.parse(
      '$_mbBase/artist/?query=${Uri.encodeQueryComponent(q)}&fmt=json&limit=10',
    );
    final res = await _get(url);
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body);
    final artists = (data['artists'] as List?) ?? [];

    return artists.map<ArtistHit>((a) {
      return ArtistHit(
        id: a['id'],
        name: a['name'],
        country: a['country'],
        score: a['score'],
      );
    }).toList()
      ..sort((a, b) => (b.score ?? 0).compareTo(a.score ?? 0));
  }

  // ==================================================
  // ✅ COMPATIBILIDAD (ARREGLA TU ERROR DE COMPILACIÓN)
  // ==================================================
  static Future<ArtistInfo> getArtistInfo(String artistName) async {
    final hits = await searchArtists(artistName);
    if (hits.isEmpty) {
      return ArtistInfo(country: null, genres: [], bio: null);
    }
    return getArtistInfoById(hits.first.id, artistName: hits.first.name);
  }

  // ==========================================
  // 🎸 INFO ARTISTA (PAÍS, GÉNERO, RESEÑA)
  // ==========================================
  static Future<ArtistInfo> getArtistInfoById(
    String artistId, {
    String? artistName,
  }) async {
    final url = Uri.parse(
      '$_mbBase/artist/$artistId?inc=tags&fmt=json',
    );
    final res = await _get(url);

    String? country;
    List<String> genres = [];
    String? name = artistName;

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      country = data['country'];
      name ??= data['name'];

      final tags = (data['tags'] as List?) ?? [];
      for (final t in tags) {
        final g = (t['name'] as String).trim();
        if (g.isEmpty) continue;
        if (RegExp(r'\d').hasMatch(g)) continue; // evita "1990s"
        genres.add(g);
        if (genres.length == 4) break;
      }
    }

    final bio = name == null ? null : await _fetchWikipediaBioES(name);

    return ArtistInfo(
      country: country,
      genres: genres,
      bio: bio,
    );
  }

  // =====================================
  // 📀 DISCOGRAFÍA (ORDENADA POR AÑO)
  // =====================================
  static Future<List<AlbumItem>> getDiscographyByArtistId(
    String artistId,
  ) async {
    final url = Uri.parse(
      '$_mbBase/release-group/?artist=$artistId&fmt=json&limit=100',
    );
    final res = await _get(url);
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body);
    final groups = (data['release-groups'] as List?) ?? [];

    final albums = <AlbumItem>[];

    for (final g in groups) {
      if ((g['primary-type'] ?? '').toString().toLowerCase() != 'album') {
        continue;
      }

      final id = g['id'];
      final title = g['title'];
      final date = g['first-release-date'] ?? '';
      final year = date.length >= 4 ? date.substring(0, 4) : null;

      albums.add(
        AlbumItem(
          releaseGroupId: id,
          title: title,
          year: year,
          cover250:
              'https://coverartarchive.org/release-group/$id/front-250',
          cover500:
              'https://coverartarchive.org/release-group/$id/front-500',
        ),
      );
    }

    albums.sort((a, b) {
      final ay = int.tryParse(a.year ?? '') ?? 9999;
      final by = int.tryParse(b.year ?? '') ?? 9999;
      return ay.compareTo(by);
    });

    return albums;
  }

  // =========================
  // 🎵 TRACKLIST DEL ÁLBUM
  // =========================
  static Future<List<TrackItem>> getTracksFromReleaseGroup(
    String rgid,
  ) async {
    final urlRg = Uri.parse(
      '$_mbBase/release-group/$rgid?inc=releases&fmt=json',
    );
    final resRg = await _get(urlRg);
    if (resRg.statusCode != 200) return [];

    final releases = (jsonDecode(resRg.body)['releases'] as List?) ?? [];
    if (releases.isEmpty) return [];

    final releaseId = releases.first['id'];

    final urlRel = Uri.parse(
      '$_mbBase/release/$releaseId?inc=recordings&fmt=json',
    );
    final resRel = await _get(urlRel);
    if (resRel.statusCode != 200) return [];

    final media = (jsonDecode(resRel.body)['media'] as List?) ?? [];
    if (media.isEmpty) return [];

    final tracks = <TrackItem>[];
    int n = 1;

    for (final m in media) {
      for (final t in (m['tracks'] as List? ?? [])) {
        tracks.add(
          TrackItem(
            number: n++,
            title: t['title'],
            length: _fmtMs(t['length']),
          ),
        );
      }
    }
    return tracks;
  }

  static String? _fmtMs(dynamic ms) {
    if (ms == null) return null;
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  // =====================================
  // 📝 WIKIPEDIA EN ESPAÑOL (PRIMERO)
  // =====================================
  static Future<String?> _fetchWikipediaBioES(String name) async {
    for (final lang in ['es', 'en']) {
      try {
        final search = Uri.parse(
          'https://$lang.wikipedia.org/w/api.php?action=opensearch&search=${Uri.encodeQueryComponent(name)}&limit=1&format=json',
        );
        final sRes = await http.get(search);
        if (sRes.statusCode != 200) continue;

        final data = jsonDecode(sRes.body);
        if (data[1].isEmpty) continue;

        final title = data[1][0];
        final sum = Uri.parse(
          'https://$lang.wikipedia.org/api/rest_v1/page/summary/$title',
        );
        final sumRes = await http.get(sum);
        if (sumRes.statusCode != 200) continue;

        final extract = jsonDecode(sumRes.body)['extract'];
        if (extract != null && extract.toString().isNotEmpty) {
          return extract;
        }
      } catch (_) {}
    }
    return null;
  }
}
