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
  static const _lookup = 'https://itunes.apple.com/lookup';

  // Cache en memoria (rápido, por sesión)
  static final Map<String, TrackPreview?> _mem = <String, TrackPreview?>{};

  // Versionamos el prefijo para invalidar caches antiguas si mejoramos el algoritmo.
  // (Importante cuando antes se guardó un preview incorrecto para un título genérico.)
  static const _prefsPrefix = 'trackPreview:v2:';
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
    // Estrategia preferida cuando tenemos álbum:
    // 1) Encontrar el álbum (collection) en iTunes.
    // 2) Hacer lookup del álbum y buscar la pista dentro de ESE tracklist.
    // Esto reduce muchísimo falsos positivos en títulos genéricos típicos de soundtracks
    // ("Main Title", "Prologue", etc.)
    if (album != null && album.trim().isNotEmpty) {
      final viaAlbum = await _findItunesWithinAlbum(
        artist: artist,
        title: title,
        album: album,
      );
      if (viaAlbum != null) return viaAlbum;
    }

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

  /// Busca el preview dentro del tracklist de un álbum específico.
  ///
  /// Flujo:
  /// - search(entity=album) para obtener collectionId.
  /// - lookup(id=collectionId&entity=song) y match por trackName.
  ///
  /// Si el artista es "Various Artists" (o similar), lo tratamos como wildcard.
  static Future<TrackPreview?> _findItunesWithinAlbum({
    required String artist,
    required String title,
    required String album,
  }) async {
    final a = artist.trim();
    final t = title.trim();
    final al = album.trim();
    if (t.isEmpty || al.isEmpty) return null;

    final wantAlbum = normalizeKey(al);
    final wantArtist = normalizeKey(a);
    final artistIsWildcard = wantArtist.isEmpty ||
        wantArtist == 'various artists' ||
        wantArtist == 'varios artistas' ||
        wantArtist == 'various' ||
        wantArtist == 'soundtrack' ||
        wantArtist == 'original soundtrack';

    // 1) Encontrar el álbum (collection)
    // Si el artista es "Various Artists" (o similar), buscar solo por álbum
    // suele dar mejores resultados y evita confusiones.
    final term = artistIsWildcard ? al : [a, al].where((e) => e.trim().isNotEmpty).join(' ');
    final searchUrl = Uri.parse(
      '$_base?term=${Uri.encodeQueryComponent(term)}&media=music&entity=album&attribute=albumTerm&limit=15',
    );

    late http.Response searchRes;
    try {
      searchRes = await http.get(searchUrl).timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
    if (searchRes.statusCode != 200) return null;

    int bestScore = -1;
    Map<String, dynamic>? bestAlbum;

    // wantAlbum / wantArtist / artistIsWildcard se calcularon arriba.

    try {
      final data = jsonDecode(searchRes.body) as Map<String, dynamic>;
      final results = (data['results'] as List?) ?? [];
      for (final r in results) {
        if (r is! Map<String, dynamic>) continue;
        final collectionId = r['collectionId'];
        if (collectionId == null) continue;
        final gotAlbum = normalizeKey((r['collectionName'] ?? '').toString());
        final gotArtist = normalizeKey((r['artistName'] ?? '').toString());

        int score = 0;
        if (gotAlbum == wantAlbum) score += 14;
        if (gotAlbum.contains(wantAlbum) || wantAlbum.contains(gotAlbum)) score += 9;

        // Para soundtracks, el álbum suele ser la señal principal.
        if (!artistIsWildcard) {
          if (gotArtist == wantArtist) score += 3;
          if (gotArtist.contains(wantArtist) || wantArtist.contains(gotArtist)) score += 1;
        }

        // Bonus si parece soundtrack
        final dis = normalizeKey((r['collectionCensoredName'] ?? r['collectionName'] ?? '').toString());
        if (dis.contains('soundtrack') || dis.contains('ost') || dis.contains('score')) score += 1;

        if (score > bestScore) {
          bestScore = score;
          bestAlbum = r;
        }
      }
    } catch (_) {
      return null;
    }

    if (bestAlbum == null || bestScore < 9) {
      // No tenemos confianza suficiente de que el álbum encontrado sea el correcto.
      return null;
    }

    final collectionId = bestAlbum!['collectionId'];
    if (collectionId == null) return null;

    // 2) Lookup del tracklist del álbum
    final lookupUrl = Uri.parse(
      '$_lookup?id=$collectionId&entity=song&limit=200',
    );

    late http.Response lookupRes;
    try {
      lookupRes = await http.get(lookupUrl).timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
    if (lookupRes.statusCode != 200) return null;

    final wantTitle = normalizeKey(t);
    Map<String, dynamic>? bestTrack;
    int bestTrackScore = -1;
    try {
      final data = jsonDecode(lookupRes.body) as Map<String, dynamic>;
      final results = (data['results'] as List?) ?? [];
      for (final r in results) {
        if (r is! Map<String, dynamic>) continue;
        // El primer elemento suele ser el álbum (collection); nos interesan tracks.
        final kind = (r['wrapperType'] ?? '').toString();
        if (kind != 'track') continue;

        final previewUrl = (r['previewUrl'] as String?)?.trim() ?? '';
        if (previewUrl.isEmpty) continue;

        final gotTitle = normalizeKey((r['trackName'] ?? '').toString());
        if (gotTitle.isEmpty) continue;

        int score = 0;
        if (gotTitle == wantTitle) score += 10;
        if (gotTitle.contains(wantTitle) || wantTitle.contains(gotTitle)) score += 4;

        // Pequeño bonus si el artista de iTunes calza (si no es wildcard)
        if (!artistIsWildcard) {
          final gotArtist = normalizeKey((r['artistName'] ?? '').toString());
          if (gotArtist == wantArtist) score += 2;
          if (gotArtist.contains(wantArtist) || wantArtist.contains(gotArtist)) score += 1;
        }

        if (score > bestTrackScore) {
          bestTrackScore = score;
          bestTrack = r;
        }
      }
    } catch (_) {
      return null;
    }

    if (bestTrack == null || bestTrackScore < 8) return null;

    final previewUrl = (bestTrack!['previewUrl'] as String?)?.trim() ?? '';
    if (previewUrl.isEmpty) return null;
    final openUrl = (bestTrack!['trackViewUrl'] as String?)?.trim();

    return TrackPreview(
      previewUrl: previewUrl,
      provider: 'iTunes',
      openUrl: (openUrl ?? '').isEmpty ? null : openUrl,
    );
  }
}
