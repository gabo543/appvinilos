import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/vinyl_db.dart';

class BackupService {
  static const _kAuto = 'auto_backup_enabled';
  static const _kFile = 'vinyl_backup.json';

  static Future<bool> isAutoEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAuto) ?? false;
  }

  static Future<void> setAutoEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAuto, value);
  }

  static Future<File> _backupFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _kFile));
  }

  /// Devuelve el archivo de respaldo local (en la carpeta interna de documentos).
  /// Si `ensureLatest` es true, primero guarda el estado actual en ese archivo.
  static Future<File> getLocalBackupFile({bool ensureLatest = true}) async {
    if (ensureLatest) {
      await saveListNow();
    }
    return _backupFile();
  }

  /// Exporta el respaldo a la carpeta pública *Descargas* (Android).
  /// Nota: en Android modernos, el acceso directo a /Download puede estar restringido.
  /// Si falla, se recomienda usar "Compartir backup".
  static Future<File> exportToDownloads() async {
    if (!Platform.isAndroid) {
      throw Exception('Exportar a Descargas está disponible solo en Android.');
    }

    final src = await getLocalBackupFile(ensureLatest: true);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'GaBoLP_backup_$ts.json';

    // Rutas típicas para Descargas en Android.
    final candidates = <String>[
      '/storage/emulated/0/Download',
      '/sdcard/Download',
    ];

    File? lastAttempt;
    Object? lastError;

    for (final dirPath in candidates) {
      try {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;
        final dest = File(p.join(dir.path, fileName));
        await dest.writeAsBytes(await src.readAsBytes(), flush: true);
        return dest;
      } catch (e) {
        lastError = e;
        lastAttempt = File(p.join(dirPath, fileName));
      }
    }

    throw Exception(
      'No pude exportar a Descargas. ${lastAttempt != null ? 'Intenté: ${lastAttempt.path}. ' : ''}'
      'Sugerencia: usa “Compartir backup”. Error: $lastError',
    );
  }

  /// Guarda la lista completa en JSON (incluye `favorite`).
  static Future<void> saveListNow() async {
    final vinyls = await VinylDb.instance.getAll();

    int fav01(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v == 1 ? 1 : 0;
      if (v is bool) return v ? 1 : 0;
      final s = v.toString().trim().toLowerCase();
      return (s == '1' || s == 'true') ? 1 : 0;
    }

    final payload = vinyls
        .map((v) => <String, dynamic>{
              'numero': v['numero'],
              'artista': v['artista'],
              'album': v['album'],
              'year': v['year'],
              'genre': v['genre'],
              'country': v['country'],
              'artistBio': v['artistBio'],
              'coverPath': v['coverPath'],
              'mbid': v['mbid'],
              // ✅ v9: nuevos campos
              'condition': v['condition'],
              'format': v['format'],
              'favorite': fav01(v['favorite']),
            })
        .toList();

    final f = await _backupFile();
    await f.writeAsString(jsonEncode(payload));
  }

  /// Carga la lista desde JSON. Si el backup no trae `favorite`, lo asume 0.
  static Future<void> loadList() async {
    final f = await _backupFile();
    if (!await f.exists()) {
      throw Exception('No existe un respaldo aún.');
    }

    final raw = await f.readAsString();
    final data = jsonDecode(raw);
    if (data is! List) throw Exception('Respaldo inválido.');

    final vinyls = data.map<Map<String, dynamic>>((e) {
      final m = (e as Map).cast<String, dynamic>();
      // Compat: si el backup no trae favorite/condition/format, quedan null/0.
      m['favorite'] = (m['favorite'] == 1 || m['favorite'] == true || m['favorite'] == '1') ? 1 : 0;
      return m;
    }).toList();

    await VinylDb.instance.replaceAll(vinyls);
  }

  static Future<void> autoSaveIfEnabled() async {
    final on = await isAutoEnabled();
    if (on) {
      await saveListNow();
    }
  }
}
