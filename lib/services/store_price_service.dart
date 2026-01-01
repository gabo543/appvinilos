import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class StoreOffer {
  /// Identificador estable para switches en Ajustes.
  /// Ej: "imusic", "muziker", "hhv", "therecordhub", "recordshopx", "levykauppax".
  final String storeId;
  final String store;
  final double price;
  final String currency;
  final String url;
  final String? note;

  const StoreOffer({
    required this.storeId,
    required this.store,
    required this.price,
    required this.currency,
    required this.url,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'storeId': storeId,
        'store': store,
        'price': price,
        'currency': currency,
        'url': url,
        if (note != null) 'note': note,
      };

  static StoreOffer? fromJson(Map<String, dynamic> m) {
    final storeId = (m['storeId'] as String?)?.trim();
    final store = (m['store'] as String?)?.trim();
    final price = (m['price'] as num?)?.toDouble();
    final currency = (m['currency'] as String?)?.trim();
    final url = (m['url'] as String?)?.trim();
    final note = (m['note'] as String?)?.trim();
    if (store == null || store.isEmpty || price == null || currency == null || currency.isEmpty || url == null || url.isEmpty) {
      return null;
    }
    final inferredId = StorePriceService.inferStoreId(store);
    return StoreOffer(
      storeId: (storeId == null || storeId.isEmpty) ? inferredId : storeId,
      store: store,
      price: price,
      currency: currency,
      url: url,
      note: (note == null || note.isEmpty) ? null : note,
    );
  }
}

class StoreSourceDef {
  final String id;
  final String name;
  final String description;
  final bool enabledByDefault;

  const StoreSourceDef({
    required this.id,
    required this.name,
    required this.description,
    this.enabledByDefault = true,
  });
}

/// Switches de tiendas (Ajustes). Persisten en SharedPreferences.
class StoreSourcesSettings {
  static const _prefPrefix = 'price_store_enabled::';

  static const List<StoreSourceDef> stores = <StoreSourceDef>[
    StoreSourceDef(
      id: 'imusic',
      name: 'iMusic.fi',
      description: 'Tienda europea con buen catálogo.',
      enabledByDefault: true,
    ),
    StoreSourceDef(
      id: 'muziker',
      name: 'Muziker.fi',
      description: 'Tienda (Finlandia) con LP/vinyl.',
      enabledByDefault: true,
    ),
    StoreSourceDef(
      id: 'hhv',
      name: 'HHV.de',
      description: 'Tienda alemana con catálogo grande.',
      enabledByDefault: true,
    ),
    StoreSourceDef(
      id: 'therecordhub',
      name: 'TheRecordHub.com',
      description: 'Tienda online (Europa).',
      enabledByDefault: true,
    ),
    StoreSourceDef(
      id: 'levykauppax',
      name: 'LevykauppaX.fi',
      description: 'Finlandia (a veces bloquea consultas automáticas).',
      enabledByDefault: true,
    ),
  ];

  static Future<bool> isEnabled(String storeId) async {
    final prefs = await SharedPreferences.getInstance();
    final def = stores.firstWhere(
      (s) => s.id == storeId,
      orElse: () => const StoreSourceDef(id: 'x', name: 'x', description: '', enabledByDefault: true),
    );
    return prefs.getBool('$_prefPrefix$storeId') ?? def.enabledByDefault;
  }

  static Future<Map<String, bool>> enabledMap() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, bool>{};
    for (final s in stores) {
      out[s.id] = prefs.getBool('$_prefPrefix${s.id}') ?? s.enabledByDefault;
    }
    return out;
  }

  static Future<List<String>> enabledIds() async {
    final m = await enabledMap();
    final out = <String>[];
    for (final s in stores) {
      if (m[s.id] == true) out.add(s.id);
    }
    return out;
  }

  static Future<void> setEnabled(String storeId, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefPrefix$storeId', enabled);
  }

  static Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    for (final s in stores) {
      await prefs.setBool('$_prefPrefix${s.id}', s.enabledByDefault);
    }
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

  // ------------------ Fuentes (enchufables) ------------------
  // Se controlan desde Ajustes con switches.
  //
  // Importante: algunas tiendas pueden bloquear scraping. Por eso el usuario
  // puede desactivar fuentes que no le funcionen bien.

  static String inferStoreId(String storeName) {
    final s = storeName.toLowerCase();
    if (s.contains('imusic')) return 'imusic';
    if (s.contains('muziker')) return 'muziker';
    if (s.contains('hhv')) return 'hhv';
    if (s.contains('therecordhub') || s.contains('record hub')) return 'therecordhub';
    if (s.contains('levykauppa') || s.contains('levykauppax') || s.contains('x.fi')) return 'levykauppax';
    if (s.contains('recordshopx')) return 'recordshopx';
    return s.replaceAll(RegExp(r'[^a-z0-9]+'), '').trim();
  }

  static Future<List<String>> getEnabledStoreIds() => StoreSourcesSettings.enabledIds();

  static Future<void> setStoreEnabled(String id, bool enabled) => StoreSourcesSettings.setEnabled(id, enabled);

  static Future<void> resetStoresToDefault() => StoreSourcesSettings.resetToDefaults();

  static String _sig(List<String> enabledIds) {
    final ids = [...enabledIds]..sort();
    return ids.join(',');
  }

  static List<StoreOffer> _filterAndSort(List<StoreOffer> offers, List<String> enabledIds) {
    final allowed = enabledIds.toSet();
    final out = <StoreOffer>[];
    for (final o in offers) {
      if (allowed.contains(o.storeId)) out.add(o);
    }
    out.sort((a, b) => a.price.compareTo(b.price));
    return out;
  }

  static String _cacheKey(String barcode, String sig) => '$_prefsPrefix${barcode.trim()}::$sig';

  static String _normKey(String s) {
    final t = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t;
  }

  static String _cacheKeyQuery({required String artist, required String album, required String sig}) {
    final k = _normKey('$artist||$album');
    return '$_prefsPrefixQuery$k::$sig';
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

    final enabled = await getEnabledStoreIds();
    final sig = _sig(enabled);
    final key = _cacheKey(b, sig);
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
            final filtered = _filterAndSort(offers, enabled);
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
      final offers = _filterAndSort(await fetchOffersByBarcode(b, enabledStoreIds: enabled), enabled);
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

    final enabled = await getEnabledStoreIds();
    final sig = _sig(enabled);
    final key = _cacheKeyQuery(artist: a, album: al, sig: sig);

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
            final filtered = _filterAndSort(offers, enabled);
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
      final offers = _filterAndSort(await fetchOffersByQuery(artist: a, album: al, enabledStoreIds: enabled), enabled);
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

  static Future<List<StoreOffer>> fetchOffersByBarcode(
    String barcode, {
    List<String>? enabledStoreIds,
  }) async {
    final b = (barcode).trim();
    if (b.isEmpty) return const [];

    final enabled = enabledStoreIds ?? await getEnabledStoreIds();
    if (enabled.isEmpty) return const [];

    final offers = <StoreOffer>[];

    final futures = <Future<StoreOffer?>>[];
    if (enabled.contains('imusic')) futures.add(_fetchIMusic(b));
    if (enabled.contains('muziker')) futures.add(_fetchMuziker(b));
    if (enabled.contains('hhv')) futures.add(_fetchHHVByBarcode(b));
    if (enabled.contains('therecordhub')) futures.add(_fetchRecordHubByBarcode(b));
    if (enabled.contains('levykauppax')) futures.add(_fetchLevykauppaXByBarcode(b));

    final results = await Future.wait<StoreOffer?>(futures);

    for (final r in results) {
      if (r != null) offers.add(r);
    }

    return _filterAndSort(offers, enabled);
  }

  static Future<List<StoreOffer>> fetchOffersByQuery({
    required String artist,
    required String album,
    List<String>? enabledStoreIds,
  }) async {
    final a = artist.trim();
    final al = album.trim();
    if (a.isEmpty || al.isEmpty) return const [];

    final enabled = enabledStoreIds ?? await getEnabledStoreIds();
    if (enabled.isEmpty) return const [];

    final q = '$a $al vinyl'.trim();

    final offers = <StoreOffer>[];

    final futures = <Future<StoreOffer?>>[];
    if (enabled.contains('imusic')) futures.add(_fetchIMusicQuery(q));
    if (enabled.contains('muziker')) {
      futures.add(_fetchMuzikerArtistAlbum(artist: a, album: al, fallbackQuery: q));
    }
    if (enabled.contains('hhv')) futures.add(_fetchHHVByQuery(q, artist: a, album: al));
    if (enabled.contains('therecordhub')) futures.add(_fetchRecordHubByQuery(q, artist: a, album: al));
    if (enabled.contains('levykauppax')) futures.add(_fetchLevykauppaXByQuery(q, artist: a, album: al));

    final results = await Future.wait<StoreOffer?>(futures);
    for (final r in results) {
      if (r != null) offers.add(r);
    }

    return _filterAndSort(offers, enabled);
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
      storeId: 'imusic',
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
      storeId: 'imusic',
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

  static ({String url, double price})? _bestFromMuzikerListingByTokens(String html, {required List<String> tokens}) {
    final t = tokens.where((e) => e.trim().length >= 2).toList(growable: false);
    if (t.isEmpty) return null;

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
      if (path.contains('?')) continue;
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
      final score = _scoreTokens(snNorm, t);
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

  static List<String> _candidateMuzikerProductUrls(String html, {int limit = 8}) {
    final out = <String>[];
    final seen = <String>{};
    final hrefRx = RegExp(r'''href=["'](/[^"']+)["']''', caseSensitive: false);
    for (final m in hrefRx.allMatches(html)) {
      final path = m.group(1);
      if (path == null || path.isEmpty) continue;
      if (!path.startsWith('/')) continue;
      if (path.startsWith('/search') || path.startsWith('/haku')) continue;
      if (path.contains('page=')) continue;
      if (path.contains('?')) continue;
      if (path.endsWith('.png') || path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.webp') || path.endsWith('.svg')) continue;
      if (path.contains('/cookies') || path.contains('/faq') || path.contains('/blog')) continue;
      final url = 'https://www.muziker.fi$path';
      if (seen.add(url)) {
        out.add(url);
        if (out.length >= limit) break;
      }
    }
    return out;
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
          return StoreOffer(storeId: 'muziker', store: 'Muziker.fi', price: p2, currency: 'EUR', url: can2, note: note2);
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
          return StoreOffer(storeId: 'muziker', store: 'Muziker.fi', price: p, currency: 'EUR', url: can, note: note);
        }
      }

      // En páginas de búsqueda/listado NO tomamos precios del HTML (son propensos a errores).
      // Probamos entrar a algunos candidatos hasta encontrar un producto que contenga el barcode.
      final candidates = _candidateMuzikerProductUrls(html, limit: 8);
      for (final candidate in candidates) {
        final res2 = await _get(candidate);
        if (res2 == null) continue;
        final html2 = res2.body;

        // Para barcode, exigimos que la página del producto contenga el barcode.
        if (!html2.contains(b)) continue;

        final p2 = _extractBestProductPrice(html2);
        if (p2 == null) continue;

        final can2 = _extractCanonical(html2) ?? candidate;
        final note2 = _extractMuzikerNote(html2);
        return StoreOffer(storeId: 'muziker', store: 'Muziker.fi', price: p2, currency: 'EUR', url: can2, note: note2);
      }
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

      // En listados NO tomamos precios directos; elegimos el candidato más probable y entramos.
      final hit = _bestFromMuzikerListingByTokens(html, tokens: tokens.isEmpty ? _tokens(qRaw) : tokens);
      final candidates = <String>[];
      if (hit != null) candidates.add(hit.url);
      candidates.addAll(_candidateMuzikerProductUrls(html, limit: 6));

      for (final candidate in candidates.toSet().take(8)) {
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
        return StoreOffer(storeId: 'muziker', store: 'Muziker.fi', price: p2, currency: 'EUR', url: can2, note: note2);
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

  // ------------------ HHV ------------------

  static Future<StoreOffer?> _fetchHHVByBarcode(String barcode) async {
    final b = barcode.trim();
    if (b.isEmpty) return null;
    // HHV no es una tienda enfocada en barcode, pero a veces el EAN está en la ficha.
    return _fetchHHV(query: b, tokens: [b], requireBarcodeOnProduct: true);
  }

  static Future<StoreOffer?> _fetchHHVByQuery(String query, {required String artist, required String album}) async {
    final q = query.trim();
    if (q.isEmpty) return null;
    final tokens = _tokens('$artist $album');
    return _fetchHHV(query: q, tokens: tokens, requireBarcodeOnProduct: false);
  }

  static double? _extractHHVPrice(String html) {
    // HHV suele mostrar "Price: 134,99 €" en la ficha. Preferimos eso para evitar
    // falsos positivos (envío, descuentos, etc.).
    final h = html.replaceAll('&nbsp;', ' ').replaceAll('&euro;', '€');
    final m = RegExp(
      r'''\bPrice:\s*([0-9]{1,3}(?:[\.,][0-9]{2})?)\s*€''',
      caseSensitive: false,
    ).firstMatch(h);
    final g = m?.group(1);
    if (g == null || g.trim().isEmpty) return null;
    final v = _parseNumber(g);
    if (v == null) return null;
    if (v < 3 || v > 3000) return null;
    return v;
  }

  static Future<StoreOffer?> _fetchHHV({
    required String query,
    required List<String> tokens,
    required bool requireBarcodeOnProduct,
  }) async {
    final term = Uri.encodeQueryComponent(query.trim());
    final tries = <String>[
      // Search en el catálogo (incluye Vinyl/CD/Tape). Ejemplo público:
      // https://www.hhv.de/en/catalog/filter/search-S11?af=true&term=...
      'https://www.hhv.de/en/catalog/filter/search-S11?af=true&term=$term',
      'https://www.hhv.de/en/catalog/filter/search-S11?term=$term',
    ];

    for (final u in tries) {
      final res = await _get(u);
      if (res == null) continue;
      final html = res.body;

      final best = _bestLinkFromListing(
        html,
        hrefRx: RegExp(r'''href=["'](/en/records/item/[^"'#?]+)["']''', caseSensitive: false),
        tokens: tokens,
        baseUrl: 'https://www.hhv.de',
        requirePriceHint: true,
        requireVinylHint: false,
      );

      if (best == null) continue;
      final res2 = await _get(best.url);
      if (res2 == null) continue;
      final html2 = res2.body;

      if (requireBarcodeOnProduct && !html2.contains(query.trim())) return null;

      final p2 = _extractHHVPrice(html2) ?? _extractBestProductPrice(html2);
      if (p2 == null) continue;

      final can2 = _extractCanonical(html2) ?? best.url;
      return StoreOffer(storeId: 'hhv', store: 'HHV.de', price: p2, currency: 'EUR', url: can2);
    }

    return null;
  }

  // ------------------ The Record Hub ------------------

  static Future<StoreOffer?> _fetchRecordHubByBarcode(String barcode) async {
    final b = barcode.trim();
    if (b.isEmpty) return null;
    return _fetchRecordHub(query: b, tokens: [b], requireBarcodeOnProduct: true);
  }

  static Future<StoreOffer?> _fetchRecordHubByQuery(String query, {required String artist, required String album}) async {
    final q = query.trim();
    if (q.isEmpty) return null;
    final tokens = _tokens('$artist $album');
    return _fetchRecordHub(query: q, tokens: tokens, requireBarcodeOnProduct: false);
  }

  static Future<StoreOffer?> _fetchRecordHub({
    required String query,
    required List<String> tokens,
    required bool requireBarcodeOnProduct,
  }) async {
    final q = Uri.encodeQueryComponent(query.trim());
    final tries = <String>[
      'https://therecordhub.com/search?q=$q',
      'https://www.therecordhub.com/search?q=$q',
    ];

    for (final u in tries) {
      final res = await _get(u);
      if (res == null) continue;
      final html = res.body;

      final best = _bestLinkFromListing(
        html,
        hrefRx: RegExp(r'''href=["'](/products/[^"'#?]+)["']''', caseSensitive: false),
        tokens: tokens,
        baseUrl: 'https://therecordhub.com',
        requirePriceHint: true,
        requireVinylHint: true,
      );

      if (best == null) continue;
      final res2 = await _get(best.url);
      if (res2 == null) continue;

      final html2 = res2.body;
      if (requireBarcodeOnProduct && !html2.contains(query.trim())) return null;

      final p2 = _extractBestProductPrice(html2);
      if (p2 == null) continue;
      final can2 = _extractCanonical(html2) ?? best.url;
      return StoreOffer(storeId: 'therecordhub', store: 'TheRecordHub.com', price: p2, currency: 'EUR', url: can2);
    }
    return null;
  }

  // ------------------ LevykauppaX ------------------

  static Future<StoreOffer?> _fetchLevykauppaXByBarcode(String barcode) async {
    final b = barcode.trim();
    if (b.isEmpty) return null;
    return _fetchLevykauppaX(query: b, tokens: [b], requireBarcodeOnProduct: true);
  }

  static Future<StoreOffer?> _fetchLevykauppaXByQuery(String query, {required String artist, required String album}) async {
    final q = query.trim();
    if (q.isEmpty) return null;
    final tokens = _tokens('$artist $album');
    return _fetchLevykauppaX(query: q, tokens: tokens, requireBarcodeOnProduct: false);
  }

  static Future<StoreOffer?> _fetchLevykauppaX({
    required String query,
    required List<String> tokens,
    required bool requireBarcodeOnProduct,
  }) async {
    final q = Uri.encodeQueryComponent(query.trim());

    final tries = <String>[
      'https://www.levykauppax.fi/search/?q=$q',
      'https://www.levykauppax.fi/search?q=$q',
      'https://www.levykauppax.fi/?s=$q',
      'https://www.levykauppax.fi/search/?query=$q',
    ];

    for (final u in tries) {
      final res = await _get(u);
      if (res == null) continue;
      final html = res.body;

      // Encontrar una ficha probable (suelen ser /artist/...)
      final best = _bestLinkFromListing(
        html,
        hrefRx: RegExp(r'''href=["'](/artist/[^"'#?]+)["']''', caseSensitive: false),
        tokens: tokens,
        baseUrl: 'https://www.levykauppax.fi',
        requirePriceHint: true,
        requireVinylHint: true,
      );
      if (best == null) continue;

      final res2 = await _get(best.url);
      if (res2 == null) continue;

      final html2 = res2.body;
      if (requireBarcodeOnProduct && !html2.contains(query.trim())) return null;

      final p2 = _extractBestProductPrice(html2);
      if (p2 == null) continue;
      final can2 = _extractCanonical(html2) ?? best.url;
      return StoreOffer(storeId: 'levykauppax', store: 'LevykauppaX.fi', price: p2, currency: 'EUR', url: can2);
    }

    return null;
  }

  // ------------------ Helper: mejor link desde un listado ------------------

  static _ListingHit? _bestLinkFromListing(
    String html, {
    required RegExp hrefRx,
    required List<String> tokens,
    String? baseUrl,
    bool requirePriceHint = true,
    bool requireVinylHint = false,
  }) {
    if (html.trim().isEmpty) return null;
    final normAll = _normKey(html);

    _ListingHit? best;
    int bestScore = -1;

    for (final m in hrefRx.allMatches(html)) {
      final raw = m.group(1);
      if (raw == null || raw.trim().isEmpty) continue;
      var url = raw.trim();
      if (baseUrl != null && url.startsWith('/')) {
        url = '$baseUrl$url';
      }
      if (!url.startsWith('http')) continue;

      final start = m.start;
      final from = (start - 600) < 0 ? 0 : (start - 600);
      final to = (start + 900) > html.length ? html.length : (start + 900);
      final snippet = html.substring(from, to);

      if (requirePriceHint && !snippet.contains('€') && !snippet.toLowerCase().contains('eur')) {
        continue;
      }
      if (requireVinylHint) {
        final sn = snippet.toLowerCase();
        if (!sn.contains('vinyl') && !sn.contains('lp') && !sn.contains('vinyyl')) continue;
      }

      final score = tokens.isEmpty ? 0 : _scoreTokens(normAll, tokens);
      // Ajuste: cuando el snippet menciona tokens, subimos el score.
      final scoreSnippet = tokens.isEmpty ? 0 : _scoreTokens(_normKey(snippet), tokens);
      final total = (score * 2) + (scoreSnippet * 3);

      final listingPrice = _firstPriceInHtml(snippet);

      if (total > bestScore) {
        bestScore = total;
        best = _ListingHit(url: url, listingPrice: listingPrice);
      }
    }

    return best;
  }

  static double? _firstPriceInHtml(String html) {
    // Busca valores como 24,99 € o 24.99 €.
    final m = RegExp(r'([0-9]{1,3}(?:[\.,][0-9]{2})?)\s*(?:€|EUR)', caseSensitive: false)
        .firstMatch(html);
    if (m == null) return null;
    final raw = m.group(1);
    if (raw == null) return null;
    final norm = raw.replaceAll(',', '.').trim();
    final v = double.tryParse(norm);
    if (v == null) return null;
    if (v < 3 || v > 3000) return null;
    return v;
  }

}

class _ListingHit {
  final String url;
  final double? listingPrice;
  const _ListingHit({required this.url, this.listingPrice});
}
