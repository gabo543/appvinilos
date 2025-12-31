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

  static const _prefsPrefix = 'store_offers_v3::';
  static const _prefsPrefixQuery = 'store_offers_q_v3::';
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


  static bool _looksLikeBadContext(String snippet) {
    final s = _normKey(snippet);
    const bad = <String>[
      'shipping',
      'delivery',
      'toimitus',
      'postitus',
      'postage',
      'discount',
      'alennus',
      'koodilla',
      'code',
      'coupon',
      'kupon',
      'tarjous',
      'sale',
    ];
    for (final w in bad) {
      if (s.contains(w)) return true;
    }
    return false;
  }

  static List<double> _extractJsonLdEuroPrices(String html) {
    final out = <double>[];
    final rx = RegExp(
      r"""<script[^>]+type=["\']application/ld\+json["\'][^>]*>(.*?)</script>""",
      caseSensitive: false,
      dotAll: true,
    );

    for (final m in rx.allMatches(html)) {
      final raw = m.group(1);
      if (raw == null) continue;
      final cleaned = raw.trim();
      if (cleaned.isEmpty) continue;

      dynamic data;
      try {
        data = jsonDecode(cleaned);
      } catch (_) {
        continue;
      }

      void collect(dynamic node) {
        if (node == null) return;
        if (node is List) {
          for (final e in node) collect(e);
          return;
        }
        if (node is Map) {
          final map = Map<String, dynamic>.from(node);

          double? asNum(dynamic v) {
            if (v == null) return null;
            if (v is num) return v.toDouble();
            final s = v.toString().trim();
            if (s.isEmpty) return null;
            return _parseNumber(s);
          }

          final currency = (map['priceCurrency'] ?? map['pricecurrency'] ?? map['currency'])
              ?.toString()
              .toUpperCase()
              .trim();
          final hasCurrency = currency != null && currency.isNotEmpty;
          final eurOk = !hasCurrency || currency == 'EUR' || currency == '€';

          if (eurOk) {
            final p = asNum(map['price']);
            final lp = asNum(map['lowPrice'] ?? map['lowprice']);
            final hp = asNum(map['highPrice'] ?? map['highprice']);
            for (final v in <double?>[p, lp, hp]) {
              if (v != null && v > 0) out.add(v);
            }
          }

          // Campos comunes
          for (final key in const ['offers', 'itemOffered', 'mainEntity', 'mainEntityOfPage', '@graph']) {
            if (map.containsKey(key)) collect(map[key]);
          }

          // Recorrido genérico de subestructuras
          for (final v in map.values) {
            if (v is Map || v is List) collect(v);
          }
        }
      }

      collect(data);
    }

    final filtered = out.where((v) => v >= 7 && v <= 500).toList();
    return filtered;
  }

  static double? _extractItempropEuroPrice(String html) {
    final h = html.replaceAll('&nbsp;', ' ').replaceAll('&euro;', '€');

    final m1 = RegExp(
      r"""itemprop=["\']price["\'][^>]*content=["\']([^"\']+)["\']""",
      caseSensitive: false,
    ).firstMatch(h);
    final c1 = m1?.group(1);
    if (c1 != null && c1.trim().isNotEmpty) {
      final v = _parseNumber(c1);
      if (v != null && v >= 7 && v <= 500) return v;
    }

    final m2 = RegExp(
      r"""itemprop=["\']price["\'][^>]*>\s*([0-9][0-9\.,\s]{0,10})\s*(?:€|EUR)""",
      caseSensitive: false,
    ).firstMatch(h);
    final c2 = m2?.group(1);
    if (c2 != null && c2.trim().isNotEmpty) {
      final v = _parseNumber(c2);
      if (v != null && v >= 7 && v <= 500) return v;
    }

    return null;
  }

  static double? _extractBestProductPrice(String html) {
    // 1) Preferimos JSON-LD (schema.org)
    final js = _extractJsonLdEuroPrices(html);
    if (js.isNotEmpty) {
      js.sort();
      return js.first;
    }

    // 2) itemprop="price"
    final ip = _extractItempropEuroPrice(html);
    if (ip != null) return ip;

    // 3) Fallback (muy best-effort): escaneo general,
    // pero si hay señales claras de envío/descuento, no adivinamos.
    if (_looksLikeBadContext(html)) return null;

    final p = _minPrice(html, minValid: 7);
    if (p != null && p >= 7 && p <= 500) return p;
    return null;
  }

  static ({String url, int score})? _bestIMusicProductFromListing(String html, {required List<String> tokens}) {
    if (tokens.isEmpty) return null;

    final hrefRx = RegExp(r'''href=["'](/music/[^"']+)["']''', caseSensitive: false);

    int bestScore = 0;
    String? bestPath;

    for (final m in hrefRx.allMatches(html)) {
      final path = m.group(1);
      if (path == null || path.trim().isEmpty) continue;

      final start = m.start;
      final end = (start + 900) > html.length ? html.length : (start + 900);
      final snippet = html.substring(start, end);

      if (_looksLikeBadContext(snippet)) continue;

      final snNorm = _normKey(snippet);
      final score = _scoreTokens(snNorm, tokens);
      if (score <= 0) continue;

      if (bestPath == null || score > bestScore) {
        bestScore = score;
        bestPath = path;
      }
    }

    if (bestPath == null) return null;
    return (url: 'https://imusic.fi$bestPath', score: bestScore);
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
    final b = barcode.trim();
    if (b.isEmpty) return null;

    final searchUrl = 'https://imusic.fi/page/search?query=$b';
    final res = await _get(searchUrl);
    if (res == null) return null;

    final html = res.body;

    // 1) Preferimos un link directo donde el barcode esté en el path.
    String? productUrl = _firstHref(
      html,
      RegExp('href=["\'](/music/$b/[^"\']+)["\']', caseSensitive: false),
      prefix: 'https://imusic.fi',
    );

    // 2) Fallback: si en el snippet del resultado aparece el barcode, tomamos ese link.
    if (productUrl == null) {
      final hrefRx = RegExp(r'''href=["'](/music/[^"']+)["']''', caseSensitive: false);
      for (final m in hrefRx.allMatches(html)) {
        final path = m.group(1);
        if (path == null || path.trim().isEmpty) continue;
        final start = m.start;
        final end = (start + 900) > html.length ? html.length : (start + 900);
        final snippet = html.substring(start, end);
        if (snippet.contains(b)) {
          productUrl = 'https://imusic.fi$path';
          break;
        }
      }
    }

    // Si no encontramos un producto claro, no adivinamos (evita precios erróneos).
    if (productUrl == null) return null;

    final res2 = await _get(productUrl);
    if (res2 == null) return null;

    final html2 = res2.body;

    // Para barcode, exigimos que la página contenga el barcode.
    if (!html2.contains(b)) return null;

    final price = _extractBestProductPrice(html2);
    if (price == null) return null;

    final can = _extractCanonical(html2) ?? productUrl;

    return StoreOffer(
      store: 'iMusic.fi',
      price: price,
      currency: 'EUR',
      url: can,
    );
  }

  static Future<StoreOffer?> _fetchIMusicQuery(String query) async {
    final qRaw = query.trim();
    if (qRaw.isEmpty) return null;

    final q = Uri.encodeQueryComponent(qRaw);
    final searchUrl = 'https://imusic.fi/page/search?query=$q';
    final res = await _get(searchUrl);
    if (res == null) return null;

    final html = res.body;

    // Elegimos el producto más probable según tokens (evita tomar el primer precio del listado).
    final tokens1 = _tokens(qRaw.replaceAll(RegExp(r'\bvinyl\b', caseSensitive: false), ' '));
    final hit = _bestIMusicProductFromListing(html, tokens: tokens1) ??
        _bestIMusicProductFromListing(html, tokens: _tokens(qRaw));
    if (hit == null) return null;

    final res2 = await _get(hit.url);
    if (res2 == null) return null;

    final html2 = res2.body;
    final price = _extractBestProductPrice(html2);
    if (price == null) return null;

    final can = _extractCanonical(html2) ?? hit.url;

    return StoreOffer(
      store: 'iMusic.fi',
      price: price,
      currency: 'EUR',
      url: can,
    );
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
          // Entramos al producto para obtener un precio fiable (evita tomar precios del listado).
          final res2 = await _get(hit.url);
          if (res2 == null) continue;
          final html2 = res2.body;

          final p2 = _extractBestProductPrice(html2);
          if (p2 == null) continue;

          final can2 = _extractCanonical(html2) ?? hit.url;
          final note2 = _extractMuzikerNote(html2);
          return StoreOffer(store: 'Muziker.fi', price: p2, currency: 'EUR', url: can2, note: note2);
        }
      }
    }

    // ✅ Estrategia 2: búsqueda (best-effort)
    return _fetchMuzikerQuery(fallbackQuery);
  }

  static Future<StoreOffer?> _fetchMuziker(String barcode) async {
    final b = barcode.trim();
    if (b.isEmpty) return null;

    final tries = <String>[
      'https://www.muziker.fi/search?q=$b',
      'https://www.muziker.fi/search?query=$b',
      'https://www.muziker.fi/search/?q=$b',
      'https://www.muziker.fi/haku?q=$b',
      'https://www.muziker.fi/?s=$b',
    ];

    for (final u in tries) {
      final res = await _get(u);
      if (res == null) continue;
      final html = res.body;

      // Si ya es una página de producto (contiene el barcode), intentamos extraer un precio fiable.
      if (html.contains(b)) {
        final p = _extractBestProductPrice(html);
        if (p != null) {
          final can = _extractCanonical(html) ?? u;
          final note = _extractMuzikerNote(html);
          return StoreOffer(store: 'Muziker.fi', price: p, currency: 'EUR', url: can, note: note);
        }
      }

      // En páginas de búsqueda/listado NO tomamos precios del HTML (son propensos a errores).
      // Intentamos entrar a un producto y validar que contenga el barcode.
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

      // Para barcode, exigimos que la página del producto contenga el barcode.
      if (!html2.contains(b)) continue;

      final p2 = _extractBestProductPrice(html2);
      if (p2 == null) continue;

      final can2 = _extractCanonical(html2) ?? candidate;
      final note2 = _extractMuzikerNote(html2);
      return StoreOffer(store: 'Muziker.fi', price: p2, currency: 'EUR', url: can2, note: note2);
    }

    return null;
  }

  static Future<StoreOffer?> _fetchMuzikerQuery(String query) async {
    final qRaw = query.trim();
    if (qRaw.isEmpty) return null;

    final q = Uri.encodeQueryComponent(qRaw);
    final tries = <String>[
      'https://www.muziker.fi/search?q=$q',
      'https://www.muziker.fi/search?query=$q',
      'https://www.muziker.fi/search/?q=$q',
      'https://www.muziker.fi/haku?q=$q',
      'https://www.muziker.fi/?s=$q',
    ];

    final tokens = _tokens(qRaw)
        .where((t) => t.length >= 3 && t != 'vinyl' && t != 'vinyylilevyt' && t != 'lp')
        .toList(growable: false);
    final minScore = tokens.length <= 2 ? 1 : 2;

    for (final u in tries) {
      final res = await _get(u);
      if (res == null) continue;
      final html = res.body;

      // En listados NO tomamos precios directos; entramos a un producto.
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

      if (tokens.isNotEmpty) {
        final score = _scoreTokens(_normKey(html2), tokens);
        if (score < minScore) continue;
      }

      final p2 = _extractBestProductPrice(html2);
      if (p2 == null) continue;

      final can2 = _extractCanonical(html2) ?? candidate;
      final note2 = _extractMuzikerNote(html2);
      return StoreOffer(store: 'Muziker.fi', price: p2, currency: 'EUR', url: can2, note: note2);
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
