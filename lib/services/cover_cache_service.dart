import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/vinyl_db.dart';

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
  static String _sanitizeBase(String s) {
    final out = s.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_').trim();
    return out.isEmpty ? 'cover' : out;
  }

  static Future<Directory> _coversDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(dir.path, 'covers'));
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return d;
  }

  /// Guarda una carátula elegida por el usuario dentro de /Documents/covers.
  ///
  /// Devuelve la ruta local final (para guardar en `vinyls.coverPath`).
  static Future<String?> saveCustomCover({
    required int vinylId,
    String? mbid,
    required String sourcePath,
  }) async {
    try {
      final src = File(sourcePath);
      if (!await src.exists()) return null;

      final dir = await _coversDir();
      final base = _sanitizeBase((mbid ?? '').trim().isNotEmpty ? (mbid ?? '') : 'id_$vinylId');

      // Respeta extensión si es conocida; si no, usa jpg.
      final ext0 = p.extension(sourcePath).toLowerCase().replaceAll('.', '');
      final ext = (ext0 == 'png' || ext0 == 'jpg' || ext0 == 'jpeg' || ext0 == 'webp') ? ext0 : 'jpg';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final out = File(p.join(dir.path, '${base}_custom_$ts.$ext'));

      await src.copy(out.path);
      return out.path;
    } catch (_) {
      return null;
    }
  }

  /// Borra un archivo solo si pertenece a la carpeta administrada /Documents/covers.
  /// (Evita borrar rutas del usuario fuera de la app o URLs.)
  static Future<void> deleteIfManaged(String? path) async {
    final raw = (path ?? '').trim();
    if (raw.isEmpty) return;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return;

    try {
      final covers = await _coversDir();
      final candidate = p.normalize(raw);
      final managedRoot = p.normalize(covers.path);
      if (!candidate.startsWith(managedRoot)) return;

      final f = File(raw);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // ignore
    }
  }

  static Future<String?> _downloadWithRetries(
    String url, {
    required String baseName,
    required String suffix,
    int retries = 2,
  }) async {
    final dir = await _coversDir();
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 18));
        if (res.statusCode != 200) {
          continue;
        }
        final ct = (res.headers['content-type'] ?? '').toLowerCase();
        final ext = ct.contains('png') ? 'png' : 'jpg';
        final file = File(p.join(dir.path, '${baseName}_$suffix.$ext'));
        await file.writeAsBytes(res.bodyBytes, flush: true);
        return file.path;
      } catch (_) {
        // retry
      }
    }
    return null;
  }

  static Future<CoverDownloadResult> downloadMissingCovers({
    void Function(int done, int total)? onProgress,
    Duration delayBetween = const Duration(milliseconds: 450),
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

      // Guardamos info suficiente para resolver URLs de 500 y 250.
      candidates.add({'id': id, 'coverPath': cp, 'mbid': mbid});
    }

    final total = candidates.length;
    int done = 0;
    int ok = 0;
    int skipped = 0;

    for (final c in candidates) {
      final id = c['id'] as int;
      final cp = (c['coverPath'] as String).trim();
      final mbid = (c['mbid'] as String).trim();

      final base = _sanitizeBase(mbid.isNotEmpty ? mbid : 'id_$id');

      String? url500;
      String? url250;

      final isUrl = cp.startsWith('http://') || cp.startsWith('https://');
      if (isUrl) {
        // Si ya viene de Cover Art Archive, intentamos ambas resoluciones.
        if (cp.contains('/front-500')) {
          url500 = cp;
          url250 = cp.replaceAll('/front-500', '/front-250');
        } else if (cp.contains('/front-250')) {
          url250 = cp;
          url500 = cp.replaceAll('/front-250', '/front-500');
        } else {
          url500 = cp;
        }
      } else if (mbid.isNotEmpty) {
        url500 = 'https://coverartarchive.org/release-group/$mbid/front-500';
        url250 = 'https://coverartarchive.org/release-group/$mbid/front-250';
      }

      String? localFull;
      String? localThumb;

      // Intentar full (500) primero, con fallback a 250.
      if (url500 != null) {
        localFull = await _downloadWithRetries(url500, baseName: base, suffix: 'full');
      }
      if (localFull == null && url250 != null) {
        // Si no hay 500 o falló, guardamos al menos la 250 como full.
        localFull = await _downloadWithRetries(url250, baseName: base, suffix: 'full');
      }

      // Thumb (250) separado para listas rápidas (si existe URL 250).
      if (url250 != null) {
        localThumb = await _downloadWithRetries(url250, baseName: base, suffix: 'thumb');
      }

      if (localFull != null) {
        await db.update('vinyls', {'coverPath': localFull}, where: 'id = ?', whereArgs: [id]);
        ok += 1;
      } else if (mbid.isNotEmpty) {
        // Si no pudimos descargar, al menos dejamos un URL 250 para que online siga funcionando.
        await db.update(
          'vinyls',
          {'coverPath': 'https://coverartarchive.org/release-group/$mbid/front-250'},
          where: 'id = ?',
          whereArgs: [id],
        );
        skipped += 1;
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
