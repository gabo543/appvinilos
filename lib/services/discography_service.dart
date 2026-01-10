import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/vinyl_db.dart';
import '../utils/normalize.dart';

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

class SimilarArtistHit {
  final String id;
  final String name;
  final String? country;
  /// Score combinado (0..1 aprox). Mientras más alto, más similar.
  final double score;
  /// Tags compartidos usados para la similitud.
  final List<String> tags;

  SimilarArtistHit({
    required this.id,
    required this.name,
    this.country,
    required this.score,
    required this.tags,
  });
}

class _TagCount {
  final String name;
  final int count;

  _TagCount(this.name, this.count);
}

class _SimilarAgg {
  String name;
  String? country;
  double score;
  final Set<String> tags;

  _SimilarAgg({
    required this.name,
    required this.country,
    required this.score,
    required Set<String> tags,
  }) : tags = tags;
}

class _CacheEntry<T> {
  final T value;
  final DateTime ts;
  const _CacheEntry(this.value, this.ts);
}


class AlbumItem {
  final String releaseGroupId;
  final String title;
  final String? year;
  final String cover250;
  final String cover500;
  /// MusicBrainz primary type (Album, Single, EP, ...). Puede venir vacío.
  final String primaryType;
  /// MusicBrainz secondary types (Compilation, Live, ...). Puede venir vacío.
  final List<String> secondaryTypes;

  AlbumItem({
    required this.releaseGroupId,
    required this.title,
    required this.cover250,
    required this.cover500,
    this.year,
    this.primaryType = '',
    this.secondaryTypes = const <String>[],
  });
}

class _RgCandidate {
  final String id;
  String title;
  String? year;
  DateTime? earliest;
  bool hasOfficial;

  _RgCandidate({
    required this.id,
    required this.title,
    this.year,
    this.earliest,
    this.hasOfficial = false,
  });

  AlbumItem toAlbumItem() {
    return AlbumItem(
      releaseGroupId: id,
      title: title.isEmpty ? '(sin título)' : title,
      year: year,
      cover250: 'https://coverartarchive.org/release-group/$id/front-250',
      cover500: 'https://coverartarchive.org/release-group/$id/front-500',
    );
  }
}

/// Página de discografía (MusicBrainz release-groups).
///
/// Se usa para cargar rápido: primero una página, y luego vamos trayendo
/// más páginas solo cuando se necesitan.
class DiscographyPage {
  final List<AlbumItem> items;
  final int total;
  final int offset;
  final int limit;

  DiscographyPage({
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
  });

  bool get hasMore => (offset + limit) < total;
}

class ExploreAlbumHit {
  final String releaseGroupId;
  final String title;
  final String artistName;
  final String? year;
  final String cover250;
  final String cover500;

  ExploreAlbumHit({
    required this.releaseGroupId,
    required this.title,
    required this.artistName,
    required this.cover250,
    required this.cover500,
    this.year,
  });
}

class ExploreAlbumPage {
  final List<ExploreAlbumHit> items;
  final int total;
  final int offset;
  final int limit;

  ExploreAlbumPage({
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
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

/// Edición (release) dentro de un release-group.
///
/// Se usa para que el usuario pueda elegir "qué edición" usar como referencia
/// para carátula/metadata, sin alterar el año guardado del álbum (que viene del
/// first-release-date del release-group).
class ReleaseEdition {
  final String id;
  final String title;
  final String? date; // YYYY-MM-DD (o vacío)
  final String? country;
  final String? status;
  final String? barcode;

  ReleaseEdition({
    required this.id,
    required this.title,
    this.date,
    this.country,
    this.status,
    this.barcode,
  });

  String? get year => (date != null && date!.length >= 4) ? date!.substring(0, 4) : null;
}

class SongHit {
  final String id;
  final String title;
  final int? score;

  SongHit({
    required this.id,
    required this.title,
    this.score,
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

  // Debug interno del filtro de canciones (no UI). Útil para entender por qué
  // un tema cae en compilaciones/en vivo. Mantener en false en producción.
  static const bool _debugSongFilter = false;
  static void _dbgSongFilter(String msg) {
    if (!_debugSongFilter) return;
    // ignore: avoid_print
    print('[SongFilter] $msg');
  }

  // Cache in-memory para que "Similares" sea más estable y rápido.
  static const Duration _similarTtl = Duration(hours: 12);
  static final Map<String, _CacheEntry<List<SimilarArtistHit>>> _similarCache = {};
  static final Map<String, _CacheEntry<List<_TagCount>>> _artistTagsCache = {};

  // Cache de tracklists (primera edición) por release-group.
  // Es caro consultar releases/recordings; esto mantiene el autocompletado
  // de canciones rápido y consistente.
  static const Duration _tracksTtl = Duration(hours: 24);
  static final Map<String, _CacheEntry<List<String>>> _firstEditionTracksCache = {};
  // Cache simple para validar si un release-group pertenece al artista.
  // (evita mostrar "various artists" cuando estás en Discografía del artista)
  static final Map<String, _CacheEntry<bool>> _rgHasArtistCache = {};
  // Cache de detalles de release-group (title/tipo/fecha/secundarios).
  // Evita repetir lookups al filtrar canciones y mejora consistencia cuando MB devuelve
  // release-group como solo id (string).
  static const Duration _rgDetailsTtl = Duration(days: 30);
  static final Map<String, _CacheEntry<Map<String, dynamic>>> _rgDetailsCache = {};
  static const _luceneSpecial = '+-!(){}[]^"~*?:\\/&|';

  static String _escLucene(String s) {
    final sb = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      if (_luceneSpecial.contains(ch)) sb.write('\\');
      sb.write(ch);
    }
    return sb.toString();
  }


  static Map<String, dynamic>? _rgDetailsCachedMem(String id) {
    final key = id.trim();
    if (key.isEmpty) return null;
    final c = _rgDetailsCache[key];
    if (c == null) return null;
    if (DateTime.now().difference(c.ts) <= _rgDetailsTtl) return c.value;
    _rgDetailsCache.remove(key);
    return null;
  }

  static Future<Map<String, dynamic>?> _rgDetailsCached(String id) async {
    final key = id.trim();
    if (key.isEmpty) return null;

    // 1) memoria
    final m = _rgDetailsCachedMem(key);
    if (m != null) return m;

    // 2) SQLite (persistente)
    try {
      final j = await VinylDb.instance.mbCacheGetJson('mb:rg:$key');
      if (j != null) {
        _rgDetailsCache[key] = _CacheEntry(j, DateTime.now());
        return j;
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  static Future<void> _rgDetailsStore(String id, Map<String, dynamic> j) async {
    final key = id.trim();
    if (key.isEmpty) return;
    _rgDetailsCache[key] = _CacheEntry(j, DateTime.now());
    try {
      await VinylDb.instance.mbCachePutJson('mb:rg:$key', j);
    } catch (_) {
      // ignore
    }
  }

  static Future<Map<String, dynamic>?> _rgDetailsFetch(String id) async {
    final key = id.trim();
    if (key.isEmpty) return null;

    try {
      final u = Uri.parse('$_mbBase/release-group/$key?fmt=json');
      final r = await _get(u);
      if (r.statusCode != 200) return null;
      final decoded = jsonDecode(r.body);
      if (decoded is! Map) return null;
      final j = decoded.cast<String, dynamic>();
      await _rgDetailsStore(key, j);
      return j;
    } catch (_) {
      return null;
    }
  }


  // Cache de tracks (título normalizado + length ms) por release-group.
  // Se usa para desambiguar versiones (live/remaster) y confirmar que el tema
  // realmente aparece en el álbum de estudio.
  static const Duration _rgTracksInfoTtl = Duration(days: 30);
  static final Map<String, _CacheEntry<Map<String, dynamic>>> _rgTracksInfoCache = {};

  // Tracklist cache preferiendo un release con formato CD (cuando exista).
  static final Map<String, _CacheEntry<Map<String, dynamic>>> _rgTracksInfoCacheCd = {};

  static Map<String, dynamic>? _rgTracksInfoCachedMem(String id) {
    final key = id.trim();
    if (key.isEmpty) return null;
    final c = _rgTracksInfoCache[key];
    if (c == null) return null;
    if (DateTime.now().difference(c.ts) <= _rgTracksInfoTtl) return c.value;
    _rgTracksInfoCache.remove(key);
    return null;
  }

  static Future<Map<String, dynamic>?> _rgTracksInfoCached(String id) async {
    final key = id.trim();
    if (key.isEmpty) return null;

    final m = _rgTracksInfoCachedMem(key);
    if (m != null) return m;

    try {
      final j = await VinylDb.instance.mbCacheGetJson('mb:rg_tracks:$key');
      if (j != null) {
        _rgTracksInfoCache[key] = _CacheEntry(j, DateTime.now());
        return j;
      }
    } catch (_) {
      // ignore
    }

    return null;
  }

  static Future<void> _rgTracksInfoStore(String id, Map<String, dynamic> j) async {
    final key = id.trim();
    if (key.isEmpty) return;
    _rgTracksInfoCache[key] = _CacheEntry(j, DateTime.now());
    try {
      await VinylDb.instance.mbCachePutJson('mb:rg_tracks:$key', j);
    } catch (_) {
      // ignore
    }
  }

  // --- versión CD preferida ---
  static Map<String, dynamic>? _rgTracksInfoCachedMemCd(String id) {
    final key = id.trim();
    if (key.isEmpty) return null;
    final c = _rgTracksInfoCacheCd[key];
    if (c == null) return null;
    if (DateTime.now().difference(c.ts) <= _rgTracksInfoTtl) return c.value;
    _rgTracksInfoCacheCd.remove(key);
    return null;
  }

  static Future<Map<String, dynamic>?> _rgTracksInfoCachedCd(String id) async {
    final key = id.trim();
    if (key.isEmpty) return null;

    final m = _rgTracksInfoCachedMemCd(key);
    if (m != null) return m;

    try {
      final j = await VinylDb.instance.mbCacheGetJson('mb:rg_tracks_cd:$key');
      if (j != null) {
        _rgTracksInfoCacheCd[key] = _CacheEntry(j, DateTime.now());
        return j;
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  static Future<void> _rgTracksInfoStoreCd(String id, Map<String, dynamic> j) async {
    final key = id.trim();
    if (key.isEmpty) return;
    _rgTracksInfoCacheCd[key] = _CacheEntry(j, DateTime.now());
    try {
      await VinylDb.instance.mbCachePutJson('mb:rg_tracks_cd:$key', j);
    } catch (_) {
      // ignore
    }
  }

  static bool _releaseHasCdFormat(Map r) {
    final media = (r['media'] as List?) ?? const <dynamic>[];
    for (final m in media) {
      if (m is! Map) continue;
      final fmt = (m['format'] ?? '').toString().trim().toLowerCase();
      if (fmt == 'cd') return true;
    }
    return false;
  }

  /// Elige una edición preferentemente en CD desde un listado de releases
  /// (resultado de /release?release-group=...&inc=media).
  ///
  /// Preferimos: CD + Official + fecha más antigua.
  /// Si no hay CD, caemos a Official + fecha más antigua (como _pickBestReleaseIdFromReleases).
  static String _pickBestReleaseIdFromReleaseSearchPreferCd(List releases) {
    String? bestCd;
    DateTime? bestCdDt;
    bool bestCdOfficial = false;

    String? bestAny;
    DateTime? bestAnyDt;
    bool bestAnyOfficial = false;

    String? firstAny;
    String? firstOfficial;

    for (final r in releases) {
      if (r is! Map) continue;
      final id = (r['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      firstAny ??= id;

      final status = (r['status'] ?? '').toString().trim().toLowerCase();
      final isOfficial = status.isEmpty || status == 'official';
      if (isOfficial) firstOfficial ??= id;

      final dt = _parseMbDate(r['date']);

      // Mejor cualquiera (fallback)
      if (dt != null) {
        if (bestAny == null) {
          bestAny = id;
          bestAnyDt = dt;
          bestAnyOfficial = isOfficial;
        } else {
          if (isOfficial && !bestAnyOfficial) {
            bestAny = id;
            bestAnyDt = dt;
            bestAnyOfficial = true;
          } else if (!( !isOfficial && bestAnyOfficial)) {
            if (bestAnyDt == null || dt.isBefore(bestAnyDt!)) {
              bestAny = id;
              bestAnyDt = dt;
              bestAnyOfficial = isOfficial;
            }
          }
        }
      } else if (bestAny == null) {
        // Si no hay fechas, igual dejamos algo.
        bestAny = id;
        bestAnyOfficial = isOfficial;
      }

      // Mejor CD
      final hasCd = _releaseHasCdFormat(r);
      if (!hasCd) continue;
      if (dt == null) {
        // sin fecha: usar como fallback si no tenemos CD aún.
        bestCd ??= id;
        bestCdOfficial = isOfficial;
        continue;
      }

      if (bestCd == null) {
        bestCd = id;
        bestCdDt = dt;
        bestCdOfficial = isOfficial;
      } else {
        if (isOfficial && !bestCdOfficial) {
          bestCd = id;
          bestCdDt = dt;
          bestCdOfficial = true;
        } else if (!( !isOfficial && bestCdOfficial)) {
          if (bestCdDt == null || dt.isBefore(bestCdDt!)) {
            bestCd = id;
            bestCdDt = dt;
            bestCdOfficial = isOfficial;
          }
        }
      }
    }

    return bestCd ?? bestAny ?? firstOfficial ?? firstAny ?? '';
  }

  /// Elige una edición (release) "buena" desde la lista de releases del release-group.
  /// Preferimos Official + fecha más antigua (para no abrir reediciones raras primero).
  static String _pickBestReleaseIdFromReleases(List releases) {
    String? firstAny;
    String? firstOfficial;
    String? bestId;
    DateTime? bestDt;
    bool bestIsOfficial = false;

    for (final r in releases) {
      if (r is! Map) continue;
      final id = (r['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      firstAny ??= id;

      final status = (r['status'] ?? '').toString().trim().toLowerCase();
      final isOfficial = status.isEmpty || status == 'official';
      if (isOfficial) firstOfficial ??= id;

      final dt = _parseMbDate(r['date']);
      if (dt == null) continue;

      if (bestId == null) {
        bestId = id;
        bestDt = dt;
        bestIsOfficial = isOfficial;
        continue;
      }

      // Preferir releases oficiales; si ambos son oficiales/no-oficiales, elegir el más antiguo.
      if (isOfficial && !bestIsOfficial) {
        bestId = id;
        bestDt = dt;
        bestIsOfficial = true;
        continue;
      }
      if (!isOfficial && bestIsOfficial) {
        continue;
      }

      if (bestDt == null || dt.isBefore(bestDt)) {
        bestId = id;
        bestDt = dt;
        bestIsOfficial = isOfficial;
      }
    }

    return bestId ?? firstOfficial ?? firstAny ?? '';
  }

  /// Obtiene (y cachea) el tracklist (título normalizado + length ms) de la "mejor" edición
  /// dentro del release-group. Se usa solo para desambiguación (no para UI directa).
  static Future<Map<String, dynamic>?> _rgTracksInfoFetch(String rgid) async {
    final id = rgid.trim();
    if (id.isEmpty) return null;

    final urlRg = Uri.parse('$_mbBase/release-group/$id?inc=releases&fmt=json');
    final resRg = await _get(urlRg);
    if (resRg.statusCode != 200) return null;

    dynamic decoded;
    try {
      decoded = jsonDecode(resRg.body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final releases = (decoded['releases'] as List?) ?? const <dynamic>[];
    if (releases.isEmpty) return null;

    // En vez de elegir 1 sola edición (que a veces viene sin tracklist),
    // probamos varias candidatas hasta encontrar una con tracks.
    final candidates = <Map<String, dynamic>>[];
    int i = 0;
    for (final r in releases) {
      if (r is! Map) {
        i++;
        continue;
      }
      final rid = (r['id'] ?? '').toString().trim();
      if (rid.isEmpty) {
        i++;
        continue;
      }
      final status = (r['status'] ?? '').toString().trim().toLowerCase();
      final isOfficial = status.isEmpty || status == 'official';
      final dt = _parseMbDate(r['date']);
      candidates.add({
        'id': rid,
        'off': isOfficial,
        'dt': dt,
        'i': i,
      });
      i++;
    }

    candidates.sort((a, b) {
      final ao = (a['off'] == true);
      final bo = (b['off'] == true);
      if (ao != bo) return ao ? -1 : 1; // oficiales primero
      final ad = a['dt'] as DateTime?;
      final bd = b['dt'] as DateTime?;
      if (ad == null && bd != null) return 1;
      if (ad != null && bd == null) return -1;
      if (ad != null && bd != null) {
        final c = ad.compareTo(bd); // más antiguo primero
        if (c != 0) return c;
      }
      return (a['i'] as int).compareTo(b['i'] as int);
    });

    final maxTry = math.min(6, candidates.length);
    for (int k = 0; k < maxTry; k++) {
      final releaseId = (candidates[k]['id'] ?? '').toString().trim();
      if (releaseId.isEmpty) continue;

      final urlRel = Uri.parse('$_mbBase/release/$releaseId?inc=recordings&fmt=json');
      final resRel = await _get(urlRel);
      if (resRel.statusCode != 200) continue;

      dynamic relDecoded;
      try {
        relDecoded = jsonDecode(resRel.body);
      } catch (_) {
        continue;
      }
      if (relDecoded is! Map) continue;

      final media = (relDecoded['media'] as List?) ?? const <dynamic>[];
      if (media.isEmpty) continue;

      final tracks = <Map<String, dynamic>>[];
      for (final m in media) {
        if (m is! Map) continue;
        final tlist = (m['tracks'] as List?) ?? const <dynamic>[];
        for (final t in tlist) {
          if (t is! Map) continue;
          final title = (t['title'] ?? '').toString().trim();
          if (title.isEmpty) continue;
          final n = normalizeKey(title);
          final l = (t['length'] is num) ? (t['length'] as num).toInt() : null;
          tracks.add({'t': title, 'n': n, 'l': l});
        }
      }

      if (tracks.isEmpty) continue;

      return {
        'releaseId': releaseId,
        'tracks': tracks,
      };
    }

    return null;
  }


  /// Igual que _rgTracksInfoFetch, pero intenta elegir una edición en formato CD.
  ///
  /// 1) Lista releases del release-group usando /release?release-group=...&inc=media
  /// 2) Elige CD + Official + más antigua
  /// 3) Si no hay CD, cae a Official + más antigua
  /// 4) Descarga tracklist con /release/<id>?inc=recordings
  static Future<Map<String, dynamic>?> _rgTracksInfoFetchPreferCd(String rgid) async {
    final id = rgid.trim();
    if (id.isEmpty) return null;

    final urlList = Uri.parse(
      '$_mbBase/release/?release-group=$id&inc=media&fmt=json&limit=100',
    );
    final resList = await _get(urlList);
    if (resList.statusCode != 200) return null;

    dynamic decoded;
    try {
      decoded = jsonDecode(resList.body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final releases = (decoded['releases'] as List?) ?? const <dynamic>[];
    if (releases.isEmpty) return null;

    // En vez de elegir 1 sola edición CD (que a veces no trae tracklist),
    // probamos varias: CD primero, luego Official + más antigua.
    final candidates = <Map<String, dynamic>>[];
    int i = 0;
    for (final r in releases) {
      if (r is! Map) {
        i++;
        continue;
      }
      final rid = (r['id'] ?? '').toString().trim();
      if (rid.isEmpty) {
        i++;
        continue;
      }

      final status = (r['status'] ?? '').toString().trim().toLowerCase();
      final isOfficial = status.isEmpty || status == 'official';
      final dt = _parseMbDate(r['date']);

      bool hasCd = false;
      final media = (r['media'] as List?) ?? const <dynamic>[];
      for (final m in media) {
        if (m is! Map) continue;
        final fmt = (m['format'] ?? '').toString().trim().toLowerCase();
        if (fmt.contains('cd')) {
          hasCd = true;
          break;
        }
      }

      candidates.add({
        'id': rid,
        'cd': hasCd,
        'off': isOfficial,
        'dt': dt,
        'i': i,
      });
      i++;
    }

    candidates.sort((a, b) {
      final acd = (a['cd'] == true);
      final bcd = (b['cd'] == true);
      if (acd != bcd) return acd ? -1 : 1; // CD primero
      final ao = (a['off'] == true);
      final bo = (b['off'] == true);
      if (ao != bo) return ao ? -1 : 1; // Official primero
      final ad = a['dt'] as DateTime?;
      final bd = b['dt'] as DateTime?;
      if (ad == null && bd != null) return 1;
      if (ad != null && bd == null) return -1;
      if (ad != null && bd != null) {
        final c = ad.compareTo(bd); // más antiguo primero
        if (c != 0) return c;
      }
      return (a['i'] as int).compareTo(b['i'] as int);
    });

    final maxTry = math.min(8, candidates.length);
    for (int k = 0; k < maxTry; k++) {
      final releaseId = (candidates[k]['id'] ?? '').toString().trim();
      if (releaseId.isEmpty) continue;

      final urlRel = Uri.parse('$_mbBase/release/$releaseId?inc=recordings&fmt=json');
      final resRel = await _get(urlRel);
      if (resRel.statusCode != 200) continue;

      dynamic relDecoded;
      try {
        relDecoded = jsonDecode(resRel.body);
      } catch (_) {
        continue;
      }
      if (relDecoded is! Map) continue;

      final media = (relDecoded['media'] as List?) ?? const <dynamic>[];
      if (media.isEmpty) continue;

      final tracks = <Map<String, dynamic>>[];
      for (final m in media) {
        if (m is! Map) continue;
        final tlist = (m['tracks'] as List?) ?? const <dynamic>[];
        for (final t in tlist) {
          if (t is! Map) continue;
          final title = (t['title'] ?? '').toString().trim();
          if (title.isEmpty) continue;
          final n = normalizeKey(title);
          final l = (t['length'] is num) ? (t['length'] as num).toInt() : null;
          tracks.add({'t': title, 'n': n, 'l': l});
        }
      }

      if (tracks.isEmpty) continue;

      return {
        'releaseId': releaseId,
        'tracks': tracks,
      };
    }

    return null;
  }


  static bool _trackTitleMatches(String trackNorm, String wantNorm, List<String> wantTokens) {
    final tn = trackNorm.trim();
    final wn = wantNorm.trim();
    if (tn.isEmpty || wn.isEmpty) return false;
    if (tn == wn) return true;

    // Tokens fuertes: todas deben aparecer.
    final strong = wantTokens.where((t) => t.length >= 2).toList();
    if (strong.isNotEmpty && strong.every((t) => tn.contains(t))) return true;

    // Match más permisivo para casos como "suedehead" vs "suedehead (2011 remaster)".
    if (tn.startsWith(wn)) return true;
    return false;
  }

  static int? _bestTrackLenMsForSong(Map<String, dynamic> rgTracksInfo, String wantNorm, List<String> wantTokens) {
    final tracks = (rgTracksInfo['tracks'] as List?) ?? const <dynamic>[];
    if (tracks.isEmpty) return null;
    for (final t in tracks) {
      if (t is! Map) continue;
      final tn = (t['n'] ?? '').toString();
      if (!_trackTitleMatches(tn, wantNorm, wantTokens)) continue;
      final l = t['l'];
      if (l is int && l > 0) return l;
      // Encontramos el track, pero sin duración.
      return -1;
    }
    return null;
  }

  static String _sanitizeSongQuery(String s) {
    var q = s.trim();
    if (q.isEmpty) return q;

    // Limpia sufijos/complementos típicos del autocomplete: (live), (remaster), etc.
    final kw = RegExp(
      r'(live|en vivo|remaster|remastered|version|edit|demo|mix|remix|acoustic|instrumental)',
      caseSensitive: false,
    );

    // Elimina paréntesis/corchetes SOLO si contienen keywords (para no destruir títulos reales).
    q = q.replaceAllMapped(RegExp(r'[\(\[\{]([^\)\]\}]+)[\)\]\}]'), (m) {
      final inside = (m[1] ?? '').toString();
      return kw.hasMatch(inside) ? ' ' : (m[0] ?? '');
    });

    // Elimina sufijos tipo " - live" o " - remastered".
    q = q.replaceAll(
      RegExp(r'\s+-\s+(live|en vivo|remaster(?:ed)?|demo|edit|mix|remix)\s*.*$', caseSensitive: false),
      '',
    );

    q = q.replaceAll(RegExp(r'\s+'), ' ').trim();
    return q;
  }

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

  // ==================================================
  // 🎵 TRACKLIST (preferir CD) + búsqueda por discografía
  // ==================================================
  // Enfoque robusto para "¿en qué álbum está esta canción?":
  // 1) Traer la discografía (release-groups) del artista, filtrando a Albums.
  // 2) Para cada álbum, elegir una edición en formato CD (si existe).
  // 3) Revisar el tracklist de esa edición y marcar coincidencias.
  //
  // Esto evita depender de que MusicBrainz entregue el "recording" correcto
  // (estudio vs live/remaster) en las búsquedas.


  static bool _isRetryableStatus(int code) {
    // MusicBrainz / Wikipedia / etc pueden devolver errores temporales.
    return code == 408 || code == 429 || (code >= 500 && code <= 599);
  }

  static Future<http.Response> _get(Uri url, {int retries = 2}) async {
    http.Response? last;
    for (var attempt = 0; attempt <= retries; attempt++) {
      await _throttle();
      try {
        final res = await http
            .get(url, headers: _headers())
            .timeout(const Duration(seconds: 15));
        last = res;
        if (res.statusCode == 200) return res;
        if (!_isRetryableStatus(res.statusCode)) return res;
      } catch (_) {
        // continua a reintentar
      }

      if (attempt < retries) {
        // backoff suave (sin explotar tiempos), además del throttle.
        await Future.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
    }
    // Si todo falló y no tenemos respuesta, devolvemos una respuesta vacía.
    return last ?? http.Response('', 599);
  }

  static Map<String, String> _headersPlain() => {
        'User-Agent': 'GaBoLP/1.0 (contact: gabo.hachim@gmail.com)',
        'Accept': 'text/plain',
      };

  static Future<http.Response> _getPlain(Uri url, {int retries = 1}) async {
    http.Response? last;
    for (var attempt = 0; attempt <= retries; attempt++) {
      await _throttle();
      try {
        final res = await http
            .get(url, headers: _headersPlain())
            .timeout(const Duration(seconds: 20));
        last = res;
        if (res.statusCode == 200) return res;
        if (!_isRetryableStatus(res.statusCode)) return res;
      } catch (_) {}

      if (attempt < retries) {
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    return last ?? http.Response('', 599);
  }

  // ==================================================
  // 🏷️ GÉNEROS (MusicBrainz /genre/all)
  // ==================================================
  static const String _prefsGenresKey = 'mb_genres_all_v1';
  static const String _prefsGenresTsKey = 'mb_genres_all_ts_v1';
  static const Duration _genresTtl = Duration(days: 14);

  static List<String>? _genresMem;
  static int _genresMemTs = 0;

  static Future<List<String>> getAllGenres({bool forceRefresh = false}) async {
    if (!forceRefresh && _genresMem != null && _genresMem!.isNotEmpty) {
      final dt = DateTime.fromMillisecondsSinceEpoch(_genresMemTs);
      if (DateTime.now().difference(dt) <= _genresTtl) {
        return _genresMem!;
      }
    }

    if (!forceRefresh) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final ts = prefs.getInt(_prefsGenresTsKey) ?? 0;
        final raw = prefs.getString(_prefsGenresKey);
        if (ts > 0 && raw != null && raw.trim().isNotEmpty) {
          final dt = DateTime.fromMillisecondsSinceEpoch(ts);
          if (DateTime.now().difference(dt) <= _genresTtl) {
            final list = raw
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            if (list.isNotEmpty) {
              _genresMem = list;
              _genresMemTs = ts;
              return list;
            }
          }
        }
      } catch (_) {
        // ignore
      }
    }

    final url = Uri.parse('$_mbBase/genre/all?fmt=txt');
    final res = await _getPlain(url);
    if (res.statusCode != 200) {
      if (_genresMem != null) return _genresMem!;
      return const <String>[];
    }

    final list = res.body
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsGenresKey, list.join('\n'));
      await prefs.setInt(_prefsGenresTsKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // ignore
    }

    _genresMem = list;
    _genresMemTs = DateTime.now().millisecondsSinceEpoch;
    return list;
  }


  // ==================================================
  // 🧭 EXPLORAR ÁLBUMES (GÉNERO + RANGO DE AÑOS)
  // ==================================================
  /// Devuelve una página de álbumes (release-groups) filtrados por:
  /// - tag (género)
  /// - firstreleasedate (rango de años)
  ///
  /// Nota: MusicBrainz usa tags comunitarios; los resultados dependen de cómo
  /// estén etiquetados los release-groups.
  static Future<ExploreAlbumPage> exploreAlbumsByGenreAndYear({
    required String genre,
    required int yearFrom,
    required int yearTo,
    String? countryCode,
    int limit = 30,
    int offset = 0,
  }) async {
    final g = genre.trim();
    if (g.isEmpty) {
      return ExploreAlbumPage(items: const <ExploreAlbumHit>[], total: 0, offset: offset, limit: limit);
    }

    var y1 = yearFrom;
    var y2 = yearTo;
    if (y1 <= 0 && y2 <= 0) {
      // Si el usuario no pone año, dejamos abierto (pero normalmente lo usará).
      y1 = 0;
      y2 = 0;
    } else {
      if (y1 <= 0) y1 = y2;
      if (y2 <= 0) y2 = y1;
      if (y2 < y1) {
        final tmp = y1;
        y1 = y2;
        y2 = tmp;
      }
    }

    final genreTerm = g.contains(' ') ? 'tag:"${_escLucene(g)}"' : 'tag:${_escLucene(g)}';
    final typeTerm = 'primarytype:album';
    final dateTerm = (y1 > 0 && y2 > 0)
        ? 'firstreleasedate:[${y1.toString().padLeft(4, '0')}-01-01 TO ${y2.toString().padLeft(4, '0')}-12-31]'
        : '';
    final cc = (countryCode ?? '').trim().toUpperCase();
    final countryTerm = (cc.length == 2) ? 'country:$cc' : '';


    final lucene = [genreTerm, typeTerm, if (dateTerm.isNotEmpty) dateTerm, if (countryTerm.isNotEmpty) countryTerm].join(' AND ');
    final url = Uri.parse(
      '$_mbBase/release-group/?query=${Uri.encodeQueryComponent(lucene)}&fmt=json&limit=$limit&offset=$offset',
    );
    final res = await _get(url);
    if (res.statusCode != 200) {
      return ExploreAlbumPage(items: const <ExploreAlbumHit>[], total: 0, offset: offset, limit: limit);
    }

    final data = jsonDecode(res.body);
    final total = (data['count'] as int?) ?? 0;
    final groups = (data['release-groups'] as List?) ?? [];

    final out = <ExploreAlbumHit>[];
    for (final g in groups) {
      if (g is! Map) continue;
      // Solo álbumes.
      final pt = (g['primary-type'] ?? g['primaryType'] ?? '').toString().toLowerCase();
      if (pt.isNotEmpty && pt != 'album') continue;

      final id = (g['id'] ?? '').toString().trim();
      final title = (g['title'] ?? '').toString().trim();
      if (id.isEmpty || title.isEmpty) continue;

      final date = (g['first-release-date'] ?? '').toString();
      final year = date.length >= 4 ? date.substring(0, 4) : null;

      // Artist credit suele venir como lista.
      String artistName = '';
      final ac = g['artist-credit'];
      if (ac is List && ac.isNotEmpty) {
        final first = ac.first;
        if (first is Map) {
          final name = (first['name'] ?? '').toString().trim();
          if (name.isNotEmpty) artistName = name;
          final art = first['artist'];
          if (artistName.isEmpty && art is Map) {
            artistName = (art['name'] ?? '').toString().trim();
          }
        }
      } else if (ac is Map) {
        artistName = (ac['name'] ?? '').toString().trim();
      }
      artistName = artistName.isEmpty ? '—' : artistName;

      out.add(
        ExploreAlbumHit(
          releaseGroupId: id,
          title: title,
          artistName: artistName,
          year: year,
          cover250: 'https://coverartarchive.org/release-group/$id/front-250',
          cover500: 'https://coverartarchive.org/release-group/$id/front-500',
        ),
      );
    }

    return ExploreAlbumPage(items: out, total: total, offset: offset, limit: limit);
  }


  // ==================================================
  // 🎬 BUSCAR SOUNDTRACKS (release-groups)
  // ==================================================
  /// Busca release-groups marcados como Soundtrack (secondary-type) por título.
  ///
  /// Mantiene una búsqueda "estricta" (secondarytype:soundtrack) y, si no hay resultados,
  /// un fallback por texto (OST / soundtrack) para cubrir casos mal etiquetados.
  static Future<ExploreAlbumPage> searchSoundtracksByTitle({
    required String title,
    int limit = 30,
    int offset = 0,
  }) async {
    final raw = title.trim();
    if (raw.isEmpty) {
      return ExploreAlbumPage(items: const <ExploreAlbumHit>[], total: 0, offset: offset, limit: limit);
    }

    String squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Permite: "Dune 2021" o "Dune (2021)" (año opcional al final).
    String q = raw;
    String? year;
    final mYear = RegExp(r'(?:\(|\b)(19\d{2}|20\d{2})(?:\)|\b)\s*$').firstMatch(q);
    if (mYear != null) {
      year = mYear.group(1);
      q = q.substring(0, mYear.start).trim();
      q = q.replaceAll(RegExp(r'[\(\)\[\]]+$'), '').trim();
      if (q.isEmpty) q = raw;
    }

    final hasHint = RegExp(r'\b(soundtrack|ost|bso|banda sonora|score)\b', caseSensitive: false).hasMatch(raw);

    // Variantes de búsqueda: mantenemos el título original y agregamos variantes "limpias".
    final variants = <String>[];
    void addVar(String s) {
      final v = squash(s);
      if (v.length < 2) return;
      if (!variants.contains(v)) variants.add(v);
    }

    addVar(q);

    // Variante extra: remueve sufijos/prefijos típicos (pero nunca borra la original).
    var cleaned = q;
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\b(original\s+motion\s+picture\s+soundtrack|motion\s+picture\s+soundtrack|original\s+soundtrack|official\s+soundtrack)\b',
        caseSensitive: false,
      ),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'\b(soundtrack|ost|bso|b\.s\.o\.|banda\s+sonora|score)\b', caseSensitive: false),
      '',
    );
    cleaned = squash(cleaned);
    if (cleaned.isNotEmpty && cleaned.length >= 3) addVar(cleaned);

    // Variantes por separación típica.
    if (q.contains(':')) addVar(q.split(':').first);
    if (q.contains(' - ')) addVar(q.split(' - ').first);
    if (q.contains('-') && !q.contains(' - ')) addVar(q.split('-').first);

    // Variante "The ..." (mejora casos como "Last of Us" → "The Last of Us").
    if (!q.toLowerCase().startsWith('the ')) addVar('The $q');

    String term(String s) {
      final esc = _escLucene(s);
      // Busca tanto por release-group como por release.
      return '(releasegroup:"$esc" OR release:"$esc")';
    }

    final titleClause = variants.map(term).join(' OR ');
    final titleBlock = '($titleClause)';
    final typesClause = '(primarytype:album OR primarytype:other)';

    // Señales típicas: algunos soundtracks vienen mal etiquetados y solo aparecen por tags/texto.
    final signalsClause = '('
        'secondarytype:soundtrack OR '
        'tag:soundtrack OR tag:ost OR tag:score OR '
        'releasegroup:soundtrack OR releasegroup:ost OR releasegroup:score OR '
        'releasegroup:"original soundtrack" OR releasegroup:"original motion picture soundtrack" OR '
        'releasegroup:"music from" OR releasegroup:"banda sonora"'
        ')';

    bool looksLikeSoundtrack(String title, String disambiguation) {
      final s = '${title.trim()} ${disambiguation.trim()}'.toLowerCase();
      if (s.contains('soundtrack')) return true;
      if (RegExp(r'\bost\b').hasMatch(s)) return true;
      if (s.contains('original soundtrack')) return true;
      if (s.contains('motion picture soundtrack')) return true;
      if (s.contains('music from')) return true;
      if (s.contains('banda sonora')) return true;
      if (s.contains(' bso ')) return true;
      if (s.endsWith(' bso')) return true;
      if (s.startsWith('bso ')) return true;
      if (s.contains('score')) return true;
      return false;
    }

    int scoreHit({
      required String title,
      required String artist,
      required String? yearStr,
      required bool hasSoundtrackSecondary,
      required String disambiguation,
    }) {
      final t = title.toLowerCase();
      final ql = q.toLowerCase();
      int score = 0;

      if (hasSoundtrackSecondary) score += 260;
      if (looksLikeSoundtrack(title, disambiguation)) score += 140;

      if (t == ql) score += 90;
      if (t.contains(ql)) score += 35;

      if (hasHint && looksLikeSoundtrack(title, disambiguation)) score += 40;

      if (year != null && yearStr != null && yearStr.startsWith(year!)) score += 20;

      if (artist.toLowerCase() == 'various artists') score += 5;

      return score;
    }

    Future<ExploreAlbumPage> runLucene(
      String lucene, {
      bool filterLowConfidence = false,
      int? fetchLimit,
    }) async {
      final fLimit = fetchLimit ?? limit;
      final url = Uri.parse(
        '$_mbBase/release-group/?query=${Uri.encodeQueryComponent(lucene)}&fmt=json&limit=$fLimit&offset=$offset',
      );
      final res = await _get(url);
      if (res.statusCode != 200) {
        return ExploreAlbumPage(items: const <ExploreAlbumHit>[], total: 0, offset: offset, limit: limit);
      }

      final data = jsonDecode(res.body);
      final rawTotal = (data['count'] as int?) ?? 0;
      final groups = (data['release-groups'] as List?) ?? [];

      final scored = <Map<String, Object>>[];
      final seen = <String>{};

      for (final g in groups) {
        if (g is! Map) continue;

        // Acepta Album y Other (algunos soundtracks vienen como Other).
        final pt = (g['primary-type'] ?? g['primaryType'] ?? '').toString().toLowerCase();
        if (pt.isNotEmpty && pt != 'album' && pt != 'other') continue;

        final id = (g['id'] ?? '').toString().trim();
        final ttl = (g['title'] ?? '').toString().trim();
        if (id.isEmpty || ttl.isEmpty) continue;
        if (seen.contains(id)) continue;
        seen.add(id);

        final date = (g['first-release-date'] ?? '').toString();
        final y = date.length >= 4 ? date.substring(0, 4) : null;

        // Artist credit suele venir como lista.
        String artistName = '';
        final ac = g['artist-credit'];
        if (ac is List && ac.isNotEmpty) {
          final first = ac.first;
          if (first is Map) {
            final name = (first['name'] ?? '').toString().trim();
            if (name.isNotEmpty) artistName = name;
            final art = first['artist'];
            if (artistName.isEmpty && art is Map) {
              artistName = (art['name'] ?? '').toString().trim();
            }
          }
        } else if (ac is Map) {
          artistName = (ac['name'] ?? '').toString().trim();
        }
        artistName = artistName.isEmpty ? '—' : artistName;

        final disambiguation = (g['disambiguation'] ?? '').toString().trim();
        bool hasSoundtrackSecondary = false;
        final sec = g['secondary-types'] ?? g['secondaryTypes'];
        if (sec is List) {
          hasSoundtrackSecondary = sec.any((e) => e.toString().toLowerCase() == 'soundtrack');
        }

        final score = scoreHit(
          title: ttl,
          artist: artistName,
          yearStr: y,
          hasSoundtrackSecondary: hasSoundtrackSecondary,
          disambiguation: disambiguation,
        );

        final hit = ExploreAlbumHit(
          releaseGroupId: id,
          title: ttl,
          artistName: artistName,
          year: y,
          cover250: 'https://coverartarchive.org/release-group/$id/front-250',
          cover500: 'https://coverartarchive.org/release-group/$id/front-500',
        );

        scored.add({'hit': hit, 'score': score});
      }

      scored.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
      var hits = scored.map((e) => e['hit'] as ExploreAlbumHit).toList();

      if (filterLowConfidence) {
        final filtered = <ExploreAlbumHit>[];
        for (final e in scored) {
          final s = e['score'] as int;
          // 140: keyword fuerte o secundario soundtrack.
          if (s >= 140) filtered.add(e['hit'] as ExploreAlbumHit);
        }
        if (filtered.isNotEmpty) hits = filtered;
      }

      if (hits.length > limit) hits = hits.sublist(0, limit);

      return ExploreAlbumPage(items: hits, total: rawTotal, offset: offset, limit: limit);
    }

    String strictLucene([String? y]) {
      final yClause = (y != null && y.isNotEmpty) ? ' AND firstreleasedate:${_escLucene(y)}*' : '';
      return '$typesClause AND secondarytype:soundtrack AND $titleBlock$yClause';
    }

    String hintedLucene([String? y]) {
      final yClause = (y != null && y.isNotEmpty) ? ' AND firstreleasedate:${_escLucene(y)}*' : '';
      return '$typesClause AND $signalsClause AND $titleBlock$yClause';
    }

    String broadLucene([String? y]) {
      final yClause = (y != null && y.isNotEmpty) ? ' AND firstreleasedate:${_escLucene(y)}*' : '';
      return '$typesClause AND $titleBlock$yClause';
    }

    // 1) Estricto: secondarytype:soundtrack (con año opcional).
    if (year != null) {
      final p = await runLucene(strictLucene(year));
      if (p.total > 0 || p.items.isNotEmpty) return p;
    }
    final p1 = await runLucene(strictLucene());
    if (p1.total > 0 || p1.items.isNotEmpty) return p1;

    // 2) Hinted: usa tags/texto para casos mal etiquetados.
    if (year != null) {
      final p = await runLucene(hintedLucene(year));
      if (p.total > 0 || p.items.isNotEmpty) return p;
    }
    final p2 = await runLucene(hintedLucene());
    if (p2.total > 0 || p2.items.isNotEmpty) return p2;

    // 3) Muy amplio por título + ranking/filtrado de confianza (mejor que devolver vacío).
    int fetchLimit = limit * 3;
    if (fetchLimit < limit) fetchLimit = limit;
    if (fetchLimit > 100) fetchLimit = 100;

    if (year != null) {
      final p = await runLucene(broadLucene(year), filterLowConfidence: true, fetchLimit: fetchLimit);
      if (p.items.isNotEmpty) return p;
    }
    return runLucene(broadLucene(), filterLowConfidence: true, fetchLimit: fetchLimit);
  }

  /// Autocompletado para Soundtracks (desde 1 letra).
  ///
  /// Esta búsqueda está optimizada para *sugerencias* (rápida y tolerante a parcial):
  /// - Usa prefijos con wildcard (token*) en `releasegroup:` y `release:`.
  /// - Prioriza resultados con secondary-type `soundtrack` o señales típicas (OST/score).
  /// - Evita traer demasiados resultados para no saturar MusicBrainz.
  static Future<List<ExploreAlbumHit>> autocompleteSoundtracks({
    required String title,
    int limit = 10,
  }) async {
    final raw = title.trim();
    if (raw.isEmpty) return <ExploreAlbumHit>[];

    String squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Limpia caracteres muy ruidosos para consultas parciales.
    var q = raw;
    q = q.replaceAll(RegExp(r'[\(\)\[\]\{\}"]'), ' ');
    q = squash(q);
    if (q.isEmpty) return <ExploreAlbumHit>[];

    // Tokens para AND: permitimos 1 letra solo cuando el usuario realmente está escribiendo 1 letra (autocomplete).
    final compact = q.replaceAll(' ', '');
    final isSingleChar = compact.length == 1;
    final minTokLen = isSingleChar ? 1 : 2;

    final toks = q
        .split(RegExp(r'\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e.length >= minTokLen)
        .toList();
    if (toks.isEmpty) return <ExploreAlbumHit>[];

    final typesClause = '(primarytype:album OR primarytype:other)';
    final signalsClause = '(' 
        'secondarytype:soundtrack OR '
        'tag:soundtrack OR tag:ost OR tag:score OR '
        'releasegroup:soundtrack OR releasegroup:ost OR releasegroup:score OR '
        'releasegroup:"original soundtrack" OR releasegroup:"original motion picture soundtrack" OR '
        'releasegroup:"music from" OR releasegroup:"banda sonora"'
        ')';

    String tokClause(String t) {
      final esc = _escLucene(t);
      // Prefijo para parcial.
      return '(releasegroup:${esc}* OR release:${esc}*)';
    }

    final titleClause = toks.map(tokClause).join(' AND ');

    bool looksLikeSoundtrack(String title, String disambiguation) {
      final s = '${title.trim()} ${disambiguation.trim()}'.toLowerCase();
      if (s.contains('soundtrack')) return true;
      if (RegExp(r'\bost\b').hasMatch(s)) return true;
      if (s.contains('original soundtrack')) return true;
      if (s.contains('motion picture soundtrack')) return true;
      if (s.contains('music from')) return true;
      if (s.contains('banda sonora')) return true;
      if (s.contains('score')) return true;
      return false;
    }

    int scoreHit({
      required String title,
      required String artist,
      required bool hasSoundtrackSecondary,
      required String disambiguation,
    }) {
      final t = title.toLowerCase();
      final ql = q.toLowerCase();
      int score = 0;
      if (hasSoundtrackSecondary) score += 240;
      if (looksLikeSoundtrack(title, disambiguation)) score += 140;
      if (t == ql) score += 80;
      if (t.contains(ql)) score += 40;
      if (artist.toLowerCase() == 'various artists') score += 5;
      return score;
    }

    Future<List<ExploreAlbumHit>> runLucene(String lucene, {bool filterLowConfidence = false}) async {
      // Para sugerencias: un fetch un poco más alto y luego recorte.
      int fetchLimit = limit * 3;
      if (fetchLimit < 20) fetchLimit = 20;
      if (fetchLimit > 50) fetchLimit = 50;

      final url = Uri.parse(
        '$_mbBase/release-group/?query=${Uri.encodeQueryComponent(lucene)}&fmt=json&limit=$fetchLimit&offset=0',
      );
      final res = await _get(url);
      if (res.statusCode != 200) return <ExploreAlbumHit>[];

      final data = jsonDecode(res.body);
      final groups = (data['release-groups'] as List?) ?? [];

      final scored = <Map<String, Object>>[];
      final seen = <String>{};

      for (final g in groups) {
        if (g is! Map) continue;
        final pt = (g['primary-type'] ?? g['primaryType'] ?? '').toString().toLowerCase();
        if (pt.isNotEmpty && pt != 'album' && pt != 'other') continue;

        final id = (g['id'] ?? '').toString().trim();
        final ttl = (g['title'] ?? '').toString().trim();
        if (id.isEmpty || ttl.isEmpty) continue;
        if (seen.contains(id)) continue;
        seen.add(id);

        final date = (g['first-release-date'] ?? '').toString();
        final y = date.length >= 4 ? date.substring(0, 4) : null;

        String artistName = '';
        final ac = g['artist-credit'];
        if (ac is List && ac.isNotEmpty) {
          final first = ac.first;
          if (first is Map) {
            final name = (first['name'] ?? '').toString().trim();
            if (name.isNotEmpty) artistName = name;
            final art = first['artist'];
            if (artistName.isEmpty && art is Map) {
              artistName = (art['name'] ?? '').toString().trim();
            }
          }
        } else if (ac is Map) {
          artistName = (ac['name'] ?? '').toString().trim();
        }
        artistName = artistName.isEmpty ? '—' : artistName;

        final disambiguation = (g['disambiguation'] ?? '').toString().trim();
        bool hasSoundtrackSecondary = false;
        final sec = g['secondary-types'] ?? g['secondaryTypes'];
        if (sec is List) {
          hasSoundtrackSecondary = sec.any((e) => e.toString().toLowerCase() == 'soundtrack');
        }

        final score = scoreHit(
          title: ttl,
          artist: artistName,
          hasSoundtrackSecondary: hasSoundtrackSecondary,
          disambiguation: disambiguation,
        );

        final hit = ExploreAlbumHit(
          releaseGroupId: id,
          title: ttl,
          artistName: artistName,
          year: y,
          cover250: 'https://coverartarchive.org/release-group/$id/front-250',
          cover500: 'https://coverartarchive.org/release-group/$id/front-500',
        );

        scored.add({'hit': hit, 'score': score});
      }

      scored.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

      var hits = scored.map((e) => e['hit'] as ExploreAlbumHit).toList();
      if (filterLowConfidence) {
        final filtered = <ExploreAlbumHit>[];
        for (final e in scored) {
          final s = e['score'] as int;
          if (s >= 140) filtered.add(e['hit'] as ExploreAlbumHit);
        }
        if (filtered.isNotEmpty) hits = filtered;
      }

      if (hits.length > limit) hits = hits.sublist(0, limit);
      return hits;
    }

    // 1) Con señales (mejor precisión).
    final lucene1 = '$typesClause AND $signalsClause AND $titleClause';
    final hits1 = await runLucene(lucene1);
    if (hits1.isNotEmpty) return hits1;

    // 2) Fallback: amplio por título, pero filtrado por confianza.
    final lucene2 = '$typesClause AND $titleClause';
    return runLucene(lucene2, filterLowConfidence: true);
  }

  // ============================================
  // 🎵 BUSCAR CANCIÓN (para filtrar discografía)
  // ============================================
  /// Sugerencias de canciones (autocomplete) para un artista.
  ///
  /// Devuelve una lista corta y deduplicada de títulos (con su recording id)
  /// para poder aplicar el filtro con un click.
  static Future<List<SongHit>> searchSongSuggestions({
    required String artistId,
    required String songQuery,
    int limit = 8,
  }) async {
    final arid = artistId.trim();
    final q = songQuery.trim();
    if (arid.isEmpty || q.isEmpty) return <SongHit>[];

    const specialChars = '+-!(){}[]^"~*?:\\/&|';
    String esc(String s) {
      final sb = StringBuffer();
      for (final rune in s.runes) {
        final ch = String.fromCharCode(rune);
        if (specialChars.contains(ch)) sb.write('\\');
        sb.write(ch);
      }
      return sb.toString();
    }

    final tokens = q.split(RegExp(r'\s+')).where((t) => t.trim().isNotEmpty).toList();
    if (tokens.isEmpty) return <SongHit>[];

    late final String recPart;
    if (tokens.length == 1) {
      final term = esc(tokens.first);
      // Con 1 letra ya queremos sugerencias: siempre wildcard.
      recPart = 'recording:${term}*';
    } else {
      final phrase = esc(q);
      recPart = 'recording:"$phrase"';
    }

    final lucene = '$recPart AND arid:$arid';
    final url = Uri.parse(
      '$_mbBase/recording/?query=${Uri.encodeQueryComponent(lucene)}&fmt=json&limit=$limit',
    );
    final res = await _get(url);
    if (res.statusCode != 200) return <SongHit>[];

    final data = jsonDecode(res.body);
    final recs = (data['recordings'] as List?) ?? [];

    final out = <SongHit>[];
    final seen = <String>{};
    for (final r in recs) {
      if (r is! Map) continue;
      final id = (r['id'] ?? '').toString().trim();
      final title = (r['title'] ?? '').toString().trim();
      if (id.isEmpty || title.isEmpty) continue;

      final k = title.toLowerCase();
      if (seen.contains(k)) continue;
      seen.add(k);

      out.add(
        SongHit(
          id: id,
          title: title,
          score: (r['score'] as num?)?.toInt(),
        ),
      );
    }
    return out;
  }



  /// ✅ Pro: devuelve álbumes (release-groups) donde aparece una canción.
  ///
  /// Esto permite mostrar al tipear la canción una lista de *álbumes* (con año)
  /// sin depender de que la discografía esté completamente cargada/paginada.
  ///
  /// Estrategia (rápida):
  /// 1) Search de recordings por (título + artista)
  /// 2) Tomar pocos `recordingId` candidatos
  /// 3) Lookup de cada recording -> releases -> release-groups (filtra a Album)
  /// 4) Dedupe y ordena por año

  /// ✅ Enfoque "como el sitio de MusicBrainz":
  /// Artista -> Discography -> Albums, y dentro de esa lista busca la canción
  /// en el tracklist de una edición preferentemente en CD.
  ///
  /// Ventaja: evita que "ganen" compilados/en vivo cuando el usuario busca
  /// el álbum principal donde sale el tema.
  ///
  /// NOTA: puede ser más lento que el search de recordings, por eso está
  /// cacheado a nivel de tracklist por release-group.
  static Future<List<AlbumItem>> searchSongAlbumsInArtistAlbumsPreferCd({
    required String artistId,
    required String songQuery,
    int maxScanAlbums = 220,
    int maxMatches = 25,
    bool includeLiveAndCompilation = false,
  }) async {
    final arid = artistId.trim();
    final rawQ = songQuery.trim();
    final q = _sanitizeSongQuery(rawQ);
    if (arid.isEmpty || q.isEmpty) return <AlbumItem>[];

    final wantNorm = normalizeKey(q);
    final wantTokens = wantNorm
        .split(RegExp(' +'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // Trae discografía del artista y luego filtramos SOLO a primary-type Album.
    // Además excluimos secondary-types Live/Compilation
    // usando lookup del release-group solo si es necesario.
    final discog = await getDiscographyByArtistId(arid);
    if (discog.isEmpty) return <AlbumItem>[];

    final out = <AlbumItem>[];
    final seen = <String>{};

    // Limitar para no explotar en artistas enormes.
    final toScan = discog.take(math.min(maxScanAlbums, discog.length)).toList();

    for (final alb in toScan) {
      // SOLO Albums (estudio): primary-type Album y excluyendo Live/Compilation.
      // En modo estricto: si no podemos confirmar que es Album de estudio, NO lo consideramos.
      final rgid = alb.releaseGroupId.trim();
      if (rgid.isEmpty) continue;

      final pt = alb.primaryType.trim().toLowerCase();
      final secs = alb.secondaryTypes
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toList();

      // Si ya viene marcado como Live/Compilation, descartamos altiro.
      if (!includeLiveAndCompilation && (secs.contains('live') || secs.contains('compilation'))) continue;

      // Si el primary-type viene y NO es Album, descartamos.
      if (pt.isNotEmpty && pt != 'album') continue;

      // Si falta metadata (primary/secondary), confirmamos con lookup del release-group.
      if (pt.isEmpty || secs.isEmpty) {
        final rg = await _rgDetailsCached(rgid) ?? await _rgDetailsFetch(rgid);
        // `rg` es nullable: en modo estricto, sin datos -> no incluir.
        if (rg == null) continue;
        final p = (rg['primary-type'] ?? '').toString().trim().toLowerCase();
        if (p != 'album') continue;
        if (!includeLiveAndCompilation && (_isLiveReleaseGroup(rg) || _isCompilationReleaseGroup(rg))) continue;
      }

      // Tracklist preferiendo CD.
      Map<String, dynamic>? ti = await _rgTracksInfoCachedCd(rgid);
      if (ti == null) {
        ti = await _rgTracksInfoFetchPreferCd(rgid);
        if (ti != null) {
          await _rgTracksInfoStoreCd(rgid, ti);
        }
      }
      // Si no pudimos obtener por CD, caemos al método estándar (mejor edición).
      ti ??= await _rgTracksInfoCached(rgid);
      if (ti == null) {
        final fetched = await _rgTracksInfoFetch(rgid);
        if (fetched != null) {
          await _rgTracksInfoStore(rgid, fetched);
          ti = fetched;
        }
      }
      if (ti == null) continue;

      final tracks = (ti['tracks'] as List?) ?? const <dynamic>[];
      bool ok = false;
      for (final t in tracks) {
        if (t is! Map) continue;
        final tn = (t['n'] ?? '').toString();
        if (_trackTitleMatches(tn, wantNorm, wantTokens)) {
          ok = true;
          break;
        }
      }
      if (!ok) continue;

      if (seen.contains(rgid)) continue;
      seen.add(rgid);

      out.add(alb);
      if (out.length >= maxMatches) break;
    }

    return out;
  }

static Future<List<AlbumItem>> searchSongAlbums({
  required String artistId,
  required String songQuery,
  int maxAlbums = 25,
  int recordingSearchLimit = 40,
  int maxRecordings = 20,
  String? preferredRecordingId,
}) async {
  final arid = artistId.trim();
  final rawQ = songQuery.trim();
  final q = _sanitizeSongQuery(rawQ);
  if (arid.isEmpty || q.isEmpty) return <AlbumItem>[];

  String norm(String s) {
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
    out = out.replaceAll(RegExp(' +'), ' ').trim();
    return out;
  }

  // Construye query Lucene (MusicBrainz search)
  final tokens = q.split(RegExp(' +')).where((t) => t.trim().isNotEmpty).toList();
  if (tokens.isEmpty) return <AlbumItem>[];

  late final String recPart;
  if (tokens.length == 1) {
    final term = _escLucene(tokens.first);
    // Para canciones cortas (Zoom, Suede, etc.) un wildcard solo puede traer mucho ruido.
    // Combinamos exact match + prefix wildcard para mantener recall sin perder precisión.
    recPart = '(recording:"$term" OR recording:${term}*)';
  } else {
    final phrase = _escLucene(q);
    final terms = tokens.map(_escLucene).toList();
    recPart = '(recording:"$phrase" OR recording:(${terms.join(' AND ')}))';
  }

  final lucene = '$recPart AND arid:$arid';
  final searchUrl = Uri.parse(
    '$_mbBase/recording/?query=${Uri.encodeQueryComponent(lucene)}&fmt=json&limit=$recordingSearchLimit',
  );

  final res = await _get(searchUrl);
  if (res.statusCode != 200) return <AlbumItem>[];

  dynamic data;
  try {
    data = jsonDecode(res.body);
  } catch (_) {
    return <AlbumItem>[];
  }

  final recs = (data is Map ? (data['recordings'] as List?) : null) ?? const <dynamic>[];
  if (recs.isEmpty && (preferredRecordingId ?? '').trim().isEmpty) return <AlbumItem>[];

  final want = norm(q);
  final wantTokens = want.split(' ').where((t) => t.trim().isNotEmpty).toList();

  bool matchesTitle(String titleNorm) {
    if (wantTokens.isEmpty) return true;
    if (wantTokens.length == 1) {
      final w = wantTokens.first;
      if (w.length <= 1) return true;
      return titleNorm.contains(w);
    }
    final strong = wantTokens.where((t) => t.length >= 2).toList();
    if (strong.isEmpty) return true;
    return strong.every((t) => titleNorm.contains(t));
  }

  int titlePenalty(String title) {
    final t = title.toLowerCase();
    int p = 0;
    // Penalizaciones fuertes para versiones que suelen "ganar" en el search
    // pero NO son el recording de estudio.
    if (RegExp(r'\b(live|en\s+vivo)\b').hasMatch(t)) p += 90;
    if (RegExp(r'\b(compilation|greatest\s+hits|hits)\b').hasMatch(t)) p += 50;
    if (RegExp(r'\b(remaster|remastered)\b').hasMatch(t)) p += 35;
    if (RegExp(r'\b(demo)\b').hasMatch(t)) p += 70;
    if (RegExp(r'\b(edit|radio\s+edit)\b').hasMatch(t)) p += 25;
    if (RegExp(r'\b(remix|mix)\b').hasMatch(t)) p += 30;
    if (RegExp(r'\b(version|acoustic|instrumental)\b').hasMatch(t)) p += 20;
    return p;
  }

  final candidates = <String>[];
  final seenRec = <String>{};
  final Map<String, int> recScore = {};

  void addRec(String id, {int score = 0}) {
    final rid = id.trim();
    if (rid.isEmpty) return;
    if (seenRec.contains(rid)) return;
    seenRec.add(rid);
    candidates.add(rid);
    recScore[rid] = score;
  }

  if ((preferredRecordingId ?? '').trim().isNotEmpty) {
    addRec(preferredRecordingId!.trim(), score: 100);
  }

  for (final r in recs) {
    if (r is! Map) continue;
    final rid = (r['id'] ?? '').toString().trim();
    final title = (r['title'] ?? '').toString().trim();
    if (rid.isEmpty) continue;

    // Si no hay título, igual lo dejamos como candidato (lo resolveremos por lookup).
    final ok = title.isEmpty ? true : matchesTitle(norm(title));
    if (!ok && want.length >= 4 && candidates.isNotEmpty) {
      // Si escribió bastante y ya tenemos uno, evitamos ruido.
      continue;
    }

    final sc = (r['score'] is num) ? (r['score'] as num).toInt() : 0;
    final effective = title.isEmpty ? sc : (sc - titlePenalty(title));
    addRec(rid, score: effective);
    if (candidates.length >= maxRecordings) break;
  }

  if (candidates.isEmpty) return <AlbumItem>[];

  // Aggregate por release-group
  final Map<String, Map<String, dynamic>> agg = {}; // id -> {title, year, earliest, score, nonStudio, knownType}


  void upsert(
    String id, {
    String? title,
    DateTime? dt,
    String? year,
    required int score,
    bool? nonStudio,
    required bool knownType,
    int? recLenMs,
  }) {
    final cur = agg[id] ?? <String, dynamic>{
      'title': '',
      'year': null,
      'earliest': null,
      'score': 0,
      'nonStudio': nonStudio,
      'knownType': knownType,
      'recLens': <int>[],
      'trackOk': null,
      'trackLen': null,
    };

    // title
    final curTitle = (cur['title'] ?? '').toString();
    if (curTitle.trim().isEmpty && (title ?? '').trim().isNotEmpty) {
      cur['title'] = title;
    }

    // earliest/year
    final curDt = cur['earliest'] as DateTime?;
    if (curDt == null || (dt != null && dt.isBefore(curDt))) {
      cur['earliest'] = dt;
    }
    if (((cur['year'] ?? '').toString()).trim().isEmpty && (year ?? '').trim().isNotEmpty) {
      cur['year'] = year;
    }

    // score (max)
    final curScore = (cur['score'] is int) ? (cur['score'] as int) : 0;
    if (score > curScore) cur['score'] = score;

    // type flags
    if (knownType) cur['knownType'] = true;
    if (nonStudio != null) cur['nonStudio'] = nonStudio;

    // recording lengths seen for this release-group (ms)
    if (recLenMs != null && recLenMs > 0) {
      final List<int> lens = (cur['recLens'] is List)
          ? (cur['recLens'] as List).whereType<num>().map((n) => n.toInt()).toList()
          : <int>[];
      if (!lens.contains(recLenMs)) lens.add(recLenMs);
      cur['recLens'] = lens;
    }

    agg[id] = cur;
  }


  int biasFromRec(String rid) {
    final sc = recScore[rid] ?? 0;
    var b = (sc / 5).floor(); // 0..20 aprox
    if (b < 0) b = 0;
    if (b > 20) b = 20;
    return b;
  }

  // Procesamos recordings en cola: si un recording es "live recording of" otro,
  // agregamos el recording base para poder llegar al álbum de estudio.
  var i = 0;
  var processed = 0;
  final maxProcessRecordings = math.min(25, maxRecordings + 8);

  while (i < candidates.length && processed < maxProcessRecordings) {
    final rid = candidates[i++];
    processed++;

    final lookupUrl = Uri.parse('$_mbBase/recording/$rid?inc=releases+release-groups+recording-rels&fmt=json');
    final rr = await _get(lookupUrl);
    if (rr.statusCode != 200) continue;

    dynamic d;
    try {
      d = jsonDecode(rr.body);
    } catch (_) {
      continue;
    }

    final recLenMs = (d is Map && d['length'] is num) ? (d['length'] as num).toInt() : null;

    // Si este recording es una versión live/edit/etc. de otro, sumamos el recording base.
    final rels = (d is Map ? (d['relations'] as List?) : null) ?? const <dynamic>[];
    for (final rel in rels) {
      if (rel is! Map) continue;
      final tt = (rel['target-type'] ?? '').toString().trim().toLowerCase();
      if (tt.isNotEmpty && tt != 'recording') continue;
      final type = (rel['type'] ?? '').toString().trim().toLowerCase();
      const wanted = <String>{
        'live recording of',
        'remaster of',
        'edit of',
        'instrumental of',
        'karaoke version of',
      };
      if (!wanted.contains(type)) continue;
      final trg = rel['recording'];
      if (trg is! Map) continue;
      final baseId = (trg['id'] ?? '').toString().trim();
      if (baseId.isEmpty) continue;
      // Le damos un pequeño boost para que el base gane sobre el live.
      final baseScore = (recScore[rid] ?? 0) + 15;
      addRec(baseId, score: baseScore);
    }

    final recBias = biasFromRec(rid);
    final releases = (d is Map ? (d['releases'] as List?) : null) ?? const <dynamic>[];
    for (final rel in releases) {
      if (rel is! Map) continue;
      final status = (rel['status'] ?? '').toString().trim().toLowerCase();
      final isOfficial = status.isEmpty || status == 'official';

      final rg = rel['release-group'];
      if (rg is Map) {
        final id = (rg['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;

        final pt = (rg['primary-type'] ?? '').toString().trim().toLowerCase();
        if (pt.isNotEmpty && pt != 'album') continue;

        final isLive = _isLiveReleaseGroup(rg);
        final isComp = _isCompilationReleaseGroup(rg);
        final nonStudio = isLive || isComp;
        final title = (rg['title'] ?? '').toString().trim();
        // Para el "año del álbum" preferimos first-release-date del release-group
        // (evita que una reedición con fecha más reciente gane).
        final dt = _parseMbDate(rg['first-release-date']) ?? _parseMbDate(rel['date']);
        final y = dt != null ? dt.year.toString().padLeft(4, '0') : ((rg['first-release-date'] ?? rel['date'] ?? '').toString().trim());
        final year = y.length >= 4 ? y.substring(0, 4) : null;

        var score = 120 + recBias + (isOfficial ? 45 : 0);
        if (isLive) {
          score -= 500;
        } else if (isComp) {
          score -= 320;
        }

        // Si podemos determinar que el release-group NO es del artista,
        // bajamos el score (evita Various Artists cuando MB lo entrega).
        final acOk = _artistCreditIncludes(rg['artist-credit'], arid);
        if (acOk == false) score -= 120;
        upsert(
          id,
          title: title,
          dt: dt,
          year: year,
          score: score,
          nonStudio: nonStudio,
          knownType: true,
          recLenMs: recLenMs,
        );
      } else if (rg is String) {
        // A veces MB devuelve solo el id del release-group.
        final id = rg.trim();
        if (id.isEmpty) continue;

        final dt = _parseMbDate(rel['date']);
        final year = dt != null ? dt.year.toString().padLeft(4, '0') : null;
        final title = (rel['title'] ?? '').toString().trim();
        final score = 80 + recBias + (isOfficial ? 20 : 0);
        upsert(
          id,
          title: title,
          dt: dt,
          year: year,
          score: score,
          nonStudio: null,
          knownType: false,
          recLenMs: recLenMs,
        );
      }
    }

    // Si ya juntamos bastante, cortamos para no hacer demasiados lookups.
    if (agg.length >= (maxAlbums * 3)) break;
  }

  if (agg.isEmpty) return <AlbumItem>[];

  // Enriquecer: completar título/año y clasificar nonStudio cuando el RG vino como string.
  final toLookup = agg.entries
      .where((e) {
        final v = e.value;
        final known = (v['knownType'] == true);
        final title = (v['title'] ?? '').toString().trim();
        final year = (v['year'] ?? '').toString().trim();
        final ns = v['nonStudio'];
        return !known || title.isEmpty || year.isEmpty || ns == null;
      })
      .map((e) => e.key)
      .toList();

  final drops = <String>{};

  // Priorizamos lookups por fecha (más antiguos primero) y score.
  // Esto evita que el filtro se quede solo con compilaciones/en vivo cuando
  // el release-group correcto llegó como id (string) y aún no tiene título/tipo.
  toLookup.sort((a, b) {
    final da = agg[a]?['earliest'] as DateTime?;
    final db = agg[b]?['earliest'] as DateTime?;
    final sa = (agg[a]?['score'] is int) ? (agg[a]!['score'] as int) : 0;
    final sb = (agg[b]?['score'] is int) ? (agg[b]!['score'] as int) : 0;

    // Importante: no empujar los "sin fecha" al final de forma rígida.
    // En casos como Suedehead/Zoom, el release-group correcto puede venir como
    // string y sin `rel.date`, quedando con earliest==null. Si lo mandamos al
    // final, nunca lo enriquecemos y terminan ganando compilaciones/en vivo.
    if (da == null || db == null) {
      final c = sb.compareTo(sa);
      if (c != 0) return c;
      if (da == null && db != null) return 1;
      if (db == null && da != null) return -1;
      return 0;
    }

    // Ambos con fecha: más antiguo primero, y dentro de eso mejor score.
    final c = da.compareTo(db);
    if (c != 0) return c;
    return sb.compareTo(sa);
  });

  // En algunos casos (p.ej. "Suedehead", "Zoom"), el release-group correcto llega
  // solo como id (string) y queda como "unknown" hasta que se hace lookup.
  // Si el set de release-groups es grande, cortar muy temprano hace que ganen
  // compilaciones/en vivo simplemente porque venían completos.
  // Ajuste: permitir más lookups cuando hay muchos release-groups "string".
  // Mantener un techo razonable para no castigar rendimiento.
  final int maxRgLookups = math.max(80, maxAlbums * 4);
  var looked = 0;

  for (final id in toLookup) {
    if (looked >= maxRgLookups) break;

    final v = agg[id];
    if (v == null) continue;
    final known = (v['knownType'] == true);
    final title0 = (v['title'] ?? '').toString().trim();
    final year0 = (v['year'] ?? '').toString().trim();
    final ns0 = v['nonStudio'];
    if (known && title0.isNotEmpty && year0.isNotEmpty && ns0 != null) continue;

    Map<String, dynamic>? j = await _rgDetailsCached(id);
    if (j == null) {
      try {
        final u = Uri.parse('$_mbBase/release-group/$id?fmt=json');
        final r = await _get(u);
        if (r.statusCode != 200) continue;
        final decoded = jsonDecode(r.body);
        if (decoded is! Map) continue;
        j = decoded.cast<String, dynamic>();
        await _rgDetailsStore(id, j);
      } catch (_) {
        continue;
      }
    }

    looked++;

    final pt = (j['primary-type'] ?? '').toString().trim().toLowerCase();
    if (pt.isNotEmpty && pt != 'album') {
      drops.add(id);
      continue;
    }

    final title = (j['title'] ?? '').toString().trim();
    final dt = _parseMbDate(j['first-release-date']);
    final year = dt != null ? dt.year.toString().padLeft(4, '0') : ((j['first-release-date'] ?? '').toString().trim());
    final yy = year.length >= 4 ? year.substring(0, 4) : null;

    final isLive = _isLiveReleaseGroup(j);
    final isComp = _isCompilationReleaseGroup(j);
    final nonStudio = isLive || isComp;
    var curScore = (agg[id]?['score'] is int) ? (agg[id]!['score'] as int) : 0;
    if (isLive) {
      curScore -= 500;
    } else if (isComp) {
      curScore -= 320;
    }
    final acOk = _artistCreditIncludes(j['artist-credit'], arid);
    if (acOk == false) curScore -= 120;
    upsert(
      id,
      title: title,
      dt: dt,
      year: yy,
      score: curScore,
      nonStudio: nonStudio,
      knownType: true,
    );

    // Nota: NO cortamos anticipadamente aquí. En casos como "Suedehead" o "Zoom",
    // el álbum correcto de estudio a veces llega como release-group id (string)
    // y necesita lookup para aparecer (si cortamos temprano, ganan compilaciones/en vivo).
  }

  for (final id in drops) {
    agg.remove(id);
  }

  if (agg.isEmpty) return <AlbumItem>[];

  // Verificación extra: confirmamos que el track realmente existe dentro del álbum
  // (y si tenemos duration, la usamos para preferir la versión de estudio).
  final wantNorm2 = normalizeKey(q);
  final wantTokens2 = wantNorm2.split(' ').where((t) => t.trim().isNotEmpty).toList();

  // Verificamos primero los candidatos de estudio. Si no hay, probamos con los "unknown".
  // Ordenamos priorizando los más antiguos, porque el usuario busca el álbum "original".
  final studioForVerify = agg.entries.where((e) => e.value['nonStudio'] == false).toList();
  final unknownForVerify = agg.entries.where((e) => e.value['nonStudio'] == null).toList();
  final verify = studioForVerify.isNotEmpty ? studioForVerify : unknownForVerify;

  verify.sort((a, b) {
    final da = a.value['earliest'] as DateTime?;
    final db = b.value['earliest'] as DateTime?;
    if (da == null && db == null) {
      final sa = (a.value['score'] is int) ? (a.value['score'] as int) : 0;
      final sb = (b.value['score'] is int) ? (b.value['score'] as int) : 0;
      return sb.compareTo(sa);
    }
    if (da == null) return 1;
    if (db == null) return -1;
    final c = da.compareTo(db); // más antiguo primero
    if (c != 0) return c;
    final sa = (a.value['score'] is int) ? (a.value['score'] as int) : 0;
    final sb = (b.value['score'] is int) ? (b.value['score'] as int) : 0;
    return sb.compareTo(sa);
  });

  const int verifyMax = 15;
  for (final e in verify.take(verifyMax)) {
    final id = e.key;
    final v = agg[id];
    if (v == null) continue;

    Map<String, dynamic>? ti = await _rgTracksInfoCached(id);
    if (ti == null) {
      ti = await _rgTracksInfoFetch(id);
      if (ti != null) {
        await _rgTracksInfoStore(id, ti);
      }
    }
    if (ti == null) continue;

    final tlen = _bestTrackLenMsForSong(ti, wantNorm2, wantTokens2);
    if (tlen == null) {
      // No encontramos el track en el tracklist del release elegido.
      // Penalización suave: puede ser una edición incompleta.
      if (v['trackOk'] == null) v['trackOk'] = false;
      final cs = (v['score'] is int) ? (v['score'] as int) : 0;
      v['score'] = cs - 25;
      continue;
    }

    // Track encontrado.
    v['trackOk'] = true;
    if (tlen > 0) v['trackLen'] = tlen;

    var delta = 70; // boost base por confirmación

    // Si tenemos duraciones, preferimos la que calza con el recording.
    if (tlen > 0) {
      final lensRaw = v['recLens'];
      final lens = (lensRaw is List) ? lensRaw.whereType<num>().map((n) => n.toInt()).where((n) => n > 0).toList() : <int>[];
      if (lens.isNotEmpty) {
        var bestDiff = 1 << 30;
        for (final rl in lens) {
          final d = (tlen - rl).abs();
          if (d < bestDiff) bestDiff = d;
        }
        if (bestDiff <= 4000) {
          delta += 150;
        } else if (bestDiff <= 8000) {
          delta += 90;
        } else if (bestDiff <= 15000) {
          delta += 35;
        } else {
          delta -= 70;
        }
      } else {
        // No tenemos length del recording, igual damos boost moderado.
        delta += 20;
      }
    }

    final cs = (v['score'] is int) ? (v['score'] as int) : 0;
    v['score'] = cs + delta;
  }

  final studio = agg.entries.where((e) => e.value['nonStudio'] == false).toList();
  final unknown = agg.entries.where((e) => e.value['nonStudio'] == null).toList();
  final nonStudio = agg.entries.where((e) => e.value['nonStudio'] == true).toList();

  final studioOk = studio.where((e) => e.value['trackOk'] == true).toList();
  final unknownOk = unknown.where((e) => e.value['trackOk'] == true).toList();

  final selected = studioOk.isNotEmpty
      ? studioOk
      : (studio.isNotEmpty
          ? studio
          : (unknownOk.isNotEmpty
              ? unknownOk
              : (unknown.isNotEmpty ? unknown : nonStudio)));

  _dbgSongFilter('query="$q" recs=${candidates.length} rg=${agg.length} studio=${studio.length} studioOk=${studioOk.length} unknown=${unknown.length} unknownOk=${unknownOk.length} nonStudio=${nonStudio.length}');
  if (selected.isEmpty) return <AlbumItem>[];


  // Construimos salida con year calculable incluso si no vino explícito.
  int yearFrom(String y, DateTime? dt) {
    final yy = int.tryParse(y);
    if (yy != null && yy > 0 && yy < 9999) return yy;
    if (dt != null) return dt.year;
    return 9999;
  }

  final tmp = <Map<String, dynamic>>[];
  for (final e in selected) {
    final id = e.key;
    final v = e.value;
    final title = (v['title'] ?? '').toString().trim();
    if (title.isEmpty) continue;
    final y = (v['year'] ?? '').toString().trim();
    final dt = v['earliest'] as DateTime?;
    final ns = v['nonStudio'];
    final score = (v['score'] is int) ? (v['score'] as int) : 0;
    tmp.add({
      'id': id,
      'title': title,
      'yearStr': y,
      'year': yearFrom(y, dt),
      'dt': dt,
      'nonStudio': ns,
      'score': score,
    });
  }

  // ✅ Mostrar TODOS los álbumes donde aparece la canción (no solo el más antiguo).
  // Orden: studio primero, luego unknown, luego live/compilation. Dentro: año (asc) y score (desc).
  tmp.sort((a, b) {
    int nsRank(dynamic v) {
      if (v == false) return 0; // studio
      if (v == null) return 1;  // unknown
      return 2;                 // non-studio (live/compilation)
    }

    final ra = nsRank(a['nonStudio']);
    final rb = nsRank(b['nonStudio']);
    final c0 = ra.compareTo(rb);
    if (c0 != 0) return c0;

    final ya = (a['year'] as int?) ?? 9999;
    final yb = (b['year'] as int?) ?? 9999;
    final c1 = ya.compareTo(yb);
    if (c1 != 0) return c1;

    final sa = (a['score'] as int?) ?? 0;
    final sb = (b['score'] as int?) ?? 0;
    final c2 = sb.compareTo(sa);
    if (c2 != 0) return c2;

    final ta = (a['title'] ?? '').toString().toLowerCase();
    final tb = (b['title'] ?? '').toString().toLowerCase();
    return ta.compareTo(tb);
  });

  if (tmp.isEmpty) return <AlbumItem>[];
  final ranked = tmp;
  final out = <AlbumItem>[];
  for (final m in ranked) {
    final id = (m['id'] ?? '').toString();
    final title = (m['title'] ?? '').toString();
    final y = (m['year'] as int?) ?? 9999;
    out.add(
      AlbumItem(
        releaseGroupId: id,
        title: title,
        year: y == 9999 ? null : y.toString().padLeft(4, '0'),
        cover250: 'https://coverartarchive.org/release-group/$id/front-250',
        cover500: 'https://coverartarchive.org/release-group/$id/front-500',
      ),
    );
  }


  if (out.length > maxAlbums) return out.take(maxAlbums).toList();
  return out;
}

  /// Resuelve release-groups (preferentemente "Album") para un recording id.
  ///
  /// Esto es más preciso que buscar por texto cuando el usuario selecciona
  /// una opción del dropdown.
  static Future<Set<String>> getAlbumReleaseGroupsForRecordingId({
    required String recordingId,
  }) async {
    final rid = recordingId.trim();
    if (rid.isEmpty) return <String>{};

    try {
      final u = Uri.parse('$_mbBase/recording/$rid?inc=releases+release-groups&fmt=json');
      final rr = await _get(u);
      if (rr.statusCode != 200) return <String>{};
      final d = jsonDecode(rr.body);
      final releases = (d is Map ? (d['releases'] as List?) : null) ?? [];
      final out = <String>{};
      for (final rel in releases) {
        if (rel is! Map) continue;
        final rg = rel['release-group'];
        if (rg is Map) {
          final id = (rg['id'] ?? '').toString().trim();
          final pt = (rg['primary-type'] ?? '').toString().trim();
          if (id.isNotEmpty && (pt.isEmpty || pt.toLowerCase() == 'album')) {
            if (_isNonStudioReleaseGroup(rg)) continue;
            out.add(id);
          }
        } else if (rg is String) {
          final id = rg.trim();
          if (id.isNotEmpty) out.add(id);
        }
      }
      return out;
    } catch (_) {
      return <String>{};
    }
  }

  /// Devuelve IDs de release-groups (álbumes) donde aparece una canción.
  ///
  /// En UI esto se usa para filtrar la lista de álbumes SIN descargar todos
  /// los tracklists.
  static Future<Set<String>> searchAlbumReleaseGroupsBySong({
    required String artistId,
    required String songQuery,
    int limit = 100,
  }) async {
    final arid = artistId.trim();
    final q = songQuery.trim();
    if (arid.isEmpty || q.isEmpty) return <String>{};

    // Estrategia robusta (evita que el endpoint de búsqueda ignore `inc=`):
    // 1) Buscar recordings (top match) filtrado por artista.
    // 2) Hacer 1 lookup al recording id para obtener releases + release-groups.
    const specialChars = '+-!(){}[]^"~*?:\\/&|';
    String esc(String s) {
      final sb = StringBuffer();
      for (final rune in s.runes) {
        final ch = String.fromCharCode(rune);
        if (specialChars.contains(ch)) sb.write('\\');
        sb.write(ch);
      }
      return sb.toString();
    }

    final tokens = q.split(RegExp(r'\s+')).where((t) => t.trim().isNotEmpty).toList();
    if (tokens.isEmpty) return <String>{};

    late final String recPart;
    if (tokens.length == 1) {
      final term = esc(tokens.first);
      recPart = tokens.first.length >= 3 ? 'recording:${term}*' : 'recording:$term';
    } else {
      final phrase = esc(q);
      final terms = tokens.map(esc).toList();
      recPart = '(recording:"$phrase" OR recording:(${terms.join(' AND ')}))';
    }

    final lucene = '$recPart AND arid:$arid';
    final url = Uri.parse(
      '$_mbBase/recording/?query=${Uri.encodeQueryComponent(lucene)}&fmt=json&limit=$limit',
    );
    final res = await _get(url);
    if (res.statusCode != 200) return <String>{};

    final data = jsonDecode(res.body);
    final recs = (data['recordings'] as List?) ?? [];
    if (recs.isEmpty) return <String>{};

    // Tomamos el mejor match (1er resultado). Para la UI es suficiente.
    final best = recs.first;
    final rid = (best is Map ? (best['id'] ?? '').toString().trim() : '');
    if (rid.isEmpty) return <String>{};

    return getAlbumReleaseGroupsForRecordingId(recordingId: rid);
  }

  /// Variante más robusta: devuelve IDs de release-groups (álbumes) donde aparece
  /// una canción, uniendo resultados de múltiples recordings.
  ///
  /// Problema común: una misma canción puede existir como distintos `recordingId`
  /// (remaster, live, single edit, etc.). Si filtramos solo por 1 recordingId,
  /// a veces la UI no encuentra el track en ningún álbum o solo en algunos.
  ///
  /// Estrategia:
  /// 1) Buscar recordings por (título + artista)
  /// 2) Tomar varios `recordingId` candidatos (incluyendo el preferido si viene)
  /// 3) Hacer lookups (capados) para obtener release-groups y unirlos

static Future<Set<String>> searchAlbumReleaseGroupsBySongRobust({
  required String artistId,
  required String songQuery,
  String? preferredRecordingId,
  int searchLimit = 18,
  int maxLookups = 5,
}) async {
  final arid = artistId.trim();
  final raw = songQuery.trim();
  if (arid.isEmpty || raw.isEmpty) return <String>{};

  // ✅ Plan A/B nuevo (más confiable):
  // Artista -> Discography -> Albums, y verificar la canción dentro del tracklist
  // (preferentemente en CD). Así evitamos que ganen compilados/en vivo.
  final scanAlbums = math.min(260, math.max(140, maxLookups * 30));
  final scanMatches = math.max(25, maxLookups * 6);
  final items = await searchSongAlbumsInArtistAlbumsPreferCd(
    artistId: arid,
    songQuery: raw,
    maxScanAlbums: scanAlbums,
    maxMatches: scanMatches,
  );

  final picked = <String>{};
  for (final it in items) {
    final id = it.releaseGroupId.trim();
    if (id.isNotEmpty) picked.add(id);
  }

  if (picked.isNotEmpty) return picked;

  // Fallback suave: si por algún motivo no pudimos obtener tracklists desde los albums,
  // intentamos el método anterior por recordings.
  final effectiveRecordingSearchLimit = math.max(40, searchLimit);
  final effectiveMaxRecordings = math.max(25, maxLookups * 4);
  final oldItems = await searchSongAlbums(
    artistId: arid,
    songQuery: raw,
    maxAlbums: 16,
    recordingSearchLimit: effectiveRecordingSearchLimit,
    maxRecordings: effectiveMaxRecordings,
    preferredRecordingId: preferredRecordingId,
  );
  for (final it in oldItems) {
    final id = it.releaseGroupId.trim();
    if (id.isNotEmpty) picked.add(id);
  }
  return picked;
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

  static bool _cacheValid(DateTime ts, Duration ttl) {
    return DateTime.now().difference(ts) <= ttl;
  }

  static List<_TagCount> _parseTagCounts(dynamic rawTags) {
    final out = <_TagCount>[];
    final list = (rawTags as List?) ?? const <dynamic>[];
    for (final t in list) {
      if (t is! Map) continue;
      final name = (t['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      if (RegExp(r'\d').hasMatch(name)) continue; // evita "1990s"
      final c = (t['count'] is int)
          ? (t['count'] as int)
          : int.tryParse((t['count'] ?? '').toString()) ?? 0;
      out.add(_TagCount(name, c));
    }
    out.sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  static Future<List<_TagCount>> _fallbackTagsFromReleaseGroups(String artistId) async {
    // Si el artista no tiene tags, intentamos sacarlos desde sus álbumes.
    final url = Uri.parse('$_mbBase/release-group/?artist=$artistId&fmt=json&limit=25');
    final res = await _get(url);
    if (res.statusCode != 200) return const <_TagCount>[];

    dynamic data;
    try {
      data = jsonDecode(res.body);
    } catch (_) {
      return const <_TagCount>[];
    }

    final groups = (data['release-groups'] as List?) ?? const <dynamic>[];
    final ids = <String>[];
    for (final g in groups) {
      if (g is! Map) continue;
      final pt = (g['primary-type'] ?? '').toString().toLowerCase();
      if (pt != 'album') continue;
      final id = (g['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      ids.add(id);
      if (ids.length >= 4) break;
    }
    if (ids.isEmpty) return const <_TagCount>[];

    final score = <String, int>{};
    for (final rgid in ids) {
      final u = Uri.parse('$_mbBase/release-group/$rgid?inc=tags&fmt=json');
      final r = await _get(u);
      if (r.statusCode != 200) continue;
      dynamic j;
      try {
        j = jsonDecode(r.body);
      } catch (_) {
        continue;
      }
      final tags = _parseTagCounts(j['tags']);
      for (final tg in tags.take(8)) {
        // suma suave (si hay varios álbumes, se refuerzan)
        score[tg.name] = (score[tg.name] ?? 0) + (tg.count <= 0 ? 1 : tg.count);
      }
    }

    final out = score.entries
        .map((e) => _TagCount(e.key, e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  static Future<List<_TagCount>> _getArtistTagsWithFallback(String artistId) async {
    final cached = _artistTagsCache[artistId];
    if (cached != null && _cacheValid(cached.ts, _similarTtl)) {
      return cached.value;
    }

    // 1) tags directos del artista
    final infoUrl = Uri.parse('$_mbBase/artist/$artistId?inc=tags&fmt=json');
    final infoRes = await _get(infoUrl);
    List<_TagCount> tags = const <_TagCount>[];
    if (infoRes.statusCode == 200) {
      try {
        final data = jsonDecode(infoRes.body);
        tags = _parseTagCounts(data['tags']);
      } catch (_) {
        tags = const <_TagCount>[];
      }
    }

    // 2) fallback: tags desde release-groups
    if (tags.isEmpty) {
      tags = await _fallbackTagsFromReleaseGroups(artistId);
    }

    // Evitar cachear vacíos (permite reintentar si fue un fallo temporal).
    if (tags.isNotEmpty) {
      _artistTagsCache[artistId] = _CacheEntry(tags, DateTime.now());
    }
    return tags;
  }

  // ============================================
  // ✨ ARTISTAS SIMILARES (por tags de MusicBrainz)
  // ============================================
  /// Aproximación "sin API keys":
  /// 1) toma los tags principales del artista (ej: progressive rock, art rock)
  /// 2) busca otros artistas con esos tags
  /// 3) combina resultados y rankea
  static Future<List<SimilarArtistHit>> getSimilarArtistsByArtistId(
    String artistId, {
    int limit = 20,
    int tagLimit = 2,
    int perTag = 12,
  }) async {
    final id = artistId.trim();
    if (id.isEmpty) return <SimilarArtistHit>[];

    final cacheKey = '$id|$limit|$tagLimit|$perTag';
    final cached = _similarCache[cacheKey];
    if (cached != null && _cacheValid(cached.ts, _similarTtl)) {
      return cached.value;
    }

    // 1) Tags del artista (con fallback desde release-groups)
    final tags = await _getArtistTagsWithFallback(id);
    if (tags.isEmpty) return <SimilarArtistHit>[];

    // Filtra tags ultra genéricos si hay alternativas.
    const broad = <String>{
      'rock',
      'pop',
      'electronic',
      'metal',
      'jazz',
      'classical',
      'hip hop',
      'rap',
      'folk',
      'punk',
      'indie',
    };

    final filtered = tags.where((t) => !broad.contains(t.name.toLowerCase())).toList();
    final safeTagLimit = math.max(1, tagLimit);
    final picked = (filtered.isNotEmpty ? filtered : tags).take(safeTagLimit).toList();

    // 2) Buscar artistas por tag y combinar
    final Map<String, _SimilarAgg> agg = <String, _SimilarAgg>{};

    for (final tg in picked) {
      final tagTerm = tg.name.contains(' ')
          ? 'tag:"${_escLucene(tg.name)}"'
          : 'tag:${_escLucene(tg.name)}';

      final url = Uri.parse(
        '$_mbBase/artist/?query=${Uri.encodeQueryComponent(tagTerm)}&fmt=json&limit=$perTag',
      );
      final res = await _get(url);
      if (res.statusCode != 200) continue;

      dynamic d;
      try {
        d = jsonDecode(res.body);
      } catch (_) {
        continue;
      }
      final artists = (d['artists'] as List?) ?? const <dynamic>[];

      // Peso del tag: suavizado por raíz para que no domine un tag con count gigante.
      final tagWeight = tg.count <= 0 ? 1.0 : math.sqrt(tg.count.toDouble());

      for (final a in artists) {
        if (a is! Map) continue;
        final aid = (a['id'] ?? '').toString().trim();
        if (aid.isEmpty) continue;
        if (aid == id) continue;

        final name = (a['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        final country = (a['country'] ?? '').toString().trim();
        final mbScoreNum = (a['score'] is num) ? (a['score'] as num).toDouble() : double.tryParse((a['score'] ?? '0').toString()) ?? 0.0;
        final base = (mbScoreNum / 100.0).clamp(0.0, 1.0);

        final inc = base * tagWeight;

        final cur = agg[aid];
        if (cur == null) {
          agg[aid] = _SimilarAgg(
            name: name,
            country: country.isEmpty ? null : country,
            score: inc,
            tags: <String>{tg.name},
          );
        } else {
          cur.score += inc;
          cur.tags.add(tg.name);
          if ((cur.country == null || cur.country!.isEmpty) && country.isNotEmpty) {
            cur.country = country;
          }
        }
      }
    }

    if (agg.isEmpty) return <SimilarArtistHit>[];

    final out = agg.entries.map((e) {
      final v = e.value;
      final tagList = v.tags.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return SimilarArtistHit(
        id: e.key,
        name: v.name,
        country: v.country,
        score: v.score,
        tags: tagList,
      );
    }).toList();

    out.sort((a, b) => b.score.compareTo(a.score));
    final clipped = (out.length > limit) ? out.take(limit).toList() : out;
    // No cachear vacíos: así el usuario puede reintentar si fue un fallo temporal.
    if (clipped.isNotEmpty) {
      _similarCache[cacheKey] = _CacheEntry(clipped, DateTime.now());
    }
    return clipped;
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
      '$_mbBase/artist/$artistId?inc=tags+url-rels&fmt=json',
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

    String? bio;
    // 1) Intentar Wikipedia desde relaciones de MusicBrainz (más preciso que buscar por nombre)
    if (res.statusCode == 200) {
      try {
        final data = jsonDecode(res.body);
        final wikiUrl = _pickWikipediaUrlFromRelations(data);
        if (wikiUrl != null) {
          bio = await _fetchWikipediaSummaryFromUrl(wikiUrl);
        }
      } catch (_) {}
    }
    // 2) Fallback: búsqueda por nombre (puede devolver cosas que no son música)
    bio ??= (name == null ? null : await _fetchWikipediaBioES(name));
    // 3) Filtro anti-basura: si no parece reseña musical, la descartamos
    if (bio != null && name != null && !_isRelevantMusicBio(bio!, name)) {
      bio = null;
    }

    return ArtistInfo(
      country: country,
      genres: genres,
      bio: bio,
    );
  }

  // =====================================
  // 📀 DISCOGRAFÍA (ORDENADA POR AÑO)
  // =====================================
  /// Obtiene UNA página de discografía desde MusicBrainz.
  ///
  /// Esto evita tener que descargar 1000+ releases para mostrar algo:
  /// la UI puede cargar la primera página y luego pedir más páginas bajo
  /// demanda (por ejemplo, al buscar un álbum específico).
  static Future<DiscographyPage> getDiscographyPageByArtistId(
    String artistId, {
    int limit = 100,
    int offset = 0,
  }) async {
    final url = Uri.parse(
      '$_mbBase/release-group/?artist=$artistId&fmt=json&limit=$limit&offset=$offset',
    );
    final res = await _get(url);
    if (res.statusCode != 200) {
      throw Exception('MusicBrainz ${res.statusCode}');
    }

    final data = jsonDecode(res.body);
    final groups = (data['release-groups'] as List?) ?? [];

    final items = <AlbumItem>[];
    for (final g in groups) {
      if (g is! Map) continue;
      final id = (g['id'] ?? '').toString();
      if (id.trim().isEmpty) continue;
      final title = (g['title'] ?? '').toString();
      final date = (g['first-release-date'] ?? '').toString();
      final year = date.length >= 4 ? date.substring(0, 4) : null;

      final pt = (g['primary-type'] ?? g['primaryType'] ?? '').toString();
      final secsRaw = g['secondary-types'] ?? g['secondaryTypes'];
      final secondary = <String>[];
      if (secsRaw is List) {
        for (final s in secsRaw) {
          final ss = s?.toString().trim();
          if (ss != null && ss.isNotEmpty) secondary.add(ss);
        }
      }

      items.add(
        AlbumItem(
          releaseGroupId: id,
          title: title,
          year: year,
          primaryType: pt,
          secondaryTypes: secondary,
          cover250: 'https://coverartarchive.org/release-group/$id/front-250',
          cover500: 'https://coverartarchive.org/release-group/$id/front-500',
        ),
      );
    }

    final total = (data['count'] is int)
        ? (data['count'] as int)
        : (offset + groups.length);

    return DiscographyPage(
      items: items,
      total: total,
      offset: offset,
      limit: limit,
    );
  }

  static Future<List<AlbumItem>> getDiscographyByArtistId(
    String artistId,
  ) async {
    // Legacy (modo "traer todo"). Se mantiene para filtros que necesitan
    // recorrer todo. Para UI, preferir getDiscographyPageByArtistId.
    const limit = 100;
    final albums = <AlbumItem>[];
    int offset = 0;
    int safetyPages = 0;

    while (true) {
      safetyPages++;
      if (safetyPages > 30) break; // 30*100 = 3000 release-groups
      final page = await getDiscographyPageByArtistId(
        artistId,
        limit: limit,
        offset: offset,
      );
      if (page.items.isEmpty) break;
      albums.addAll(page.items);
      offset += limit;
      if (!page.hasMore) break;
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

    final releaseId = _pickBestReleaseIdFromReleases(releases);
    if (releaseId.isEmpty) return [];

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

  // =========================
  // 💿 EDICIONES (RELEASES) DE UN ÁLBUM
  // =========================
  /// Devuelve una lista de ediciones (releases) asociadas a un release-group.
  ///
  /// IMPORTANTE: no se usa para "año" (eso se toma del release-group), sino para
  /// permitir elegir una edición específica como fallback de carátula (release).
  static Future<List<ReleaseEdition>> getEditionsFromReleaseGroup(String rgid) async {
    final id = rgid.trim();
    if (id.isEmpty) return [];

    final urlRg = Uri.parse(
      '$_mbBase/release-group/$id?inc=releases&fmt=json',
    );
    final resRg = await _get(urlRg);
    if (resRg.statusCode != 200) return [];

    final data = jsonDecode(resRg.body) as Map<String, dynamic>;
    final releases = (data['releases'] as List?) ?? [];
    if (releases.isEmpty) return [];

    final out = <ReleaseEdition>[];
    for (final r in releases) {
      if (r is! Map) continue;
      final rid = (r['id'] ?? '').toString().trim();
      final title = (r['title'] ?? '').toString().trim();
      if (rid.isEmpty) continue;

      final date = (r['date'] ?? '').toString().trim();
      final country = (r['country'] ?? '').toString().trim();
      final status = (r['status'] ?? '').toString().trim();
      final barcode = (r['barcode'] ?? '').toString().trim();

      out.add(
        ReleaseEdition(
          id: rid,
          title: title.isEmpty ? '(sin título)' : title,
          date: date.isEmpty ? null : date,
          country: country.isEmpty ? null : country,
          status: status.isEmpty ? null : status,
          barcode: barcode.isEmpty ? null : barcode,
        ),
      );
    }

    // Orden por fecha (más antigua primero) y luego por título.
    out.sort((a, b) {
      final ay = int.tryParse(a.year ?? '') ?? 9999;
      final by = int.tryParse(b.year ?? '') ?? 9999;
      final c = ay.compareTo(by);
      if (c != 0) return c;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    // Limitar para que el UI no explote con artistas/álbumes con cientos de ediciones.
    return out.take(120).toList();
  }

  /// Versión más robusta: intenta más de un release dentro del release-group.
  /// Algunas veces el 1er release no trae recordings (o viene incompleto),
  /// lo que hacía que el filtro de canciones no encontrara nada.
  static Future<List<String>> getTrackTitlesFromReleaseGroupRobust(
    String rgid, {
    int maxReleaseLookups = 3,
  }) async {
    final urlRg = Uri.parse(
      '$_mbBase/release-group/$rgid?inc=releases&fmt=json',
    );
    final resRg = await _get(urlRg);
    if (resRg.statusCode != 200) return <String>[];

    final releases = (jsonDecode(resRg.body)['releases'] as List?) ?? [];
    if (releases.isEmpty) return <String>[];

    // Probamos primero releases Official + más antiguos (mejor para tracklists completos).
    final rels = releases.whereType<Map>().toList();
    rels.sort((a, b) {
      final sa = (a['status'] ?? '').toString().trim().toLowerCase();
      final sb = (b['status'] ?? '').toString().trim().toLowerCase();
      final oa = sa.isEmpty || sa == 'official';
      final ob = sb.isEmpty || sb == 'official';
      if (oa != ob) return oa ? -1 : 1;
      final da = _parseMbDate(a['date']);
      final db = _parseMbDate(b['date']);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });

    int tried = 0;
    for (final r in rels) {
      final releaseId = (r is Map ? (r['id'] ?? '').toString().trim() : '');
      if (releaseId.isEmpty) continue;

      final urlRel = Uri.parse(
        '$_mbBase/release/$releaseId?inc=recordings&fmt=json',
      );
      final resRel = await _get(urlRel);
      if (resRel.statusCode != 200) {
        tried++;
        if (tried >= maxReleaseLookups) break;
        continue;
      }

      final media = (jsonDecode(resRel.body)['media'] as List?) ?? [];
      if (media.isEmpty) {
        tried++;
        if (tried >= maxReleaseLookups) break;
        continue;
      }

      final titles = <String>[];
      for (final m in media) {
        for (final t in (m is Map ? (m['tracks'] as List? ?? const []) : const <dynamic>[])) {
          if (t is! Map) continue;
          final title = (t['title'] ?? '').toString().trim();
          if (title.isNotEmpty) titles.add(title);
        }
      }

      if (titles.isNotEmpty) return titles;

      tried++;
      if (tried >= maxReleaseLookups) break;
    }

    return <String>[];
  }

  // ================================
  // 🎵 TRACKLIST (PRIMERA EDICIÓN)
  // ================================
  /// Devuelve títulos de tracklist usando la **primera edición** (release más
  /// antigua y oficial) de un release-group.
  ///
  /// Esto es clave para el filtro de canciones: evita falsos positivos por
  /// reediciones/deluxe que agregan bonus tracks.
  static Future<List<String>> getTrackTitlesFromReleaseGroupFirstEdition(
    String rgid, {
    int maxReleaseLookups = 6,
  }) async {
    final id = rgid.trim();
    if (id.isEmpty) return <String>[];

    // Cache con TTL
    final cached = _firstEditionTracksCache[id];
    if (cached != null && DateTime.now().difference(cached.ts) < _tracksTtl) {
      return cached.value;
    }

    final urlRg = Uri.parse('$_mbBase/release-group/$id?inc=releases&fmt=json');
    final resRg = await _get(urlRg);
    if (resRg.statusCode != 200) {
      _firstEditionTracksCache[id] = _CacheEntry(<String>[], DateTime.now());
      return <String>[];
    }

    final data = jsonDecode(resRg.body);
    final releases = (data is Map ? (data['releases'] as List?) : null) ?? const <dynamic>[];
    if (releases.isEmpty) {
      _firstEditionTracksCache[id] = _CacheEntry(<String>[], DateTime.now());
      return <String>[];
    }

    // Orden: Official primero, luego por fecha más antigua.
    int yearOf(dynamic v) {
      final s = (v ?? '').toString().trim();
      if (s.length >= 4) return int.tryParse(s.substring(0, 4)) ?? 9999;
      return 9999;
    }

    int statusRank(dynamic v) {
      final s = (v ?? '').toString().trim().toLowerCase();
      if (s.isEmpty || s == 'official') return 0;
      // Bootleg/Other -> atrás
      if (s == 'bootleg') return 3;
      return 1;
    }

    final rels = <Map<String, dynamic>>[];
    for (final r in releases) {
      if (r is! Map) continue;
      final rid = (r['id'] ?? '').toString().trim();
      if (rid.isEmpty) continue;
      rels.add(Map<String, dynamic>.from(r));
    }
    if (rels.isEmpty) {
      _firstEditionTracksCache[id] = _CacheEntry(<String>[], DateTime.now());
      return <String>[];
    }

    rels.sort((a, b) {
      final sr = statusRank(a['status']).compareTo(statusRank(b['status']));
      if (sr != 0) return sr;
      final ya = yearOf(a['date']);
      final yb = yearOf(b['date']);
      final yc = ya.compareTo(yb);
      if (yc != 0) return yc;
      // desempate: título
      return ((a['title'] ?? '').toString()).toLowerCase().compareTo(((b['title'] ?? '').toString()).toLowerCase());
    });

    int tried = 0;
    for (final r in rels) {
      final rid = (r['id'] ?? '').toString().trim();
      if (rid.isEmpty) continue;
      final urlRel = Uri.parse('$_mbBase/release/$rid?inc=recordings&fmt=json');
      final resRel = await _get(urlRel);
      tried++;
      if (resRel.statusCode != 200) {
        if (tried >= maxReleaseLookups) break;
        continue;
      }

      final relData = jsonDecode(resRel.body);
      final media = (relData is Map ? (relData['media'] as List?) : null) ?? const <dynamic>[];
      if (media.isEmpty) {
        if (tried >= maxReleaseLookups) break;
        continue;
      }

      final titles = <String>[];
      for (final m in media) {
        final tracks = (m is Map ? (m['tracks'] as List?) : null) ?? const <dynamic>[];
        for (final t in tracks) {
          if (t is! Map) continue;
          final title = (t['title'] ?? '').toString().trim();
          if (title.isNotEmpty) titles.add(title);
        }
      }

      if (titles.isNotEmpty) {
        _firstEditionTracksCache[id] = _CacheEntry(titles, DateTime.now());
        return titles;
      }

      if (tried >= maxReleaseLookups) break;
    }

    _firstEditionTracksCache[id] = _CacheEntry(<String>[], DateTime.now());
    return <String>[];
  }

  static bool _titleMatchesSong({
    required String trackTitle,
    required String songTitle,
  }) {
    final t = normalizeKey(trackTitle);
    final s = normalizeKey(songTitle);
    if (t.isEmpty || s.isEmpty) return false;
    if (t == s) return true;

    // Si el título es largo, permitimos contains (para variantes tipo "(Remastered)").
    if (s.length >= 6) return t.contains(s);

    // Para títulos cortos ("One", "..."), evitamos falsos positivos por substring.
    if (!s.contains(' ')) {
      return t.split(' ').contains(s);
    }
    return t.contains(s);
  }

  static DateTime? _parseMbDate(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return null;
    final parts = s.split('-');
    final y = int.tryParse(parts[0]);
    if (y == null || y <= 0) return null;
    var m = 1;
    var d = 1;
    if (parts.length >= 2) {
      final mm = int.tryParse(parts[1]);
      if (mm != null && mm >= 1 && mm <= 12) m = mm;
    }
    if (parts.length >= 3) {
      final dd = int.tryParse(parts[2]);
      if (dd != null && dd >= 1 && dd <= 31) d = dd;
    }
    // DateTime throws on invalid dates like 2020-02-31.
    try {
      return DateTime(y, m, d);
    } catch (_) {
      try {
        return DateTime(y, m, 1);
      } catch (_) {
        return DateTime(y, 1, 1);
      }
    }
  }

  static bool _isCompilationReleaseGroup(dynamic rg) {
    if (rg is! Map) return false;
    final sec = (rg['secondary-types'] as List?) ?? const <dynamic>[];
    for (final t in sec) {
      final v = (t ?? '').toString().trim().toLowerCase();
      if (v == 'compilation') return true;
    }
    return false;
  }

  static bool _isLiveReleaseGroup(dynamic rg) {
    if (rg is! Map) return false;
    final sec = (rg['secondary-types'] as List?) ?? const <dynamic>[];
    for (final t in sec) {
      final v = (t ?? '').toString().trim().toLowerCase();
      if (v == 'live') return true;
    }
    return false;
  }

  /// Release-groups que NO queremos considerar como "disco de lanzamiento".
  ///
  /// Para el filtro de canciones, el usuario normalmente quiere el álbum de estudio.
  /// Un recording puede existir como live/remaster/etc. Para evitar caer en "Live" (ej.
  /// *Gira Me Verás Volver*), descartamos release-groups con secondary-types Live.
  static bool _isNonStudioReleaseGroup(dynamic rg) {
    return _isCompilationReleaseGroup(rg) || _isLiveReleaseGroup(rg);
  }

  /// Para un recording, devuelve release-groups tipo "Album" ordenados por
  /// fecha de primera aparición (más antiguo primero). Filtra releases
  /// no-oficiales cuando `status` está disponible.
  static Future<List<Map<String, dynamic>>> _albumReleaseGroupsByFirstDateForRecording(
    String recordingId,
  ) async {
    final rid = recordingId.trim();
    if (rid.isEmpty) return const <Map<String, dynamic>>[];

    try {
      final u = Uri.parse('$_mbBase/recording/$rid?inc=releases+release-groups&fmt=json');
      final rr = await _get(u);
      if (rr.statusCode != 200) return const <Map<String, dynamic>>[];
      final d = jsonDecode(rr.body);
      final releases = (d is Map ? (d['releases'] as List?) : null) ?? const <dynamic>[];

      // rgId -> {title, dt}
      final Map<String, Map<String, dynamic>> best = {};
      for (final rel in releases) {
        if (rel is! Map) continue;
        final status = (rel['status'] ?? '').toString().trim();
        if (status.isNotEmpty && status.toLowerCase() != 'official') continue;

        final rg = rel['release-group'];
        if (rg is! Map) continue;
        final id = (rg['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;

        final pt = (rg['primary-type'] ?? '').toString().trim().toLowerCase();
        if (pt.isNotEmpty && pt != 'album') continue;
        if (_isNonStudioReleaseGroup(rg)) continue;

        final title = (rg['title'] ?? '').toString().trim();
        final dt = _parseMbDate(rg['first-release-date']) ?? _parseMbDate(rel['date']);

        final cur = best[id];
        if (cur == null) {
          best[id] = {
            'id': id,
            'title': title,
            'dt': dt,
            'year': (rg['first-release-date'] ?? '').toString().trim(),
          };
        } else {
          final curDt = cur['dt'] as DateTime?;
          // Guardamos la fecha más antigua disponible.
          if (curDt == null || (dt != null && dt.isBefore(curDt))) {
            cur['dt'] = dt;
          }
          // Conservamos título si antes estaba vacío.
          if (((cur['title'] ?? '').toString().trim()).isEmpty && title.isNotEmpty) {
            cur['title'] = title;
          }
        }
      }

      final out = best.values.toList();
      out.sort((a, b) {
        final ad = a['dt'] as DateTime?;
        final bd = b['dt'] as DateTime?;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        final c = ad.compareTo(bd);
        if (c != 0) return c;
        return (a['title'] ?? '').toString().toLowerCase().compareTo((b['title'] ?? '').toString().toLowerCase());
      });
      return out;
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  static Future<bool> _releaseGroupBelongsToArtist({
    required String releaseGroupId,
    required String artistId,
  }) async {
    final rgid = releaseGroupId.trim();
    final arid = artistId.trim();
    if (rgid.isEmpty || arid.isEmpty) return false;

    final key = '$arid||$rgid';
    final cached = _rgHasArtistCache[key];
    if (cached != null && DateTime.now().difference(cached.ts) < _tracksTtl) {
      return cached.value;
    }

    try {
      final u = Uri.parse('$_mbBase/release-group/$rgid?fmt=json');
      final r = await _get(u);
      if (r.statusCode != 200) {
        _rgHasArtistCache[key] = _CacheEntry(false, DateTime.now());
        return false;
      }
      final j = jsonDecode(r.body);
      final ac = (j is Map ? (j['artist-credit'] as List?) : null) ?? const <dynamic>[];
      bool ok = false;
      for (final it in ac) {
        if (it is! Map) continue;
        final a = it['artist'];
        final id = (a is Map ? (a['id'] ?? '') : '').toString().trim();
        if (id == arid) {
          ok = true;
          break;
        }
      }
      _rgHasArtistCache[key] = _CacheEntry(ok, DateTime.now());
      return ok;
    } catch (_) {
      _rgHasArtistCache[key] = _CacheEntry(false, DateTime.now());
      return false;
    }
  }

  /// Intenta determinar si un artist-credit incluye al artista elegido.
  /// Devuelve:
  /// - true  : podemos confirmar que está
  /// - false : podemos confirmar que NO está
  /// - null  : no hay datos suficientes
  static bool? _artistCreditIncludes(dynamic artistCredit, String artistId) {
    final arid = artistId.trim();
    if (arid.isEmpty) return null;
    if (artistCredit == null) return null;

    if (artistCredit is List) {
      bool sawAny = false;
      for (final it in artistCredit) {
        if (it is! Map) continue;
        sawAny = true;
        final a = it['artist'];
        final id = (a is Map ? (a['id'] ?? '') : '').toString().trim();
        if (id.isEmpty) continue;
        if (id == arid) return true;
      }
      return sawAny ? false : null;
    }

    if (artistCredit is Map) {
      // Algunos endpoints devuelven 'artist-credit' como objeto.
      final a = artistCredit['artist'];
      final id = (a is Map ? (a['id'] ?? '') : '').toString().trim();
      if (id.isEmpty) return null;
      return id == arid;
    }

    return null;
  }

  /// Devuelve álbumes (release-groups) donde aparece un recording.
  ///
  /// ✅ En móvil, el filtro de canciones debe ser rápido y confiable.
  /// Para evitar falsos "no hay nada" (por tracklists incompletos o rate-limit),
  /// aquí **no** bloqueamos el resultado con verificaciones costosas.
  ///
  /// Estrategia (Plan A/B):
  /// 1) Usa la relación directa recording → releases → release-groups.
  /// 2) Filtra a primary-type=Album, evita Compilation.
  /// 3) Prefiere releases Official si existen.
  /// 4) Elige el(los) álbum(es) más tempranos ("donde fue lanzada").
  ///
  /// Si este método devuelve vacío, la UI puede aplicar su "Plan Z" (escaneo local)
  /// como último salvavidas.
  static Future<List<AlbumItem>> albumsForRecordingFirstEditionVerified({
    required String artistId,
    required String recordingId,
    required String songTitle,
    int maxAlbums = 8,
  }) async {
    final rid = recordingId.trim();
    final arid = artistId.trim();
    if (rid.isEmpty || arid.isEmpty) return <AlbumItem>[];

    // Pedimos releases + release-groups. Esto es suficiente para identificar
    // el álbum (release-group) donde aparece el recording.
    final lookupUrl = Uri.parse('$_mbBase/recording/$rid?inc=releases+release-groups&fmt=json');
    final rr = await _get(lookupUrl);
    if (rr.statusCode != 200) return <AlbumItem>[];

    dynamic d;
    try {
      d = jsonDecode(rr.body);
    } catch (_) {
      return <AlbumItem>[];
    }


    final releases = (d is Map ? (d['releases'] as List?) : null) ?? const <dynamic>[];
    final Map<String, _RgCandidate> candidates = {};

    String? yearFromDateOrString(DateTime? dt, dynamic raw) {
      if (dt != null) return dt.year.toString().padLeft(4, '0');
      final s = (raw ?? '').toString().trim();
      if (s.length >= 4) return s.substring(0, 4);
      return null;
    }

    for (final rel in releases) {
      if (rel is! Map) continue;

      final rg = rel['release-group'];
      if (rg is! Map) continue;

      final pt = (rg['primary-type'] ?? '').toString().trim().toLowerCase();
      if (pt.isNotEmpty && pt != 'album') continue;

      // Evita compilations (grandes éxitos, VA, etc.). El usuario quiere el álbum
      // "donde fue lanzada" la canción, no apariciones tardías.
      if (_isNonStudioReleaseGroup(rg)) continue;

      final id = (rg['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;

      final status = (rel['status'] ?? '').toString().trim().toLowerCase();
      final isOfficial = status == 'official';

      final title = (rg['title'] ?? '').toString().trim();
      final dt = _parseMbDate(rg['first-release-date']) ?? _parseMbDate(rel['date']);
      final y = yearFromDateOrString(dt, rg['first-release-date']);

      final cur = candidates[id];
      if (cur == null) {
        candidates[id] = _RgCandidate(
          id: id,
          title: title,
          year: y,
          earliest: dt,
          hasOfficial: isOfficial,
        );
        continue;
      }

      // Mantén la fecha más temprana por release-group.
      if (cur.earliest == null || (dt != null && dt.isBefore(cur.earliest!))) {
        cur.earliest = dt;
      }
      // Si llega una versión con status Official, preferimos esa condición.
      if (isOfficial) cur.hasOfficial = true;

      // Completa año/título si están vacíos.
      if ((cur.title).trim().isEmpty && title.trim().isNotEmpty) cur.title = title;
      if ((cur.year ?? '').isEmpty && (y ?? '').isNotEmpty) cur.year = y;
    }

    if (candidates.isEmpty) {
      // ⚠️ Caso común: el recording seleccionado por el autocomplete puede ser una
      // versión en vivo. Ese recording a veces NO está asociado al álbum de estudio
      // original (por eso aquí quedaría vacío). Para evitar caer al "Plan Z" de la UI,
      // hacemos una resolución robusta por texto (múltiples recordings) y devolvemos
      // el/los álbum(es) de estudio más antiguos.
      try {
        final robust = await searchSongAlbums(
          artistId: arid,
          songQuery: songTitle,
          maxAlbums: maxAlbums,
          recordingSearchLimit: 20,
          maxRecordings: 8,
          preferredRecordingId: rid,
        );
        if (robust.isEmpty) return <AlbumItem>[];

        // searchSongAlbums devuelve ordenados por año; nos quedamos con el más antiguo.
        final firstYear = int.tryParse(robust.first.year ?? '') ?? 9999;
        final out = <AlbumItem>[];
        for (final it in robust) {
          final y = int.tryParse(it.year ?? '') ?? 9999;
          if (firstYear != 9999 && y != firstYear) break;
          out.add(it);
          if (out.length >= maxAlbums) break;
        }
        return out.isEmpty ? <AlbumItem>[] : out;
      } catch (_) {
        return <AlbumItem>[];
      }
    }

    // Preferimos candidates con al menos un release Official, si existen.
    final all = candidates.values.toList();
    final anyOfficial = all.any((c) => c.hasOfficial);
    final filtered = anyOfficial ? all.where((c) => c.hasOfficial).toList() : all;

    // Orden: más antiguo primero. Null al final.
    filtered.sort((a, b) {
      final adt = a.earliest ?? DateTime(9999, 12, 31);
      final bdt = b.earliest ?? DateTime(9999, 12, 31);
      final c = adt.compareTo(bdt);
      if (c != 0) return c;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    // "Disco donde fue lanzada": nos quedamos con el/los más temprano(s).
    final firstDt = filtered.first.earliest;
    final picked = <_RgCandidate>[];

    if (firstDt != null) {
      for (final c in filtered) {
        if (c.earliest == null) continue;
        if (!c.earliest!.isAtSameMomentAs(firstDt)) break;
        picked.add(c);
        if (picked.length >= maxAlbums) break;
      }
    } else {
      // Si no hay fechas, devolvemos los primeros maxAlbums ordenados por título.
      picked.addAll(filtered.take(maxAlbums));
    }

    // Filtro "suave" por artista: si algún candidato pertenece al artista,
    // preferimos esos. Si ninguno pasa, devolvemos igual los elegidos.
    final preferred = <_RgCandidate>[];
    for (final c in picked) {
      try {
        final ok = await _releaseGroupBelongsToArtist(releaseGroupId: c.id, artistId: arid);
        if (ok) preferred.add(c);
      } catch (_) {}
    }
    final finalList = preferred.isNotEmpty ? preferred : picked;

    return finalList.map((c) => c.toAlbumItem()).toList();
  }

  static String? _fmtMs(dynamic ms) {
    if (ms == null) return null;
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  
// =====================================
// 🧠 SELECCIÓN DE WIKIPEDIA + FILTRO
// =====================================
  static String? _pickWikipediaUrlFromRelations(dynamic data) {
    final rels = (data['relations'] as List?) ?? [];
    String? esUrl;
    String? enUrl;
    String? anyUrl;

    for (final r in rels) {
      final urlObj = r is Map ? r['url'] : null;
      final resource = urlObj is Map ? (urlObj['resource'] ?? '').toString() : '';
      if (resource.isEmpty) continue;

      final type = (r is Map ? (r['type'] ?? '').toString().toLowerCase() : '');
      final isWiki = type == 'wikipedia' || resource.contains('wikipedia.org/wiki/');
      if (!isWiki) continue;

      anyUrl ??= resource;
      if (resource.contains('es.wikipedia.org')) esUrl ??= resource;
      if (resource.contains('en.wikipedia.org')) enUrl ??= resource;
    }

    // Preferimos ES, luego EN, luego cualquiera
    return esUrl ?? enUrl ?? anyUrl;
  }

  static Future<String?> _fetchWikipediaSummaryFromUrl(String wikiUrl) async {
    try {
      final uri = Uri.parse(wikiUrl);
      final host = uri.host; // ej: en.wikipedia.org
      if (!host.contains('wikipedia.org')) return null;

      // Ruta típica: /wiki/Titulo
      if (uri.pathSegments.isEmpty) return null;
      final titleRaw = uri.pathSegments.last;
      final title = Uri.decodeComponent(titleRaw);

      final sum = Uri.parse(
        'https://$host/api/rest_v1/page/summary/${Uri.encodeComponent(title)}',
      );
      final sumRes = await http.get(sum, headers: _headers()).timeout(const Duration(seconds: 15));
      if (sumRes.statusCode != 200) return null;

      final decoded = jsonDecode(sumRes.body);
      final extract = decoded['extract'];
      if (extract == null) return null;

      final txt = extract.toString().trim();
      return txt.isEmpty ? null : txt;
    } catch (_) {
      return null;
    }
  }

  static bool _isRelevantMusicBio(String text, String artistName) {
    final t = text.toLowerCase();

    // Red flags típicos de texto basura / e-commerce / políticas.
    const bad = [
      'privacy policy',
      'política de privacidad',
      'cookies',
      'cookie policy',
      'terms of service',
      'términos y condiciones',
      'shipping',
      'envío',
      'returns',
      'devoluciones',
      'subscribe',
      'suscríbete',
      'login',
      'iniciar sesión',
      'warranty',
      'garantía',
      'free shipping',
    ];
    for (final b in bad) {
      if (t.contains(b)) return false;
    }

    // Señales musicales (ES + EN).
    const music = [
      'album',
      'álbum',
      'band',
      'banda',
      'musician',
      'músico',
      'singer',
      'cantante',
      'song',
      'canción',
      'record',
      'disco',
      'studio',
      'estudio',
      'debut',
      'track',
      'pista',
      'release',
      'lanzamiento',
      'genre',
      'género',
      'rock',
      'pop',
      'hip hop',
      'metal',
      'jazz',
      'electronic',
      'electrónica',
    ];

    final name = artistName.toLowerCase().trim();
    final mentionsName = name.isNotEmpty && t.contains(name);

    int hits = 0;
    for (final k in music) {
      if (t.contains(k)) hits++;
      if (hits >= 2) break;
    }

    // Aceptamos si menciona al artista o tiene suficientes señales musicales.
    return mentionsName || hits >= 2;
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
        final sRes = await http.get(search, headers: _headers()).timeout(const Duration(seconds: 15));
        if (sRes.statusCode != 200) continue;

        final data = jsonDecode(sRes.body);
        if (data[1].isEmpty) continue;

        final title = data[1][0];
        final sum = Uri.parse(
          'https://$lang.wikipedia.org/api/rest_v1/page/summary/$title',
        );
        final sumRes = await http.get(sum, headers: _headers()).timeout(const Duration(seconds: 15));
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