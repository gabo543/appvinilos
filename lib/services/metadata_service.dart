import 'dart:convert';
import 'package:http/http.dart' as http;

class AlbumSuggest {
  final String releaseGroupId;
  final String title;
  final String? year;
  final String cover250;
  final String cover500;

  AlbumSuggest({
    required this.releaseGroupId,
    required this.title,
    required this.cover250,
    required this.cover500,
    this.year,
  });
}

class CoverCandidate {
  final String releaseGroupId;
  final String? year;
  final String coverUrl250;
  final String coverUrl500;

  CoverCandidate({
    required this.releaseGroupId,
    required this.coverUrl250,
    required this.coverUrl500,
    this.year,
  });

  String get mbid => releaseGroupId;
}

class AlbumAutoMeta {
  final String? year;
  final String? genre;
  final String? releaseGroupId;
  final String? cover250;
  final String? cover500;

  AlbumAutoMeta({
    this.year,
    this.genre,
    this.releaseGroupId,
    this.cover250,
    this.cover500,
  });
}

class MetadataService {
  static const _mbBase = 'https://musicbrainz.org/ws/2';

  static DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<void> _throttle() async {
    final now = DateTime.now();
    final diff = now.difference(_lastCall);
    if (diff.inMilliseconds < 1100) {
      await Future.delayed(Duration(milliseconds: 1100 - diff.inMilliseconds));
    }
    _lastCall = DateTime.now();
  }

  static Map<String, String> _headers() => {
        'User-Agent': 'GaBoLP/1.0 (contact: gabo.hachim@gmail.com)',
        'Accept': 'application/json',
      };

  static Future<http.Response> _getJson(Uri url) async {
    await _throttle();
    return http.get(url, headers: _headers());
  }

  static bool _looksLikeYearTag(String s) {
    final t = s.toLowerCase().trim();
    if (t.isEmpty) return true;
    if (t.contains('year') || t.contains('years')) return true;
    final reDecade = RegExp(r'^\d{2,4}s$'); // 1990s
    if (reDecade.hasMatch(t)) return true;
    final reDigits = RegExp(r'\d');
    if (reDigits.hasMatch(t)) return true;
    return false;
  }

  static String? _pickGenreFromTags(List tags) {
    for (final t in tags) {
      if (t is! Map<String, dynamic>) continue;
      final name = (t['name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;
      if (_looksLikeYearTag(name)) continue;
      return name;
    }
    return null;
  }

  /// ✅ Autocompletar álbum: con 1 letra ya busca
  /// Usa wildcard: release:(q*)
  static Future<List<AlbumSuggest>> searchAlbumsForArtist(String artistName, String albumQuery) async {
    final a = artistName.trim();
    final q = albumQuery.trim();
    if (a.isEmpty || q.isEmpty) return [];

    // IMPORTANT: q* para que con 1 letra ya devuelva
    final mbQuery = 'artist:"$a" AND release:(${q}*) AND primarytype:album';

    final url = Uri.parse(
      '$_mbBase/release-group/?query=${Uri.encodeQueryComponent(mbQuery)}&fmt=json&limit=18',
    );

    final res = await _getJson(url);
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final rgs = (data['release-groups'] as List?) ?? [];

    final out = <AlbumSuggest>[];
    final seen = <String>{};

    for (final x in rgs) {
      final m = x as Map<String, dynamic>;
      final id = m['id'] as String?;
      final title = m['title'] as String?;
      if (id == null || title == null) continue;
      if (seen.contains(id)) continue;
      seen.add(id);

      final frd = (m['first-release-date'] as String?) ?? '';
      final year = frd.length >= 4 ? frd.substring(0, 4) : null;

      out.add(AlbumSuggest(
        releaseGroupId: id,
        title: title,
        year: year,
        cover250: 'https://coverartarchive.org/release-group/$id/front-250',
        cover500: 'https://coverartarchive.org/release-group/$id/front-500',
      ));

      if (out.length >= 12) break;
    }

    out.sort((a, b) {
      final ay = int.tryParse(a.year ?? '') ?? 9999;
      final by = int.tryParse(b.year ?? '') ?? 9999;
      final c = ay.compareTo(by);
      if (c != 0) return c;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return out;
  }

  static Future<List<CoverCandidate>> fetchCoverCandidates({
    required String artist,
    required String album,
  }) async {
    final a = artist.trim();
    final al = album.trim();
    if (a.isEmpty || al.isEmpty) return [];

    final q = 'release:"$al" AND artist:"$a"';
    final url = Uri.parse('$_mbBase/release/?query=${Uri.encodeQueryComponent(q)}&fmt=json&limit=25');

    final res = await _getJson(url);
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final releases = (data['releases'] as List?) ?? [];
    if (releases.isEmpty) return [];

    final out = <CoverCandidate>[];
    final seen = <String>{};

    for (final r in releases) {
      final m = r as Map<String, dynamic>;

      final date = (m['date'] as String?) ?? '';
      final year = date.length >= 4 ? date.substring(0, 4) : null;

      final rg = m['release-group'] as Map<String, dynamic>?;
      final rgid = rg?['id'] as String?;
      if (rgid == null) continue;
      if (seen.contains(rgid)) continue;
      seen.add(rgid);

      out.add(CoverCandidate(
        releaseGroupId: rgid,
        year: year,
        coverUrl250: 'https://coverartarchive.org/release-group/$rgid/front-250',
        coverUrl500: 'https://coverartarchive.org/release-group/$rgid/front-500',
      ));

      if (out.length >= 8) break;
    }

    return out;
  }

  /// ✅ Igual que fetchAutoMetadata, pero si ya tienes candidates, los usa (sin doble llamado)
  static Future<AlbumAutoMeta> fetchAutoMetadataWithCandidates({
    required String artist,
    required String album,
    List<CoverCandidate>? candidates,
  }) async {
    String? rgid;
    String? year;
    String? genre;

    final options = candidates ?? await fetchCoverCandidates(artist: artist, album: album);
    if (options.isNotEmpty) {
      rgid = options.first.releaseGroupId;
      year = options.first.year;
    }

    if (rgid != null && rgid.isNotEmpty) {
      final urlRg = Uri.parse('$_mbBase/release-group/$rgid?inc=tags&fmt=json');
      final resRg = await _getJson(urlRg);

      if (resRg.statusCode == 200) {
        final dataRg = jsonDecode(resRg.body) as Map<String, dynamic>;

        final frd = (dataRg['first-release-date'] as String?) ?? '';
        if ((year == null || year.isEmpty) && frd.length >= 4) {
          year = frd.substring(0, 4);
        }

        final tags = (dataRg['tags'] as List?) ?? [];
        genre ??= _pickGenreFromTags(tags);
      }
    }

    return AlbumAutoMeta(
      year: year,
      genre: genre,
      releaseGroupId: rgid,
      cover250: (rgid == null) ? null : 'https://coverartarchive.org/release-group/$rgid/front-250',
      cover500: (rgid == null) ? null : 'https://coverartarchive.org/release-group/$rgid/front-500',
    );
  }

  /// compat
  static Future<AlbumAutoMeta> fetchAutoMetadata({
    required String artist,
    required String album,
  }) {
    return fetchAutoMetadataWithCandidates(artist: artist, album: album);
  }
}
