import '../db/vinyl_db.dart';
import 'price_range_service.dart';

class PriceAlertHit {
  final int alertId;
  final String kind; // 'vinyl' | 'wish'
  final int itemId;
  final String artista;
  final String album;
  final double target;
  final PriceRange range;

  const PriceAlertHit({
    required this.alertId,
    required this.kind,
    required this.itemId,
    required this.artista,
    required this.album,
    required this.target,
    required this.range,
  });
}

/// Servicio para revisar alertas de precio de forma manual (botón “Revisar alertas”).
///
/// Nota: no hace tareas en background; el usuario dispara el check cuando quiere.
class PriceAlertService {
  /// Para evitar spamear alertas, no volvemos a “disparar” una alerta si ya disparó hace poco.
  static const Duration hitCooldown = Duration(hours: 12);

  /// Revisa todas las alertas activas y devuelve los “hits” donde el precio mínimo
  /// de mercado es <= target.
  static Future<List<PriceAlertHit>> checkNow() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final alerts = await VinylDb.instance.getPriceAlerts(onlyActive: true);

    final hits = <PriceAlertHit>[];

    for (final a in alerts) {
      final id = (a['id'] as int?) ?? 0;
      if (id <= 0) continue;

      final kind = (a['kind'] ?? '').toString().trim();
      final itemId = (a['itemId'] as int?) ?? 0;
      if (kind.isEmpty || itemId <= 0) continue;

      final artista = (a['artista'] ?? '').toString().trim();
      final album = (a['album'] ?? '').toString().trim();
      final mbid = (a['mbid'] ?? '').toString().trim();
      final target = (a['target'] as num?)?.toDouble();
      if (artista.isEmpty || album.isEmpty || target == null) continue;

      PriceRange? pr;
      try {
        pr = await PriceRangeService.getRange(
          artist: artista,
          album: album,
          mbid: mbid.isEmpty ? null : mbid,
        );
      } catch (_) {
        pr = null;
      }

      // Actualizamos “lastChecked” aunque no haya precio.
      await VinylDb.instance.updatePriceAlertCheck(
        id: id,
        lastCheckedAt: now,
        lastMin: pr?.min,
        lastMax: pr?.max,
      );

      if (pr == null) continue;

      final min = pr.min;
      final lastHitAt = (a['lastHitAt'] as int?) ?? 0;
      final alreadyHitRecently = lastHitAt > 0 &&
          DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastHitAt)) <= hitCooldown;

      if (min <= target && !alreadyHitRecently) {
        // Marcamos el hit
        await VinylDb.instance.updatePriceAlertCheck(
          id: id,
          lastCheckedAt: now,
          lastMin: pr.min,
          lastMax: pr.max,
          lastHitAt: now,
        );

        hits.add(
          PriceAlertHit(
            alertId: id,
            kind: kind,
            itemId: itemId,
            artista: artista,
            album: album,
            target: target,
            range: pr,
          ),
        );
      }
    }

    return hits;
  }
}
