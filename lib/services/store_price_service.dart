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

  // ✅ Solo usamos estas 2 tiendas.
  // (El resto se eliminó para evitar precios erróneos y cambios de HTML.)
  static bool _isAllowedStore(String store) {
    final s = store.toLowerCase();
    return s.contains('imusic') || s.contains('muziker');
  }

  static List<StoreOffer> _onlyAllowed(List<StoreOffer> offers) {
    final out = <StoreOffer>[];
    for (final o in offers) {
      if (_isAllowedStore(o.store)) out.add(o);
    }
    out.sort((a, c) => a.price.compareTo(c.price));
    return out;
  }

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
            final filtered = _onlyAllowed(offers);
            _memCache[key] = filtered;
            return filtered;
          }
        }
      } catch (_) {
        // ignore
      }
    }

    if (_inflight.containsKey(key)) return _inflight[key]!;

    final fut = () async {
      final offers = _onlyAllowed(await fetchOffersByBarcode(b));
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
            final filtered = _onlyAllowed(offers);
            _memCache[key] = filtered;
            return filtered;
          }
        }
      } catch (_) {
        // ignore
      }
    }

    if (_inflight.containsKey(key)) return _inflight[key]!;

    final fut = () async {
      final offers = _onlyAllowed(await fetchOffersByQuery(artist: a, album: al));
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
    ]);

    for (final r in results) {
      if (r != null) offers.add(r);
    }

    return _onlyAllowed(offers);
  }

  static Future<List<StoreOffer>> fetchOffersByQuery({
    required String artist,
    required String album,
  }) async {
    final a = artist.trim();
    final al = album.trim();
    if (a.isEmpty || al.isEmpty) return const [];

    final q = '$a $al vinyl'.trim();

    final offers = <StoreOffer>[];
    final results = await Future.wait<StoreOffer?>([
      _fetchIMusicQuery(q),
      _fetchMuzikerArtistAlbum(artist: a, album: al, fallbackQuery: q),
    ]);
    for (final r in results) {
      if (r != null) offers.add(r);
    }
    return _onlyAllowed(offers);
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
    final og = RegExp(r'''property=["']og:url["']\s+content=["']([^"']+)["']''',
            caseSensitive: false)
        .firstMatch(h)
        ?.group(1);
    if (og != null && og.trim().isNotEmpty) return og.trim();

    final can = RegExp(r'''rel=["']canonical["']\s+href=["']([^"']+)["']''',
            caseSensitive: false)
        .firstMatch(h)
        ?.group(1);
    if (can != null && can.trim().isNotEmpty) return can.trim();
    return null;
  }

  static List<double> _extractEuroPrices(String html) {
    // Muchas tiendas muestran precios con:
    // - coma decimal (24,90 €)
    // - punto decimal (24.90 €)
    // - sin decimales (24 €)
    // - separador de miles (1 234,56 €)
    final h = html.replaceAll('&nbsp;', ' ').replaceAll('&euro;', '€');
    final prices = <double>[];

    void add(String s) {
      final v = _parseNumber(s);
      if (v != null && v > 0) prices.add(v);
    }

    // Número con posible separador de miles y 0-2 decimales.
    // Ej: 24,90 | 24.90 | 24 | 1 234,56
    final numRx = r'(\d{1,3}(?:[\s\.]\d{3})*(?:[\.,]\d{1,2})?|\d{1,5}(?:[\.,]\d{1,2})?)';

    // Soporta símbolo € y el literal EUR.
    final r1 = RegExp('$numRx\\s*(?:€|EUR)', caseSensitive: false);
    for (final m in r1.allMatches(h)) {
      final g = m.group(1);
      if (g != null) add(g);
    }

    final r2 = RegExp('(?:€|EUR)\\s*$numRx', caseSensitive: false);
    for (final m in r2.allMatches(h)) {
      final g = m.group(1);
      if (g != null) add(g);
    }

    return prices;
  }

  static double? _parseNumber(String s) {
    var t = s.trim();
    // Quita separadores de miles comunes.
    t = t.replaceAll(' ', '');
    // Normaliza separadores: 1.234,56 => 1234.56
    if (t.contains('.') && t.contains(',')) {
      // asumimos . miles, , decimal
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else if (t.contains(',')) {
      t = t.replaceAll(',', '.');
    }
    return double.tryParse(t);
  }

  static double? _minPrice(String html, {double minValid = 0}) {
    final list = _extractEuroPrices(html);
    if (list.isEmpty) return null;
    list.sort();
    if (minValid > 0) {
      final filtered = list.where((v) => v >= minValid).toList()..sort();
      if (filtered.isNotEmpty) return filtered.first;
    }
    return list.first;
  }

  /// Devuelve el primer precio detectado en el HTML (según orden de aparición).
  /// Útil para páginas de búsqueda con múltiples resultados, donde "min" podría
  /// pertenecer a otro producto.
  static double? _firstPriceInHtml(String html, {double minValid = 0}) {
    final h = html.replaceAll('&nbsp;', ' ').replaceAll('&euro;', '€');
    final numRx = r'(\d{1,3}(?:[\s\.]\d{3})*(?:[\.,]\d{1,2})?|\d{1,5}(?:[\.,]\d{1,2})?)';
    final m = RegExp(
      '(?:€|EUR)\\s*($numRx)|($numRx)\\s*(?:€|EUR)',
      caseSensitive: false,
    ).firstMatch(h);
    final g = (m?.group(1) ?? m?.group(2))?.trim();
    if (g == null || g.isEmpty) return null;
    final v = _parseNumber(g);
    if (v == null) return null;
    if (minValid > 0 && v < minValid) return null;
    return v;
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
    // iMusic suele devolver muchos precios (CD, envío, accesorios). Para evitar
    // falsos mínimos, intentamos tomar el precio cerca del primer resultado
    // que apunte al producto con el barcode.
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

    double? price;
    if (direct != null) {
      final rel = direct.replaceFirst('https://imusic.fi', '');
      final idx = html.indexOf(rel);
      if (idx >= 0) {
        final end = (idx + 1400) > html.length ? html.length : (idx + 1400);
        final snippet = html.substring(idx, end);
        price = _firstPriceInHtml(snippet, minValid: 7) ?? _minPrice(snippet, minValid: 7);
      }
    }
    price ??= _firstPriceInHtml(html, minValid: 7) ?? _minPrice(html, minValid: 7);
    if (price == null) return null;

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
    final rel = RegExp(r'''href=["'](/music/[^"']+)["']''', caseSensitive: false).firstMatch(html)?.group(1);
    if (rel != null && rel.isNotEmpty) {
      final idx = html.indexOf(rel);
      if (idx >= 0) {
        final end = (idx + 900) > html.length ? html.length : (idx + 900);
        final snippet = html.substring(idx, end);
        price = _firstPriceInHtml(snippet, minValid: 7) ?? _minPrice(snippet, minValid: 7);
      }
    }
    price ??= _firstPriceInHtml(html, minValid: 7) ?? _minPrice(html, minValid: 7);
    if (price == null) return null;

    final any = rel == null ? null : 'https://imusic.fi$rel';
    return StoreOffer(store: 'iMusic.fi', price: price, currency: 'EUR', url: any ?? url);
  }

  // ------------------ Muziker ------------------

  static String _muzikerSlug(String input) {
    // Muziker usa slugs ASCII (ej: "bombay-s-jayashri-lp-vinyylilevyt").
    // Sin dependencia externa: normalizamos los diacríticos más comunes.
    final lower = input.toLowerCase().trim();
    final out = StringBuffer();

    for (final r in lower.runes) {
      final ch = String.fromCharCode(r);
      switch (ch) {
        case 'á':
        case 'à':
        case 'â':
        case 'ä':
        case 'ã':
        case 'å':
          out.write('a');
          break;
        case 'é':
        case 'è':
        case 'ê':
        case 'ë':
          out.write('e');
          break;
        case 'í':
        case 'ì':
        case 'î':
        case 'ï':
          out.write('i');
          break;
        case 'ó':
        case 'ò':
        case 'ô':
        case 'ö':
        case 'õ':
          out.write('o');
          break;
        case 'ú':
        case 'ù':
        case 'û':
        case 'ü':
          out.write('u');
          break;
        case 'ñ':
          out.write('n');
          break;
        case 'ç':
          out.write('c');
          break;
        case '&':
          out.write(' and ');
          break;
        default:
          // a-z0-9 => keep, resto => espacio
          if ((r >= 97 && r <= 122) || (r >= 48 && r <= 57)) {
            out.write(ch);
          } else {
            out.write(' ');
          }
      }
    }

    return out
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(' ', '-');
  }

  static List<String> _tokens(String s) {
    final t = _normKey(s);
    if (t.isEmpty) return const [];
    return t.split(' ').where((e) => e.trim().isNotEmpty).toList(growable: false);
  }

  static int _scoreTokens(String haystackNormalized, List<String> tokens) {
    var score = 0;
    for (final tok in tokens) {
      if (tok.length < 2) continue;
      if (haystackNormalized.contains(tok)) score++;
    }
    return score;
  }

  static ({String url, double price})? _bestFromMuzikerListing(String html, {required String album}) {
    final albumTokens = _tokens(album);
    if (albumTokens.isEmpty) return null;

    final hrefRx = RegExp(r'''href=["'](/[^"']+)["']''', caseSensitive: false);

    int bestScore = 0;
    double bestPrice = 0;
    String? bestUrl;

    for (final m in hrefRx.allMatches(html)) {
      final path = m.group(1);
      if (path == null || path.isEmpty) continue;

      // Filtrado rápido de links que claramente no son productos.
      if (!path.startsWith('/')) continue;
      if (path.startsWith('/search') || path.startsWith('/haku')) continue;
      if (path.contains('page=')) continue;
      if (path.endsWith('.png') || path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.webp') || path.endsWith('.svg')) {
        continue;
      }
      if (path.contains('/cookies') || path.contains('/faq') || path.contains('/blog')) continue;

      final start = m.start;
      final end = (start + 900) > html.length ? html.length : (start + 900);
      final snippet = html.substring(start, end);

      // Evita capturar "5 €" (cupones) o "0 €" (envío).
      if (!snippet.contains('€') && !snippet.toLowerCase().contains('eur')) continue;
      if (!RegExp(r'(vinyyl|vinyl|lp)', caseSensitive: false).hasMatch(snippet)) continue;

      final snNorm = _normKey(snippet);
      final score = _scoreTokens(snNorm, albumTokens);
      if (score <= 0) continue;

      final p = _minPrice(snippet, minValid: 7);
      if (p == null) continue;

      final fullUrl = 'https://www.muziker.fi$path';
      if (bestUrl == null || score > bestScore || (score == bestScore && p < bestPrice)) {
        bestScore = score;
        bestPrice = p;
        bestUrl = fullUrl;
      }
    }

    if (bestUrl == null) return null;
    return (url: bestUrl!, price: bestPrice);
  }

  static Future<StoreOffer?> _fetchMuzikerArtistAlbum({
    required String artist,
    required String album,
    required String fallbackQuery,
  }) async {
    // ✅ Estrategia 1 (más estable): página SEO por artista
    // Ej: https://www.muziker.fi/fletcher-lp-vinyylilevyt
    final slug = _muzikerSlug(artist);
    if (slug.isNotEmpty) {
      final base = 'https://www.muziker.fi/$slug-lp-vinyylilevyt';
      final pages = <String>[base, '$base?page=2', '$base?page=3'];

      for (final u in pages) {
        final res = await _get(u);
        if (res == null) continue;
        final html = res.body;

        final hit = _bestFromMuzikerListing(html, album: album);
        if (hit != null) {
          // Intentamos entrar al producto para nota/canonical (si falla, devolvemos el URL hallado igual).
          final res2 = await _get(hit.url);
          if (res2 != null) {
            final html2 = res2.body;
            final p2 = _minPrice(html2, minValid: 7) ?? hit.price;
            final can2 = _extractCanonical(html2) ?? hit.url;
            final note2 = _extractMuzikerNote(html2);
            return StoreOffer(store: 'Muziker.fi', price: p2, currency: 'EUR', url: can2, note: note2);
          }
          return StoreOffer(store: 'Muziker.fi', price: hit.price, currency: 'EUR', url: hit.url);
        }
      }
    }

    // ✅ Estrategia 2: búsqueda (best-effort)
    return _fetchMuzikerQuery(fallbackQuery);
  }

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
        // Muziker a veces muestra "0 € envío" o "5 € descuento"; evitamos falsos mínimos.
        final p = _minPrice(html, minValid: 7);
        if (p != null) {
          final can = _extractCanonical(html) ?? u;
          final note = _extractMuzikerNote(html);
          return StoreOffer(store: 'Muziker.fi', price: p, currency: 'EUR', url: can, note: note);
        }
      }

      // En páginas de búsqueda/listado, tomamos el primer precio "razonable".
      final pList = _firstPriceInHtml(html, minValid: 7);
      if (pList != null) {
        final can = _extractCanonical(html) ?? u;
        return StoreOffer(store: 'Muziker.fi', price: pList, currency: 'EUR', url: can);
      }

      // Intenta extraer primer link de producto y entrar.
      final productUrl = _firstHref(
        html,
        RegExp(r'''href=["'](https?://www\.muziker\.fi/[^"']+)["']''', caseSensitive: false),
      );
      final productPath = _firstHref(
        html,
        RegExp(r'''href=["'](/[^"']+)["']''', caseSensitive: false),
        prefix: 'https://www.muziker.fi',
      );
      final candidate = productUrl ?? productPath;
      if (candidate == null) continue;

      final res2 = await _get(candidate);
      if (res2 == null) continue;
      final html2 = res2.body;
      final p2 = _minPrice(html2, minValid: 7);
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

      // En páginas de listado, usamos el primer precio "razonable" (evita 0 € / 5 € descuento).
      final pList = _firstPriceInHtml(html, minValid: 7);

      // Intenta extraer primer link de producto y entrar (preferible).
      final productUrl = _firstHref(
        html,
        RegExp(r'''href=["'](https?://www\.muziker\.fi/[^"']+)["']''', caseSensitive: false),
      );
      final productPath = _firstHref(
        html,
        RegExp(r'''href=["'](/[^"']+)["']''', caseSensitive: false),
        prefix: 'https://www.muziker.fi',
      );
      final candidate = productUrl ?? productPath;

      if (candidate != null) {
        final res2 = await _get(candidate);
        if (res2 != null) {
          final html2 = res2.body;
          final p2 = _minPrice(html2, minValid: 7);
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

}
