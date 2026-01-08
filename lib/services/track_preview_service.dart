import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/normalize.dart';

class TrackPreview {
  final String previewUrl;
  final String provider;
  final String? openUrl;

  const TrackPreview({
    required this.previewUrl,
    required this.provider,
    this.openUrl,
  });
}

/// Busca previews de canciones (normalmente ~30s) usando iTunes Search API.
///
/// - No requiere API key.
/// - No garantiza que todas las canciones tengan preview.
/// - Cachea resultados (incluye "no encontrado") para evitar consultas repetidas.
class TrackPreviewService {
  static const _base = 'https://itunes.apple.com/search';

  // Cache en memoria (rápido, por sesión)
  static final Map<String, TrackPreview?> _mem = <String, TrackPreview?>{};

  static const _prefsPrefix = 'trackPreview:';
  static const _cacheTtl = Duration(days: 7);

  static String _safeCacheKey(String cacheKey) {
    final k = normalizeKey(cacheKey);
    // SharedPreferences keys no deben ser demasiado largas.
    return k.length > 120 ? k.substring(0, 120) : k;
  }

  static Future<TrackPreview?> findPreview({
    required String cacheKey,
    required String artist,
    required String title,
    String? album,
  }) async {
    final a = artist.trim();
    final t = title.trim();
    final al = (album ?? '').trim();
    if (a.isEmpty || t.isEmpty) return null;

    final key = _safeCacheKey(cacheKey);
    if (_mem.containsKey(key)) return _mem[key];

    // 1) Cache persistente
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefsPrefix$key');
      if (raw != null && raw.trim().isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final ts = (data['ts'] is int) ? (data['ts'] as int) : int.tryParse('${data['ts']}') ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (ts > 0 && (now - ts) <= _cacheTtl.inMilliseconds) {
          if (data['nf'] == true) {
            _mem[key] = null;
            return null;
          }
          final url = (data['previewUrl'] ?? '').toString().trim();
          if (url.isNotEmpty) {
            final openUrl = (data['openUrl'] ?? '').toString().trim();
            final out = TrackPreview(
              previewUrl: url,
              provider: (data['provider'] ?? 'iTunes').toString(),
              openUrl: openUrl.isEmpty ? null : openUrl,
            );
            _mem[key] = out;
            return out;
          }
        }
      }
    } catch (_) {
      // silencioso
    }

    // 2) Buscar en iTunes
    final preview = await _findItunes(artist: a, title: t, album: al.isEmpty ? null : al);

    // 3) Guardar cache (incluye "no encontrado")
    _mem[key] = preview;
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = <String, dynamic>{
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
      if (preview == null) {
        data['nf'] = true;
      } else {
        data['previewUrl'] = preview.previewUrl;
        data['openUrl'] = preview.openUrl;
        data['provider'] = preview.provider;
      }
      await prefs.setString('$_prefsPrefix$key', jsonEncode(data));
    } catch (_) {
      // silencioso
    }

    return preview;
  }

  static Future<TrackPreview?> _findItunes({
    required String artist,
    required String title,
    String? album,
  }) async {
    final term = [artist, title].where((e) => e.trim().isNotEmpty).join(' ');
    if (term.trim().isEmpty) return null;

    final url = Uri.parse(
      '$_base?term=${Uri.encodeQueryComponent(term)}&media=music&entity=song&limit=10',
    );

    late http.Response res;
    try {
      res = await http.get(url).timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
    if (res.statusCode != 200) return null;

    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (data['results'] as List?) ?? [];

      final wantArtist = normalizeKey(artist);
      final wantTitle = normalizeKey(title);
      final wantAlbum = (album == null || album.trim().isEmpty) ? '' : normalizeKey(album);

      int bestScore = -1;
      Map<String, dynamic>? best;

      for (final r in results) {
        if (r is! Map<String, dynamic>) continue;
        final previewUrl = (r['previewUrl'] as String?)?.trim() ?? '';
        if (previewUrl.isEmpty) continue;

        final gotArtist = normalizeKey((r['artistName'] ?? '').toString());
        final gotTitle = normalizeKey((r['trackName'] ?? '').toString());
        final gotAlbum = normalizeKey((r['collectionName'] ?? '').toString());

        int score = 0;

        if (gotArtist == wantArtist) score += 6;
        if (gotArtist.contains(wantArtist) || wantArtist.contains(gotArtist)) score += 2;

        if (gotTitle == wantTitle) score += 8;
        if (gotTitle.contains(wantTitle) || wantTitle.contains(gotTitle)) score += 3;

        if (wantAlbum.isNotEmpty && gotAlbum == wantAlbum) score += 2;
        if (wantAlbum.isNotEmpty && (gotAlbum.contains(wantAlbum) || wantAlbum.contains(gotAlbum))) score += 1;

        // Penaliza resultados muy distintos
        if (gotTitle.isEmpty || gotArtist.isEmpty) score -= 2;

        if (score > bestScore) {
          bestScore = score;
          best = r;
        }
      }

      if (best == null) return null;

      final previewUrl = (best!['previewUrl'] as String?)?.trim() ?? '';
      if (previewUrl.isEmpty) return null;
      final openUrl = (best!['trackViewUrl'] as String?)?.trim();

      return TrackPreview(
        previewUrl: previewUrl,
        provider: 'iTunes',
        openUrl: (openUrl ?? '').isEmpty ? null : openUrl,
      );
    } catch (_) {
      return null;
    }
  }
}
