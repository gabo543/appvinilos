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
    if (min == null || max == null || currency == null || currency.isEmpty) return null;
    return PriceRange(min: min, max: max, currency: currency);
  }
}

/// Estimación de rango de precios (mín–máx) para un álbum.
///
/// Implementación pensada para no pedir API keys:
/// - intenta encontrar un release en Discogs vía búsqueda web
/// - luego intenta leer estadísticas (mín/máx) desde la página de venta
///
/// Si falla, devuelve null (la UI muestra "€ —").
class PriceRangeService {
  static const _prefsPrefix = 'price_range::';
  static const _ttl = Duration(days: 14);

  static final Map<String, PriceRange?> _memCache = {};

  static String _cacheKey(String artist, String album) {
    return _prefsPrefix + normalizeKey('$artist||$album');
  }

  static bool _isFreshTs(int? ts) {
    if (ts == null || ts <= 0) return false;
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return DateTime.now().difference(dt) <= _ttl;
  }

  static double? _parseNumber(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    // Limpia símbolos comunes
    s = s.replaceAll(RegExp(r'[^0-9,\.]'), '');
    if (s.isEmpty) return null;

    // Heurística: si tiene "," y "." a la vez, asumimos que "," es separador de miles.
    if (s.contains(',') && s.contains('.')) {
      s = s.replaceAll(',', '');
    } else if (s.contains(',') && !s.contains('.')) {
      // Si solo hay coma, asumimos coma decimal.
      s = s.replaceAll(',', '.');
    }
    return double.tryParse(s);
  }

  static String _symbolToCurrency(String s) {
    final t = s.trim();
    if (t == '€') return 'EUR';
    if (t == r'$') return 'USD';
    if (t == '£') return 'GBP';
    // Discogs a veces muestra código (EUR/USD)
    if (RegExp(r'^[A-Z]{3}$').hasMatch(t)) return t;
    return 'EUR';
  }

  static Future<PriceRange?> getRange({required String artist, required String album}) async {
    final a = artist.trim();
    final al = album.trim();
    if (a.isEmpty || al.isEmpty) return null;

    final key = _cacheKey(a, al);
    if (_memCache.containsKey(key)) return _memCache[key];

    // SharedPrefs cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw != null && raw.trim().isNotEmpty) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        if (m['null'] == true) {
          final ts = (m['ts'] as num?)?.toInt();
          if (_isFreshTs(ts)) {
            _memCache[key] = null;
            return null;
          }
        }
        final ts = (m['ts'] as num?)?.toInt();
        if (_isFreshTs(ts)) {
          final pr = PriceRange.fromJson(m);
          _memCache[key] = pr;
          return pr;
        }
      }
    } catch (_) {
      // ignore
    }

    // Fetch from Discogs (best-effort, no API key)
    final pr = await _fetchFromDiscogs(artist: a, album: al);
    _memCache[key] = pr;

    // Persist cache (even null -> to avoid hammering)
    try {
      final prefs = await SharedPreferences.getInstance();
      if (pr != null) {
        await prefs.setString(key, jsonEncode(pr.toJson()));
      } else {
        await prefs.setString(
          key,
          jsonEncode({'ts': DateTime.now().millisecondsSinceEpoch, 'null': true}),
        );
      }
    } catch (_) {
      // ignore
    }

    // Si persistimos un marcador "null", no lo devolvemos.
    if (pr == null) return null;
    return pr;
  }

  static Future<PriceRange?> _fetchFromDiscogs({required String artist, required String album}) async {
    final query = '$artist $album'.trim();
    final searchUrl = Uri.parse(
      'https://www.discogs.com/search/?q=${Uri.encodeQueryComponent(query)}&type=release',
    );

    http.Response sRes;
    try {
      sRes = await http
          .get(searchUrl, headers: const {'User-Agent': 'AppVinilos/1.0 (price-range)'}).timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
    if (sRes.statusCode != 200) return null;

    final html = sRes.body;
    // Busca el primer /release/ID o /master/ID
    final rel = RegExp(r'href="/release/(\d+)[^\"]*"', caseSensitive: false).firstMatch(html);
    final master = RegExp(r'href="/master/(\d+)[^\"]*"', caseSensitive: false).firstMatch(html);

    String? releaseId;
    if (rel != null) {
      releaseId = rel.group(1);
    } else if (master != null) {
      // Si sólo encontramos master, intentamos ir a su página y rescatar un release.
      final mid = master.group(1);
      releaseId = await _releaseIdFromMaster(mid);
    }

    if (releaseId == null || releaseId.trim().isEmpty) return null;
    return _marketStatsFromSellPage(releaseId.trim());
  }

  static Future<String?> _releaseIdFromMaster(String? masterId) async {
    final mid = (masterId ?? '').trim();
    if (mid.isEmpty) return null;

    final url = Uri.parse('https://www.discogs.com/master/$mid');
    http.Response res;
    try {
      res = await http
          .get(url, headers: const {'User-Agent': 'AppVinilos/1.0 (price-range)'}).timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
    if (res.statusCode != 200) return null;
    final html = res.body;
    final rel = RegExp(r'href="/release/(\d+)[^\"]*"', caseSensitive: false).firstMatch(html);
    return rel?.group(1);
  }

  static Future<PriceRange?> _marketStatsFromSellPage(String releaseId) async {
    final url = Uri.parse('https://www.discogs.com/sell/release/$releaseId');
    http.Response res;
    try {
      res = await http
          .get(url, headers: const {'User-Agent': 'AppVinilos/1.0 (price-range)'}).timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
    if (res.statusCode != 200) return null;
    final html = res.body;

    // Intento 1: JSON pre-cargado con lowest_price / highest_price
    final lowestJson = RegExp(r'"lowest_price"\s*:\s*\{\s*"value"\s*:\s*([0-9\.]+)\s*,\s*"currency"\s*:\s*"([A-Z]{3})"', caseSensitive: false)
        .firstMatch(html);
    final highestJson = RegExp(r'"highest_price"\s*:\s*\{\s*"value"\s*:\s*([0-9\.]+)\s*,\s*"currency"\s*:\s*"([A-Z]{3})"', caseSensitive: false)
        .firstMatch(html);
    if (lowestJson != null && highestJson != null) {
      final min = _parseNumber(lowestJson.group(1) ?? '');
      final max = _parseNumber(highestJson.group(1) ?? '');
      final cur = (lowestJson.group(2) ?? 'EUR').toUpperCase();
      if (min != null && max != null && max >= min) {
        return PriceRange(min: min, max: max, currency: cur);
      }
    }

    // Intento 2: texto en HTML "Lowest" / "Highest".
    // Acepta símbolos o códigos.
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
