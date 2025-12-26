import 'dart:io';

import '../db/vinyl_db.dart';
import 'vinyl_add_service.dart';

class CoverDownloadResult {
  final int total;
  final int downloaded;
  final int skipped;
  const CoverDownloadResult({required this.total, required this.downloaded, required this.skipped});

  String summary() => 'Carátulas: $downloaded descargadas, $skipped omitidas (de $total).';
}

/// Descarga carátulas faltantes para dejarlas offline.
///
/// Reglas:
/// - Si coverPath es local y existe -> ok
/// - Si coverPath es URL -> intenta descargar y guardar local, actualiza coverPath a ruta local
/// - Si coverPath es local pero NO existe, y hay mbid -> construye URL de Cover Art Archive y descarga
class CoverCacheService {
  static Future<CoverDownloadResult> downloadMissingCovers({
    void Function(int done, int total)? onProgress,
    Duration delayBetween = const Duration(milliseconds: 650),
  }) async {
    final db = await VinylDb.instance.db;
    final rows = await db.query('vinyls', columns: ['id', 'coverPath', 'mbid']);

    final candidates = <Map<String, dynamic>>[];

    for (final r in rows) {
      final id = (r['id'] as int?) ?? 0;
      if (id <= 0) continue;

      final cp = (r['coverPath'] as String?)?.trim() ?? '';
      final mbid = (r['mbid'] as String?)?.trim() ?? '';

      final isUrl = cp.startsWith('http://') || cp.startsWith('https://');
      final isLocal = cp.isNotEmpty && !isUrl;
      final localExists = isLocal ? File(cp).existsSync() : false;

      if (isLocal && localExists) continue; // ya está offline

      String? url;
      if (isUrl) {
        url = cp;
      } else if (mbid.isNotEmpty) {
        // Preferimos 500px, con fallback a 250px si falla.
        url = 'https://coverartarchive.org/release-group/$mbid/front-500';
      }
      if (url == null || url.isEmpty) continue;
      candidates.add({'id': id, 'url': url, 'mbid': mbid});
    }

    final total = candidates.length;
    int done = 0;
    int ok = 0;
    int skipped = 0;

    for (final c in candidates) {
      final id = c['id'] as int;
      final url = (c['url'] as String).trim();
      final mbid = (c['mbid'] as String).trim();

      String? local;
      // 1) intentar url directa
      local = await VinylAddService.downloadCoverToLocal(url);
      // 2) fallback a 250 si era 500
      if (local == null && url.contains('/front-500')) {
        local = await VinylAddService.downloadCoverToLocal(url.replaceAll('/front-500', '/front-250'));
      }
      // 3) si venía de mbid y falló (quizás no hay RG), dejamos URL a 250 para que al menos se vea online
      if (local == null && mbid.isNotEmpty) {
        await db.update(
          'vinyls',
          {'coverPath': 'https://coverartarchive.org/release-group/$mbid/front-250'},
          where: 'id = ?',
          whereArgs: [id],
        );
        skipped += 1;
      } else if (local != null) {
        await db.update('vinyls', {'coverPath': local}, where: 'id = ?', whereArgs: [id]);
        ok += 1;
      } else {
        skipped += 1;
      }

      done += 1;
      onProgress?.call(done, total);
      if (delayBetween.inMilliseconds > 0) {
        await Future.delayed(delayBetween);
      }
    }

    return CoverDownloadResult(total: total, downloaded: ok, skipped: skipped);
  }
}
