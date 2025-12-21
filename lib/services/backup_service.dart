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
      m['favorite'] = (m['favorite'] == 1 || m['favorite'] == true) ? 1 : 0;
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
