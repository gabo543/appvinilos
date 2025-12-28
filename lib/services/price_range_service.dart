import 'store_price_service.dart';

class PriceRange {
  final double min;
  final double max;
  final String currency; // e.g. EUR
  /// Timestamp (ms) when this price was fetched.
  final int fetchedAtMs;

  PriceRange({
    required this.min,
    required this.max,
    required this.currency,
    required this.fetchedAtMs,
  });

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
      fetchedAtMs:
          (ts != null && ts > 0) ? ts : DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Rango de precios (mín–máx) basado en tiendas europeas.
///
/// Importante: se eliminó Discogs.
///
/// Estrategia:
/// - Si hay barcode (EAN/UPC): consulta iMusic.fi, Muziker.fi y Levykauppa Äx.
/// - Si no: hace una búsqueda por texto (artista + álbum) en esas mismas
///   tiendas (best-effort, menos preciso).
class PriceRangeService {
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
    final min = offers.first.price;
    final max = offers.last.price;

    return PriceRange(
      min: min,
      max: max,
      currency: 'EUR',
      fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
