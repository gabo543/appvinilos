import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/normalize.dart';

class PriceRange {
  final double min;
  final double max;
  final String currency; // e.g. EUR, USD

  const PriceRange({required this.min, required this.max, required this.currency});

  Map<String, dynamic> toJson() => {
        'min': min,
        'max': max,
        'currency': currency,
        'ts': DateTime.now().millisecondsSinceEpoch,
      };

  static PriceRange? fromJson(Map<String, dynamic> m) {
    final min = (m['min'] as num?)?.toDouble();
    final max = (m['max'] as num?)?.toDouble();
    final currency = (m['currency'] as String?)?.trim();
    if (min == null || max == null || currency == null || currency.isEmpty) {
      return null;
    }
    return PriceRange(min: min, max: max, currency: currency);
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
  }) async {
    final a = artist.trim();
    final al = album.trim();
    if (a.isEmpty || al.isEmpty) return null;

    final key = _cacheKey(artist: a, album: al, mbid: mbid);
    if (_memCache.containsKey(key)) return _memCache[key];

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

      final releaseId = (releases.first as Map)['id']?.toString();
      if (releaseId == null || releaseId.trim().isEmpty) return null;

      final urlRel = Uri.parse('$_mbBase/release/$releaseId?inc=url-rels&fmt=json');
      final resRel = await _mbGet(urlRel);
      if (resRel.statusCode != 200) return null;

      final rel = jsonDecode(resRel.body) as Map<String, dynamic>;
      final rels = (rel['relations'] as List?) ?? const [];

      String? masterId;

      for (final r in rels) {
        final url = ((r as Map)['url']?['resource'] ?? '').toString();
        if (url.isEmpty) continue;

        final mRelease = RegExp(r'discogs\.com/(?:[a-z]{2}/)?release/(\d+)', caseSensitive: false).firstMatch(url);
        if (mRelease != null) return mRelease.group(1);

        final mMaster = RegExp(r'discogs\.com/(?:[a-z]{2}/)?master/(\d+)', caseSensitive: false).firstMatch(url);
        if (mMaster != null) {
          masterId = mMaster.group(1);
        }
      }

      if (masterId != null) {
        return _discogsMainReleaseFromMaster(masterId);
      }

      return null;
    } catch (_) {
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

      if (min == null && max == null) return null;
      min ??= max;
      max ??= min;

      if (min == null || max == null) return null;
      if (max < min) {
        final t = min;
        min = max;
        max = t;
      }
      return PriceRange(min: min, max: max, currency: cur);
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
        return PriceRange(min: min, max: max, currency: cur);
      }
    }

    final lowTxt = RegExp(r'Lowest[^\dA-Z€$£]{0,40}([€$£]|[A-Z]{3})\s*([0-9][0-9\.,]*)', caseSensitive: false).firstMatch(html);
    final highTxt = RegExp(r'Highest[^\dA-Z€$£]{0,40}([€$£]|[A-Z]{3})\s*([0-9][0-9\.,]*)', caseSensitive: false).firstMatch(html);

    if (lowTxt != null && highTxt != null) {
      final min = _parseNumber(lowTxt.group(2) ?? '');
      final max = _parseNumber(highTxt.group(2) ?? '');
      final cur = _symbolToCurrency(lowTxt.group(1) ?? '€');
      if (min != null && max != null && max >= min) {
        return PriceRange(min: min, max: max, currency: cur);
      }
    }

    return null;
  }
}
