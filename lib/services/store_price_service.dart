import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class StoreOffer {
  final String store;
  final double price;
  final String currency;
  final String url;
  final String? note;

  const StoreOffer({
    required this.store,
    required this.price,
    required this.currency,
    required this.url,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'store': store,
        'price': price,
        'currency': currency,
        'url': url,
        if (note != null) 'note': note,
      };

  static StoreOffer? fromJson(Map<String, dynamic> m) {
    final store = (m['store'] as String?)?.trim();
    final price = (m['price'] as num?)?.toDouble();
    final currency = (m['currency'] as String?)?.trim();
    final url = (m['url'] as String?)?.trim();
    final note = (m['note'] as String?)?.trim();
    if (store == null || store.isEmpty || price == null || currency == null || currency.isEmpty || url == null || url.isEmpty) {
      return null;
    }
    return StoreOffer(
      store: store,
      price: price,
      currency: currency,
      url: url,
      note: (note == null || note.isEmpty) ? null : note,
    );
  }
}

/// Obtiene precios (best-effort) desde tiendas europeas.
///
/// Nota: estas tiendas no exponen una API pública estable; por eso usamos scraping
/// simple de HTML (puede fallar si cambian el layout o bloquean bots).
class StorePriceService {
  static const _ua =
      'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';

  static const _prefsPrefix = 'store_offers::';
  static const _prefsPrefixQuery = 'store_offers_q::';
  static const _ttlOk = Duration(hours: 12);
  static const _ttlEmpty = Duration(hours: 6);

  static final Map<String, List<StoreOffer>?> _memCache = {};
  static final Map<String, Future<List<StoreOffer>>> _inflight = {};

  // Throttle por host (mejor UX: podemos consultar tiendas distintas en paralelo,
  // sin spamear una misma tienda).
  static final Map<String, DateTime> _lastFetchByHost = {};

  static String _cacheKey(String barcode) => '$_prefsPrefix${barcode.trim()}';

  static String _normKey(String s) {
    final t = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t;
  }

  static String _cacheKeyQuery({required String artist, required String album}) {
    final k = _normKey('$artist||$album');
    return '$_prefsPrefixQuery$k';
  }

  static bool _isFresh(int ts, Duration ttl) {
    if (ts <= 0) return false;
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return DateTime.now().difference(dt) <= ttl;
  }

  static Future<void> _throttleHost(String host) async {
    final last = _lastFetchByHost[host];
    if (last != null) {
      final diff = DateTime.now().difference(last);
      if (diff.inMilliseconds < 900) {
        await Future.delayed(Duration(milliseconds: 900 - diff.inMilliseconds));
      }
    }
    _lastFetchByHost[host] = DateTime.now();
  }

  static Future<List<StoreOffer>> fetchOffersByBarcodeCached(
    String barcode, {
    bool forceRefresh = false,
  }) async {
    final b = barcode.trim();
    if (b.isEmpty) return const [];

    final key = _cacheKey(b);
    if (!forceRefresh && _memCache.containsKey(key)) {
      return _memCache[key] ?? const [];
    }

    if (!forceRefresh) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(key);
        if (raw != null && raw.trim().isNotEmpty) {
          final m = jsonDecode(raw) as Map<String, dynamic>;
          final ts = (m['ts'] as num?)?.toInt() ?? 0;
          final offersRaw = (m['offers'] as List?) ?? const [];
          final ttl = offersRaw.isEmpty ? _ttlEmpty : _ttlOk;
          if (ts > 0 && _isFresh(ts, ttl)) {
            final offers = <StoreOffer>[];
            for (final x in offersRaw) {
              if (x is Map) {
                final o = StoreOffer.fromJson(Map<String, dynamic>.from(x));
                if (o != null) offers.add(o);
              }
            }
            offers.sort((a, c) => a.price.compareTo(c.price));
            _memCache[key] = offers;
            return offers;
          }
        }
      } catch (_) {
        // ignore
      }
    }

    if (_inflight.containsKey(key)) return _inflight[key]!;

    final fut = () async {
      final offers = await fetchOffersByBarcode(b);
      _memCache[key] = offers;
      try {
        final prefs = await SharedPreferences.getInstance();
        final payload = {
          'ts': DateTime.now().millisecondsSinceEpoch,
          'offers': offers.map((o) => o.toJson()).toList(),
        };
        await prefs.setString(key, jsonEncode(payload));
      } catch (_) {
        // ignore
      }
      return offers;
    }();

    _inflight[key] = fut;
    try {
      return await fut;
    } finally {
      _inflight.remove(key);
    }
  }

  /// Best-effort: busca por texto (artista + álbum) en las tiendas.
  ///
  /// Nota: este método es menos preciso que el barcode (EAN/UPC).
  static Future<List<StoreOffer>> fetchOffersByQueryCached({
    required String artist,
    required String album,
    bool forceRefresh = false,
  }) async {
    final a = artist.trim();
    final al = album.trim();
    if (a.isEmpty || al.isEmpty) return const [];

    final key = _cacheKeyQuery(artist: a, album: al);

    if (!forceRefresh && _memCache.containsKey(key)) {
      return _memCache[key] ?? const [];
    }

    if (!forceRefresh) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(key);
        if (raw != null && raw.trim().isNotEmpty) {
          final m = jsonDecode(raw) as Map<String, dynamic>;
          final ts = (m['ts'] as num?)?.toInt() ?? 0;
          final offersRaw = (m['offers'] as List?) ?? const [];
          final ttl = offersRaw.isEmpty ? _ttlEmpty : _ttlOk;
          if (ts > 0 && _isFresh(ts, ttl)) {
            final offers = <StoreOffer>[];
            for (final x in offersRaw) {
              if (x is Map) {
                final o = StoreOffer.fromJson(Map<String, dynamic>.from(x));
                if (o != null) offers.add(o);
              }
            }
            offers.sort((a, c) => a.price.compareTo(c.price));
            _memCache[key] = offers;
            return offers;
          }
        }
      } catch (_) {
        // ignore
      }
    }

    if (_inflight.containsKey(key)) return _inflight[key]!;

    final fut = () async {
      final offers = await fetchOffersByQuery(artist: a, album: al);
      _memCache[key] = offers;
      try {
        final prefs = await SharedPreferences.getInstance();
        final payload = {
          'ts': DateTime.now().millisecondsSinceEpoch,
          'offers': offers.map((o) => o.toJson()).toList(),
        };
        await prefs.setString(key, jsonEncode(payload));
      } catch (_) {
        // ignore
      }
      return offers;
    }();

    _inflight[key] = fut;
    try {
      return await fut;
    } finally {
      _inflight.remove(key);
    }
  }

  static Future<List<StoreOffer>> fetchOffersByBarcode(String barcode) async {
    final b = (barcode).trim();
    if (b.isEmpty) return const [];

    final offers = <StoreOffer>[];

    final results = await Future.wait<StoreOffer?>([
      _fetchIMusic(b),
      _fetchMuziker(b),
      _fetchLevykauppaX(b),
    ]);

    for (final r in results) {
      if (r != null) offers.add(r);
    }

    offers.sort((a, c) => a.price.compareTo(c.price));
    return offers;
  }

  static Future<List<StoreOffer>> fetchOffersByQuery({
    required String artist,
    required String album,
  }) async {
    final q = '${artist.trim()} ${album.trim()} vinyl'.trim();
    if (q.isEmpty) return const [];

    final offers = <StoreOffer>[];
    final results = await Future.wait<StoreOffer?>([
      _fetchIMusicQuery(q),
      _fetchMuzikerQuery(q),
      _fetchLevykauppaXQuery(q),
    ]);
    for (final r in results) {
      if (r != null) offers.add(r);
    }
    offers.sort((a, c) => a.price.compareTo(c.price));
    return offers;
  }

  static Future<http.Response?> _get(String url) async {
    try {
      final uri = Uri.parse(url);

      // Polite throttle por dominio.
      await _throttleHost(uri.host);

      final res = await http
          .get(
            uri,
            headers: const {
              'User-Agent': _ua,
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
              'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8,fi;q=0.7',
            },
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode >= 200 && res.statusCode < 300) return res;
      return null;
    } catch (_) {
      return null;
    }
  }

  static String? _extractCanonical(String html) {
    final h = html.replaceAll('&nbsp;', ' ');
    final og = RegExp(r'property=["\']og:url["\']\s+content=["\']([^"\']+)["\']',
            caseSensitive: false)
        .firstMatch(h)
        ?.group(1);
    if (og != null && og.trim().isNotEmpty) return og.trim();

    final can = RegExp(r'rel=["\']canonical["\']\s+href=["\']([^"\']+)["\']',
            caseSensitive: false)
        .firstMatch(h)
        ?.group(1);
    if (can != null && can.trim().isNotEmpty) return can.trim();
    return null;
  }

  static List<double> _extractEuroPrices(String html) {
    final h = html.replaceAll('&nbsp;', ' ').replaceAll('&euro;', '€');
    final prices = <double>[];

    void add(String s) {
      final v = _parseNumber(s);
      if (v != null && v > 0) prices.add(v);
    }

    final r1 = RegExp(r'(\d{1,5}(?:[\.,]\d{2}))\s*€');
    for (final m in r1.allMatches(h)) {
      final g = m.group(1);
      if (g != null) add(g);
    }

    final r2 = RegExp(r'€\s*(\d{1,5}(?:[\.,]\d{2}))');
    for (final m in r2.allMatches(h)) {
      final g = m.group(1);
      if (g != null) add(g);
    }

    return prices;
  }

  static double? _parseNumber(String s) {
    var t = s.trim();
    // Normaliza separadores: 1.234,56 => 1234.56
    if (t.contains('.') && t.contains(',')) {
      // asumimos . miles, , decimal
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else if (t.contains(',')) {
      t = t.replaceAll(',', '.');
    }
    return double.tryParse(t);
  }

  static double? _minPrice(String html) {
    final list = _extractEuroPrices(html);
    if (list.isEmpty) return null;
    list.sort();
    return list.first;
  }

  /// Devuelve el primer precio detectado en el HTML (según orden de aparición).
  /// Útil para páginas de búsqueda con múltiples resultados, donde "min" podría
  /// pertenecer a otro producto.
  static double? _firstPriceInHtml(String html) {
    final h = html.replaceAll('&nbsp;', ' ').replaceAll('&euro;', '€');
    final m = RegExp(
      r'€\s*(\d{1,5}(?:[\.,]\d{2}))|(\d{1,5}(?:[\.,]\d{2}))\s*€',
      caseSensitive: false,
    ).firstMatch(h);
    final g = (m?.group(1) ?? m?.group(2))?.trim();
    if (g == null || g.isEmpty) return null;
    return _parseNumber(g);
  }

  static String? _firstHref(String html, RegExp rx, {String? prefix}) {
    final m = rx.firstMatch(html);
    final path = m?.group(1);
    if (path == null || path.trim().isEmpty) return null;
    if (path.startsWith('http')) return path;
    if (prefix != null) return '$prefix$path';
    return path;
  }

  // ------------------ iMusic ------------------

  static Future<StoreOffer?> _fetchIMusic(String barcode) async {
    final url = 'https://imusic.fi/page/search?query=$barcode';
    final res = await _get(url);
    if (res == null) return null;

    final html = res.body;
    final price = _minPrice(html);
    if (price == null) return null;

    // Preferimos un link /music/<barcode>/...
    final direct = _firstHref(
      html,
      RegExp('href=["\'](/music/$barcode/[^"\']+)["\']', caseSensitive: false),
      prefix: 'https://imusic.fi',
    );
    final any = _firstHref(
      html,
      RegExp('href=["\'](/music/[^"\']+)["\']', caseSensitive: false),
      prefix: 'https://imusic.fi',
    );

    return StoreOffer(
      store: 'iMusic.fi',
      price: price,
      currency: 'EUR',
      url: direct ?? any ?? url,
    );
  }

  static Future<StoreOffer?> _fetchIMusicQuery(String query) async {
    final q = Uri.encodeQueryComponent(query);
    final url = 'https://imusic.fi/page/search?query=$q';
    final res = await _get(url);
    if (res == null) return null;

    final html = res.body;
    // Intentamos tomar el precio del primer resultado (no el mínimo del listado).
    double? price;
    final rel = RegExp(r'href=["\'](/music/[^"\']+)["\']', caseSensitive: false).firstMatch(html)?.group(1);
    if (rel != null && rel.isNotEmpty) {
      final idx = html.indexOf(rel);
      if (idx >= 0) {
        final end = (idx + 900) > html.length ? html.length : (idx + 900);
        final snippet = html.substring(idx, end);
        price = _firstPriceInHtml(snippet) ?? _minPrice(snippet);
      }
    }
    price ??= _firstPriceInHtml(html);
    if (price == null) return null;

    final any = rel == null ? null : 'https://imusic.fi$rel';
    return StoreOffer(store: 'iMusic.fi', price: price, currency: 'EUR', url: any ?? url);
  }

  // ------------------ Muziker ------------------

  static Future<StoreOffer?> _fetchMuziker(String barcode) async {
    final tries = <String>[
      'https://www.muziker.fi/search?q=$barcode',
      'https://www.muziker.fi/search?query=$barcode',
      'https://www.muziker.fi/search/?q=$barcode',
      'https://www.muziker.fi/haku?q=$barcode',
      'https://www.muziker.fi/?s=$barcode',
    ];

    for (final u in tries) {
      final res = await _get(u);
      if (res == null) continue;
      final html = res.body;

      // Si ya es una página de producto (contiene el barcode + precio)
      if (html.contains(barcode)) {
        final p = _minPrice(html);
        if (p != null) {
          final can = _extractCanonical(html) ?? u;
          final note = _extractMuzikerNote(html);
          return StoreOffer(store: 'Muziker.fi', price: p, currency: 'EUR', url: can, note: note);
        }
      }

      // Intenta extraer primer link de producto y entrar.
      final productUrl = _firstHref(
        html,
        RegExp(r'href=["\'](https?://www\.muziker\.fi/[^"\']+)["\']', caseSensitive: false),
      );
      final productPath = _firstHref(
        html,
        RegExp(r'href=["\'](/[^"\']+)["\']', caseSensitive: false),
        prefix: 'https://www.muziker.fi',
      );
      final candidate = productUrl ?? productPath;
      if (candidate == null) continue;

      final res2 = await _get(candidate);
      if (res2 == null) continue;
      final html2 = res2.body;
      final p2 = _minPrice(html2);
      if (p2 == null) continue;
      final can2 = _extractCanonical(html2) ?? candidate;
      // Si no contiene barcode, igual lo devolvemos (best-effort)
      final note2 = _extractMuzikerNote(html2);
      return StoreOffer(store: 'Muziker.fi', price: p2, currency: 'EUR', url: can2, note: note2);
    }

    return null;
  }

  static Future<StoreOffer?> _fetchMuzikerQuery(String query) async {
    final q = Uri.encodeQueryComponent(query);
    final tries = <String>[
      'https://www.muziker.fi/search?q=$q',
      'https://www.muziker.fi/search?query=$q',
      'https://www.muziker.fi/search/?q=$q',
      'https://www.muziker.fi/haku?q=$q',
      'https://www.muziker.fi/?s=$q',
    ];

    for (final u in tries) {
      final res = await _get(u);
      if (res == null) continue;
      final html = res.body;

      // En páginas de listado, usamos el primer precio visible.
      final pList = _firstPriceInHtml(html);

      // Intenta extraer primer link de producto y entrar (preferible).
      final productUrl = _firstHref(
        html,
        RegExp(r'href=["\'](https?://www\\.muziker\\.fi/[^"\']+)["\']', caseSensitive: false),
      );
      final productPath = _firstHref(
        html,
        RegExp(r'href=["\'](/[^"\']+)["\']', caseSensitive: false),
        prefix: 'https://www.muziker.fi',
      );
      final candidate = productUrl ?? productPath;

      if (candidate != null) {
        final res2 = await _get(candidate);
        if (res2 != null) {
          final html2 = res2.body;
          final p2 = _minPrice(html2);
          if (p2 != null) {
            final can2 = _extractCanonical(html2) ?? candidate;
            final note2 = _extractMuzikerNote(html2);
            return StoreOffer(store: 'Muziker.fi', price: p2, currency: 'EUR', url: can2, note: note2);
          }
        }
      }

      // Fallback: usa precio del listado si existe.
      if (pList != null) {
        final can = _extractCanonical(html) ?? u;
        return StoreOffer(store: 'Muziker.fi', price: pList, currency: 'EUR', url: can);
      }
    }

    return null;
  }

  static String? _extractMuzikerNote(String html) {
    // Ej: "koodilla MUZMUZ-40"
    final m = RegExp(r'(koodilla|code)\s+([A-Z0-9\-]{3,})', caseSensitive: false)
        .firstMatch(html);
    final code = m?.group(2);
    if (code == null || code.trim().isEmpty) return null;
    return 'Con código $code';
  }

  // ------------------ Levykauppa Äx ------------------

  static Future<StoreOffer?> _fetchLevykauppaX(String barcode) async {
    final tries = <String>[
      'https://www.levykauppax.fi/search/?q=$barcode',
      'https://www.levykauppax.fi/search?q=$barcode',
      'https://www.levykauppax.fi/haku/?q=$barcode',
      'https://www.levykauppax.fi/?q=$barcode',
      'https://www.levykauppax.fi/index.php?search=$barcode',
      'https://www.levykauppax.fi/index.php?hakusana=$barcode',
    ];

    for (final u in tries) {
      final res = await _get(u);
      if (res == null) continue;
      final html = res.body;

      final p = _minPrice(html);
      if (p == null) continue;
      final can = _extractCanonical(html) ?? u;
      return StoreOffer(store: 'Levykauppa Äx', price: p, currency: 'EUR', url: can);
    }

    return null;
  }

  static Future<StoreOffer?> _fetchLevykauppaXQuery(String query) async {
    final q = Uri.encodeQueryComponent(query);
    final tries = <String>[
      'https://www.levykauppax.fi/search/?q=$q',
      'https://www.levykauppax.fi/search?q=$q',
      'https://www.levykauppax.fi/haku/?q=$q',
      'https://www.levykauppax.fi/?q=$q',
      'https://www.levykauppax.fi/index.php?search=$q',
      'https://www.levykauppax.fi/index.php?hakusana=$q',
    ];

    for (final u in tries) {
      final res = await _get(u);
      if (res == null) continue;
      final html = res.body;

      // En búsquedas con múltiples resultados, usa el primer precio visible.
      final p = _firstPriceInHtml(html) ?? _minPrice(html);
      if (p == null) continue;
      final can = _extractCanonical(html) ?? u;
      return StoreOffer(store: 'Levykauppa Äx', price: p, currency: 'EUR', url: can);
    }

    return null;
  }
}
