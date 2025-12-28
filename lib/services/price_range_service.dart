import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/normalize.dart';

class PriceRange {
  final double min;
  final double max;
  final String currency; // e.g. EUR, USD
  /// Timestamp (ms) when this price was fetched.
  final int fetchedAtMs;

  PriceRange({required this.min, required this.max, required this.currency, required this.fetchedAtMs});

  DateTime get fetchedAt => DateTime.fromMillisecondsSinceEpoch(fetchedAtMs);

  Map<String, dynamic> toJson() => {
        'min': min,
        'max': max,
        'currency': currency,
        'ts': fetchedAtMs,
      };

  static PriceRange? fromJson(Map<String, dynamic> m) {
    final min = (m['min'] as num?)?.toDouble();
    final max = (m['max'] as num?)?.toDouble();
    final currency = (m['currency'] as String?)?.trim();
    final ts = (m['ts'] as num?)?.toInt();
    if (min == null || max == null || currency == null || currency.isEmpty) {
      return null;
    }
    return PriceRange(
      min: min,
      max: max,
      currency: currency,
      fetchedAtMs: (ts != null && ts > 0) ? ts : DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Estimación de rango de precios (mín–máx) para un álbum.
///
/// Antes se intentaba “scrapear” Discogs (HTML), pero Discogs suele devolver 403
/// o contenido dinámico que no viene en el HTML, así que falla seguido.
///
/// Nuevo enfoque (más estable):
/// 1) si tenemos MBID (release-group), intentamos mapear a Discogs release_id
///    usando relaciones de MusicBrainz (url-rels).
/// 2) con ese release_id consultamos el endpoint oficial:
///    /marketplace/stats/{release_id}?curr_abbr=EUR
/// 3) si no se puede, hacemos un fallback best-effort (scraping antiguo).
class PriceRangeService {
  static const _prefsPrefix = 'price_range::';
  static const _ttlOk = Duration(days: 14);
  static const _ttlNull = Duration(hours: 12);

  static const _mbBase = 'https://musicbrainz.org/ws/2';
  static DateTime _lastMbCall = DateTime.fromMillisecondsSinceEpoch(0);

  static final Map<String, PriceRange?> _memCache = {};

  static String _cacheKey({required String artist, required String album, String? mbid}) {
    final m = (mbid ?? '').trim();
    final base = m.isNotEmpty ? 'mbid:$m' : '${artist.trim()}||${album.trim()}';
    return _prefsPrefix + normalizeKey(base);
  }

  static bool _isFreshTs(int? ts, Duration ttl) {
    if (ts == null || ts <= 0) return false;
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return DateTime.now().difference(dt) <= ttl;
  }

  static Future<void> _throttleMb() async {
    final now = DateTime.now();
    final diff = now.difference(_lastMbCall);
    if (diff.inMilliseconds < 1100) {
      await Future.delayed(Duration(milliseconds: 1100 - diff.inMilliseconds));
    }
    _lastMbCall = DateTime.now();
  }

  static Map<String, String> _mbHeaders() => {
        'User-Agent': 'GaBoLP/1.0 (contact: gabo.hachim@gmail.com)',
        'Accept': 'application/json',
      };

  static Future<http.Response> _mbGet(Uri url) async {
    await _throttleMb();
    return http.get(url, headers: _mbHeaders()).timeout(const Duration(seconds: 15));
  }

  static double? _parseNumber(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(RegExp(r'[^0-9,\.]'), '');
    if (s.isEmpty) return null;

    if (s.contains(',') && s.contains('.')) {
      s = s.replaceAll(',', '');
    } else if (s.contains(',') && !s.contains('.')) {
      s = s.replaceAll(',', '.');
    }
    return double.tryParse(s);
  }

  static String _symbolToCurrency(String s) {
    final t = s.trim();
    if (t == '€') return 'EUR';
    if (t == r'$') return 'USD';
    if (t == '£') return 'GBP';
    if (RegExp(r'^[A-Z]{3}$').hasMatch(t)) return t;
    return 'EUR';
  }

  static Future<PriceRange?> getRange({
    required String artist,
    required String album,
    String? mbid,
    bool forceRefresh = false,
  }) async {
    final a = artist.trim();
    final al = album.trim();
    if (a.isEmpty || al.isEmpty) return null;

    final key = _cacheKey(artist: a, album: al, mbid: mbid);
    if (!forceRefresh && _memCache.containsKey(key)) return _memCache[key];

    if (!forceRefresh) {
      // 1) SharedPrefs cache
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(key);
        if (raw != null && raw.trim().isNotEmpty) {
          final m = jsonDecode(raw) as Map<String, dynamic>;
          final ts = (m['ts'] as num?)?.toInt();

          if (m['null'] == true) {
            if (_isFreshTs(ts, _ttlNull)) {
              _memCache[key] = null;
              return null;
            }
          } else {
            if (_isFreshTs(ts, _ttlOk)) {
              final pr = PriceRange.fromJson(m);
              _memCache[key] = pr;
              return pr;
            }
          }
        }
      } catch (_) {
        // ignore
      }
    }

    PriceRange? pr;

    // 2) Preferimos Discogs API via MBID (si existe)
    final m = (mbid ?? '').trim();
    if (m.isNotEmpty) {
      final discogsReleaseId = await _discogsReleaseIdFromMusicBrainz(m);
      if (discogsReleaseId != null) {
        pr = await _marketStatsFromDiscogsApi(discogsReleaseId);
      }
    }

    // 3) Fallback best-effort: scraping (puede fallar por 403)
    pr ??= await _fetchFromDiscogsHtml(artist: a, album: al);

    // Marca timestamp si vino sin ts (defensivo)
    if (pr != null && pr.fetchedAtMs <= 0) {
      pr = PriceRange(min: pr.min, max: pr.max, currency: pr.currency, fetchedAtMs: DateTime.now().millisecondsSinceEpoch);
    }

    _memCache[key] = pr;

    // 4) Persistimos cache (null con TTL más corto)
    try {
      final prefs = await SharedPreferences.getInstance();
      if (pr != null) {
        await prefs.setString(key, jsonEncode(pr.toJson()));
      } else {
        await prefs.setString(key, jsonEncode({'ts': DateTime.now().millisecondsSinceEpoch, 'null': true}));
      }
    } catch (_) {
      // ignore
    }

    return pr;
  }

  // =============================
  // MusicBrainz -> Discogs release_id
  // =============================

  static Future<String?> _discogsReleaseIdFromMusicBrainz(String rgid) async {
    try {
      final urlRg = Uri.parse('$_mbBase/release-group/$rgid?inc=releases&fmt=json');
      final resRg = await _mbGet(urlRg);
      if (resRg.statusCode != 200) return null;

      final rg = jsonDecode(resRg.body) as Map<String, dynamic>;
      final releases = (rg['releases'] as List?) ?? const [];
      if (releases.isEmpty) return null;

      // Queremos precios enfocados en VINILOS: dentro del release-group, preferimos
      // un release que tenga media.format == "Vinyl" en MusicBrainz y que además
      // tenga relación a un release de Discogs.
      //
      // Nota: MB tiene rate limiting (1 req/s). Tomamos una muestra acotada.
      final candidateIds = <String>[];
      for (final r in releases.take(8)) {
        final id = (r as Map)['id']?.toString();
        if (id != null && id.trim().isNotEmpty) candidateIds.add(id.trim());
      }

      // 1) Intento "vinyl-first": buscar un release MB con media Vinyl, y de ese
      //    mismo release sacar el Discogs release id.
      for (final mbReleaseId in candidateIds) {
        final discogsId = await _discogsReleaseIdFromMbRelease(mbReleaseId, requireVinyl: true);
        if (discogsId != null) return discogsId;
      }

      // 2) Fallback: si no encontramos un MB release marcado como Vinyl, intentamos
      //    igual desde el primero (mejor que nada).
      for (final mbReleaseId in candidateIds) {
        final discogsId = await _discogsReleaseIdFromMbRelease(mbReleaseId, requireVinyl: false);
        if (discogsId != null) return discogsId;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  static bool _mbReleaseHasVinylMedia(Map<String, dynamic> mbRelease) {
    final media = (mbRelease['media'] as List?) ?? const [];
    for (final m in media) {
      final fmt = (m as Map)['format']?.toString().toLowerCase().trim();
      if (fmt == null) continue;
      if (fmt.contains('vinyl')) return true;
    }
    return false;
  }

  /// Dado un MusicBrainz release id, intenta obtener un Discogs release id.
  ///
  /// Si [requireVinyl] es true, solo acepta releases que MB marque como Vinyl.
  static Future<String?> _discogsReleaseIdFromMbRelease(
    String mbReleaseId, {
    required bool requireVinyl,
  }) async {
    try {
      final urlRel = Uri.parse('$_mbBase/release/$mbReleaseId?inc=media+url-rels&fmt=json');
      final resRel = await _mbGet(urlRel);
      if (resRel.statusCode != 200) return null;

      final rel = jsonDecode(resRel.body) as Map<String, dynamic>;
      if (requireVinyl && !_mbReleaseHasVinylMedia(rel)) return null;

      final rels = (rel['relations'] as List?) ?? const [];
      String? masterId;

      for (final r in rels) {
        final url = ((r as Map)['url']?['resource'] ?? '').toString();
        if (url.isEmpty) continue;

        final mRelease = RegExp(r'discogs\.com/(?:[a-z]{2}/)?release/(\d+)', caseSensitive: false).firstMatch(url);
        if (mRelease != null) {
          final rid = mRelease.group(1);
          if (rid != null && rid.isNotEmpty) {
            // Validación best-effort: si podemos confirmar que el release de Discogs
            // es Vinyl, mejor. Si el check falla (timeout/403), no bloqueamos.
            final okVinyl = await _discogsReleaseIsVinylBestEffort(rid);
            if (okVinyl != false) return rid;
          }
        }

        final mMaster = RegExp(r'discogs\.com/(?:[a-z]{2}/)?master/(\d+)', caseSensitive: false).firstMatch(url);
        if (mMaster != null) {
          masterId = mMaster.group(1);
        }
      }

      if (masterId != null) {
        final mainRid = await _discogsMainReleaseFromMaster(masterId);
        if (mainRid != null) {
          final okVinyl = await _discogsReleaseIsVinylBestEffort(mainRid);
          if (okVinyl != false) return mainRid;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static final Map<String, bool?> _discogsVinylCache = {};

  /// Devuelve:
  /// - true  => confirmado que es Vinyl
  /// - false => confirmado que NO es Vinyl
  /// - null  => no se pudo comprobar (network/rate limit). En ese caso no bloqueamos.
  static Future<bool?> _discogsReleaseIsVinylBestEffort(String releaseId) async {
    final rid = releaseId.trim();
    if (rid.isEmpty) return null;
    if (_discogsVinylCache.containsKey(rid)) return _discogsVinylCache[rid];

    final url = Uri.parse('https://api.discogs.com/releases/$rid');
    try {
      final res = await http.get(url, headers: _discogsHeaders()).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        _discogsVinylCache[rid] = null;
        return null;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final formats = (data['formats'] as List?) ?? const [];
      for (final f in formats) {
        final name = (f as Map)['name']?.toString().toLowerCase().trim();
        if (name == null) continue;
        if (name.contains('vinyl')) {
          _discogsVinylCache[rid] = true;
          return true;
        }
      }
      _discogsVinylCache[rid] = false;
      return false;
    } catch (_) {
      _discogsVinylCache[rid] = null;
      return null;
    }
  }

  static Map<String, String> _discogsHeaders() => {
        // Discogs pide User-Agent identificable
        'User-Agent': 'AppVinilos/1.0 (contact: gabo.hachim@gmail.com)',
        'Accept': 'application/json',
      };

  static Future<String?> _discogsMainReleaseFromMaster(String masterId) async {
    final mid = masterId.trim();
    if (mid.isEmpty) return null;

    final url = Uri.parse('https://api.discogs.com/masters/$mid');
    try {
      final res = await http.get(url, headers: _discogsHeaders()).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final main = data['main_release'];
      if (main is num) return main.toInt().toString();
      if (main is String && main.trim().isNotEmpty) return main.trim();
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<PriceRange?> _marketStatsFromDiscogsApi(String releaseId) async {
    final rid = releaseId.trim();
    if (rid.isEmpty) return null;

    final url = Uri.parse('https://api.discogs.com/marketplace/stats/$rid?curr_abbr=EUR');
    try {
      final res = await http.get(url, headers: _discogsHeaders()).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final low = data['lowest_price'];
      final high = data['highest_price'];
      final med = data['median_price'];

      double? min;
      double? max;
      String cur = 'EUR';

      if (low is Map) {
        final v = (low['value'] as num?)?.toDouble();
        if (v != null) min = v;
        final c = (low['currency'] as String?)?.trim();
        if (c != null && c.isNotEmpty) cur = c.toUpperCase();
      }

      if (high is Map) {
        final v = (high['value'] as num?)?.toDouble();
        if (v != null) max = v;
        final c = (high['currency'] as String?)?.trim();
        if (c != null && c.isNotEmpty) cur = c.toUpperCase();
      }

      // Si highest_price no viene (a veces no hay suficiente data), usamos median_price
      // para evitar rangos "€ X - X" cuando sí existe un valor central.
      if (max == null && med is Map) {
        final v = (med['value'] as num?)?.toDouble();
        if (v != null) max = v;
        final c = (med['currency'] as String?)?.trim();
        if (c != null && c.isNotEmpty) cur = c.toUpperCase();
      }

      if (min == null && max == null) return null;
      min ??= max;
      max ??= min;

      if (min == null || max == null) return null;
      if (max < min) {
        final t = min;
        min = max;
        max = t;
      }
      return PriceRange(
        min: min,
        max: max,
        currency: cur,
        fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      return null;
    }
  }

  // =============================
  // Fallback (scraping) - puede fallar por 403
  // =============================

  static Future<PriceRange?> _fetchFromDiscogsHtml({required String artist, required String album}) async {
    final query = '$artist $album'.trim();
    final searchUrl = Uri.parse(
      'https://www.discogs.com/search/?q=${Uri.encodeQueryComponent(query)}&type=release',
    );

    http.Response sRes;
    try {
      sRes = await http
          .get(searchUrl, headers: const {'User-Agent': 'Mozilla/5.0 (AppVinilos/price-range)'})
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
    if (sRes.statusCode != 200) return null;

    final html = sRes.body;
    final rel = RegExp(r'href="/release/(\d+)[^\"]*"', caseSensitive: false).firstMatch(html);
    final master = RegExp(r'href="/master/(\d+)[^\"]*"', caseSensitive: false).firstMatch(html);

    String? releaseId;
    if (rel != null) {
      releaseId = rel.group(1);
    } else if (master != null) {
      final mid = master.group(1);
      releaseId = await _releaseIdFromMasterHtml(mid);
    }

    if (releaseId == null || releaseId.trim().isEmpty) return null;
    return _marketStatsFromSellPageHtml(releaseId.trim());
  }

  static Future<String?> _releaseIdFromMasterHtml(String? masterId) async {
    final mid = (masterId ?? '').trim();
    if (mid.isEmpty) return null;

    final url = Uri.parse('https://www.discogs.com/master/$mid');
    http.Response res;
    try {
      res = await http
          .get(url, headers: const {'User-Agent': 'Mozilla/5.0 (AppVinilos/price-range)'})
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
    if (res.statusCode != 200) return null;
    final html = res.body;
    final rel = RegExp(r'href="/release/(\d+)[^\"]*"', caseSensitive: false).firstMatch(html);
    return rel?.group(1);
  }

  static Future<PriceRange?> _marketStatsFromSellPageHtml(String releaseId) async {
    final url = Uri.parse('https://www.discogs.com/sell/release/$releaseId');
    http.Response res;
    try {
      res = await http
          .get(url, headers: const {'User-Agent': 'Mozilla/5.0 (AppVinilos/price-range)'})
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
    if (res.statusCode != 200) return null;
    final html = res.body;

    final lowestJson = RegExp(
      r'"lowest_price"\s*:\s*\{\s*"value"\s*:\s*([0-9\.]+)\s*,\s*"currency"\s*:\s*"([A-Z]{3})"',
      caseSensitive: false,
    ).firstMatch(html);
    final highestJson = RegExp(
      r'"highest_price"\s*:\s*\{\s*"value"\s*:\s*([0-9\.]+)\s*,\s*"currency"\s*:\s*"([A-Z]{3})"',
      caseSensitive: false,
    ).firstMatch(html);

    if (lowestJson != null && highestJson != null) {
      final min = _parseNumber(lowestJson.group(1) ?? '');
      final max = _parseNumber(highestJson.group(1) ?? '');
      final cur = (lowestJson.group(2) ?? 'EUR').toUpperCase();
      if (min != null && max != null && max >= min) {
        return PriceRange(
          min: min,
          max: max,
          currency: cur,
          fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
      }
    }

    final lowTxt = RegExp(r'Lowest[^\dA-Z€$£]{0,40}([€$£]|[A-Z]{3})\s*([0-9][0-9\.,]*)', caseSensitive: false).firstMatch(html);
    final highTxt = RegExp(r'Highest[^\dA-Z€$£]{0,40}([€$£]|[A-Z]{3})\s*([0-9][0-9\.,]*)', caseSensitive: false).firstMatch(html);

    if (lowTxt != null && highTxt != null) {
      final min = _parseNumber(lowTxt.group(2) ?? '');
      final max = _parseNumber(highTxt.group(2) ?? '');
      final cur = _symbolToCurrency(lowTxt.group(1) ?? '€');
      if (min != null && max != null && max >= min) {
        return PriceRange(
          min: min,
          max: max,
          currency: cur,
          fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
      }
    }

    return null;
  }
}
