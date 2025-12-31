import 'store_price_service.dart';

class PriceRange {
  final double min;
  final double median;
  final double max;
  final String currency; // e.g. EUR
  /// Timestamp (ms) when this price was fetched.
  final int fetchedAtMs;

  PriceRange({
    required this.min,
    required this.median,
    required this.max,
    required this.currency,
    required this.fetchedAtMs,
  });

  DateTime get fetchedAt => DateTime.fromMillisecondsSinceEpoch(fetchedAtMs);

  Map<String, dynamic> toJson() => {
        'min': min,
        'median': median,
        'max': max,
        'currency': currency,
        'ts': fetchedAtMs,
      };

  static PriceRange? fromJson(Map<String, dynamic> m) {
    final min = (m['min'] as num?)?.toDouble();
    final max = (m['max'] as num?)?.toDouble();
    final medianRaw = (m['median'] as num?)?.toDouble();
    final currency = (m['currency'] as String?)?.trim();
    final ts = (m['ts'] as num?)?.toInt();
    if (min == null || max == null || currency == null || currency.isEmpty) {
      return null;
    }

    final median = medianRaw ?? ((min + max) / 2.0);

    return PriceRange(
      min: min,
      median: median,
      max: max,
      currency: currency,
      fetchedAtMs: (ts != null && ts > 0) ? ts : DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Rango de precios (mín/mediana/máx) basado en tiendas.
///
/// Importante: en esta app el precio se toma solo desde:
/// - iMusic.fi
/// - Muziker.fi
///
/// Estrategia:
/// - Si hay barcode (EAN/UPC): consulta esas 2 tiendas.
/// - Si no: hace una búsqueda por texto (artista + álbum) (best-effort).
class PriceRangeService {
  static double _median(List<StoreOffer> sorted) {
    if (sorted.isEmpty) return 0;
    final n = sorted.length;
    if (n % 2 == 1) {
      return sorted[n ~/ 2].price;
    }
    final a = sorted[(n ~/ 2) - 1].price;
    final b = sorted[n ~/ 2].price;
    return (a + b) / 2.0;
  }

  static Future<PriceRange?> getRange({
    required String artist,
    required String album,
    String? mbid, // kept for backward compatibility (unused)
    String? barcode,
    bool forceRefresh = false,
  }) async {
    final a = artist.trim();
    final al = album.trim();
    if (a.isEmpty || al.isEmpty) return null;

    final b = (barcode ?? '').trim();
    final offers = b.isNotEmpty
        ? await StorePriceService.fetchOffersByBarcodeCached(
            b,
            forceRefresh: forceRefresh,
          )
        : await StorePriceService.fetchOffersByQueryCached(
            artist: a,
            album: al,
            forceRefresh: forceRefresh,
          );

    if (offers.isEmpty) return null;
    final sorted = [...offers]..sort((x, y) => x.price.compareTo(y.price));
    final min = sorted.first.price;
    final max = sorted.last.price;
    final median = _median(sorted);

    return PriceRange(
      min: min,
      median: median,
      max: max,
      currency: 'EUR',
      fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
