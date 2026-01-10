import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/vinyl_db.dart';
import '../utils/normalize.dart';
import 'app_theme_service.dart';
import 'view_mode_service.dart';

/// Modos de importación:
/// - merge: fusiona sin duplicar (recomendado)
/// - onlyMissing: solo agrega los que no existan (no actualiza existentes)
/// - replace: borra y reemplaza todo (vinyls + wishlist + trash)
enum BackupImportMode { merge, onlyMissing, replace }

class BackupPreview {
  final int schemaVersion;
  final String? createdAtIso;
  final String? appVersion;
  final int? dbUserVersion;
  final int vinyls;
  final int wishlist;
  final int trash;
  final int likedTracks;
  final int priceAlerts;
  final bool hasPrefs;

  const BackupPreview({
    required this.schemaVersion,
    required this.createdAtIso,
    required this.appVersion,
    required this.dbUserVersion,
    required this.vinyls,
    required this.wishlist,
    required this.trash,
    required this.likedTracks,
    required this.priceAlerts,
    required this.hasPrefs,
  });

  String pretty() {
    final parts = <String>[];
    parts.add('Formato: v$schemaVersion');
    if (createdAtIso != null) parts.add('Creado: $createdAtIso');
    if (appVersion != null) parts.add('App: $appVersion');
    if (dbUserVersion != null) parts.add('DB: v$dbUserVersion');
    parts.add('Vinilos: $vinyls');
    if (wishlist > 0) parts.add('Wishlist: $wishlist');
    if (trash > 0) parts.add('Papelera: $trash');
    if (likedTracks > 0) parts.add('Canciones: $likedTracks');
    if (priceAlerts > 0) parts.add('Alertas: $priceAlerts');
    if (hasPrefs) parts.add('Incluye ajustes');
    return parts.join(' • ');
  }

  static BackupPreview fromDecoded(dynamic decoded) {
    // Compat: backups antiguos eran List o Map{vinyls:[...]}
    if (decoded is List) {
      return BackupPreview(
        schemaVersion: 1,
        createdAtIso: null,
        appVersion: null,
        dbUserVersion: null,
        vinyls: decoded.length,
        wishlist: 0,
        trash: 0,
        likedTracks: 0,
        priceAlerts: 0,
        hasPrefs: false,
      );
    }
    if (decoded is Map) {
      final m = Map<String, dynamic>.from(decoded as Map);
      // schemaVersion puede venir en raíz o dentro de `meta` en backups antiguos.
      final metaSchema = (m['meta'] is Map)
          ? (BackupService._asInt((m['meta'] as Map)['schemaVersion'], fallback: 1) ?? 1)
          : 1;
      final schema = BackupService._asInt(m['schemaVersion'], fallback: metaSchema) ?? metaSchema;

      String? createdAt;
      final ca = m['createdAt'] ?? (m['meta'] is Map ? (m['meta'] as Map)['createdAt'] : null);
      if (ca != null) createdAt = ca.toString();

      String? appVersion;
      final app = m['app'];
      if (app is Map && app['version'] != null) appVersion = app['version'].toString();

      int? dbUserVersion;
      final db = m['db'];
      if (db is Map && db['userVersion'] != null) {
        dbUserVersion = BackupService._asInt(db['userVersion'], fallback: null);
      }

      final vinyls = (m['vinyls'] is List) ? (m['vinyls'] as List).length : (m['payload'] is Map && (m['payload'] as Map)['vinyls'] is List) ? ((m['payload'] as Map)['vinyls'] as List).length : 0;
      final wishlist = (m['wishlist'] is List) ? (m['wishlist'] as List).length : (m['payload'] is Map && (m['payload'] as Map)['wishlist'] is List) ? ((m['payload'] as Map)['wishlist'] as List).length : 0;
      final trash = (m['trash'] is List) ? (m['trash'] as List).length : (m['payload'] is Map && (m['payload'] as Map)['trash'] is List) ? ((m['payload'] as Map)['trash'] as List).length : 0;
      final likedTracks = (m['likedTracks'] is List)
          ? (m['likedTracks'] as List).length
          : (m['payload'] is Map && (m['payload'] as Map)['likedTracks'] is List)
              ? ((m['payload'] as Map)['likedTracks'] as List).length
              : 0;

      final priceAlerts = (m['priceAlerts'] is List)
          ? (m['priceAlerts'] as List).length
          : (m['payload'] is Map && (m['payload'] as Map)['priceAlerts'] is List)
              ? ((m['payload'] as Map)['priceAlerts'] as List).length
              : 0;

      final hasPrefs = (m['prefs'] is Map) || (m['payload'] is Map && (m['payload'] as Map)['prefs'] is Map);

      return BackupPreview(
        schemaVersion: schema,
        createdAtIso: createdAt,
        appVersion: appVersion,
        dbUserVersion: dbUserVersion,
        vinyls: vinyls,
        wishlist: wishlist,
        trash: trash,
        likedTracks: likedTracks,
        priceAlerts: priceAlerts,
        hasPrefs: hasPrefs,
      );
    }

    return const BackupPreview(
      schemaVersion: 0,
      createdAtIso: null,
      appVersion: null,
      dbUserVersion: null,
      vinyls: 0,
      wishlist: 0,
      trash: 0,
      likedTracks: 0,
      priceAlerts: 0,
      hasPrefs: false,
    );
  }
}

class BackupImportResult {
  int insertedVinyls = 0;
  int updatedVinyls = 0;
  int skippedVinyls = 0;
  int invalidVinyls = 0;

  int insertedWishlist = 0;
  int updatedWishlist = 0;
  int skippedWishlist = 0;
  int invalidWishlist = 0;

  int insertedTrash = 0;
  int updatedTrash = 0;
  int skippedTrash = 0;
  int invalidTrash = 0;

  int insertedLikedTracks = 0;
  int updatedLikedTracks = 0;
  int skippedLikedTracks = 0;
  int invalidLikedTracks = 0;

  int insertedPriceAlerts = 0;
  int updatedPriceAlerts = 0;
  int skippedPriceAlerts = 0;
  int invalidPriceAlerts = 0;

  bool prefsApplied = false;

  String summary() {
    String line(String label, int ins, int upd, int sk, int bad) {
      final parts = <String>[];
      if (ins > 0) parts.add('+$ins');
      if (upd > 0) parts.add('~$upd');
      if (sk > 0) parts.add('=$sk');
      if (bad > 0) parts.add('!$bad');
      final tail = parts.isEmpty ? 'sin cambios' : parts.join(' ');
      return '$label: $tail';
    }

    final s = <String>[
      line('Vinilos', insertedVinyls, updatedVinyls, skippedVinyls, invalidVinyls),
      if (insertedWishlist + updatedWishlist + skippedWishlist + invalidWishlist > 0)
        line('Wishlist', insertedWishlist, updatedWishlist, skippedWishlist, invalidWishlist),
      if (insertedTrash + updatedTrash + skippedTrash + invalidTrash > 0)
        line('Papelera', insertedTrash, updatedTrash, skippedTrash, invalidTrash),
      if (insertedLikedTracks + updatedLikedTracks + skippedLikedTracks + invalidLikedTracks > 0)
        line('Canciones', insertedLikedTracks, updatedLikedTracks, skippedLikedTracks, invalidLikedTracks),
      if (insertedPriceAlerts + updatedPriceAlerts + skippedPriceAlerts + invalidPriceAlerts > 0)
        line('Alertas', insertedPriceAlerts, updatedPriceAlerts, skippedPriceAlerts, invalidPriceAlerts),
      if (prefsApplied) 'Ajustes: importados',
    ];
    return s.join(' • ');
  }
}

class BackupService {
  // Prefs
  static const _kAuto = 'auto_backup_enabled';

  // Archivo "principal" (último backup)
  static const _kFile = 'vinyl_backup.json';

  // Carpeta y rotación
  static const _kDir = 'backups';
  static const int _kKeep = 10;

  // Formato del backup (independiente de la versión de la DB)
  static const int _schemaVersion = 4; // ✅ v4: incluye liked_tracks + price_alerts

  static Future<bool> isAutoEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAuto) ?? false;
  }

  static Future<void> setAutoEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAuto, v);
  }

  static Future<Directory> _docsDir() async => getApplicationDocumentsDirectory();

  static Future<File> _backupFile() async {
    final dir = await _docsDir();
    return File(p.join(dir.path, _kFile));
  }

  static Future<Directory> _backupDir() async {
    final dir = await _docsDir();
    final out = Directory(p.join(dir.path, _kDir));
    if (!await out.exists()) await out.create(recursive: true);
    return out;
  }

  static String _tsFileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    final y = now.year.toString().padLeft(4, '0');
    final mo = two(now.month);
    final d = two(now.day);
    final h = two(now.hour);
    final mi = two(now.minute);
    final s = two(now.second);
    return 'GaBoLP_backup_${y}${mo}${d}_${h}${mi}${s}.json';
  }

  static int _fav01(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v == 1 ? 1 : 0;
    if (v is bool) return v ? 1 : 0;
    final s = v.toString().trim().toLowerCase();
    return (s == '1' || s == 'true') ? 1 : 0;
  }

  static int? _asInt(dynamic v, {int? fallback}) {
    if (v == null) return fallback;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? fallback;
  }

  static bool? _asBool(dynamic v, {bool? fallback}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    if (s == '1' || s == 'true' || s == 'yes') return true;
    if (s == '0' || s == 'false' || s == 'no') return false;
    return fallback;
  }

  static String _trim(dynamic v) => (v ?? '').toString().trim();

  /// Normaliza la carátula al importar/restaurar.
  ///
  /// - Si es URL (http/https): se respeta.
  /// - Si es path local y existe: se respeta.
  /// - Si NO existe (típico tras reinstalar/cambiar de teléfono):
  ///   usa Cover Art Archive por `mbid` (release-group).
  static String? _normalizeCoverPathForImport(dynamic rawCoverPath, dynamic rawMbid) {
    final cp = _trim(rawCoverPath);
    final mbid = _trim(rawMbid);
    if (cp.isEmpty) {
      if (mbid.isNotEmpty) {
        return 'https://coverartarchive.org/release-group/$mbid/front-250';
      }
      return null;
    }

    if (cp.startsWith('http://') || cp.startsWith('https://')) return cp;

    try {
      if (File(cp).existsSync()) return cp;
    } catch (_) {
      // ignorar
    }

    if (mbid.isNotEmpty) {
      return 'https://coverartarchive.org/release-group/$mbid/front-250';
    }
    return null;
  }

  // ---------------- ORDEN Artista.Album (v11) ----------------
  static String _makeArtistKey(String artista) {
    var out = artista.toLowerCase().trim();
    const rep = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
      'ñ': 'n',
    };
    rep.forEach((k, v) => out = out.replaceAll(k, v));
    out = out.replaceAll(RegExp(r'[^a-z0-9# ]'), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }

  static Future<int> _getOrCreateArtistNo(
    DatabaseExecutor ex,
    String artistKey, {
    int? preferredNo,
  }) async {
    final key = artistKey.trim();
    if (key.isEmpty) return 0;

    final rows = await ex.query(
      'artist_orders',
      columns: ['artistNo'],
      where: 'artistKey = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isNotEmpty) return BackupService._asInt(rows.first['artistNo'], fallback: 0) ?? 0;

    int chosen = 0;

    if (preferredNo != null && preferredNo > 0) {
      final used = await ex.query(
        'artist_orders',
        columns: ['artistKey'],
        where: 'artistNo = ?',
        whereArgs: [preferredNo],
        limit: 1,
      );
      if (used.isEmpty) chosen = preferredNo;
    }

    if (chosen == 0) {
      final r = await ex.rawQuery('SELECT MAX(artistNo) as m FROM artist_orders');
      final m = BackupService._asInt(r.first['m'], fallback: 0) ?? 0;
      chosen = m + 1;
    }

    await ex.insert(
      'artist_orders',
      {'artistKey': key, 'artistNo': chosen},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    return chosen;
  }

  static Future<int> _nextAlbumNo(DatabaseExecutor ex, int artistNo) async {
    if (artistNo <= 0) return 0;
    final r = await ex.rawQuery(
      'SELECT MAX(albumNo) as m FROM vinyls WHERE artistNo = ?',
      [artistNo],
    );
    final m = _asInt(r.first['m'], fallback: 0) ?? 0;
    return m + 1;
  }



  /// Devuelve el archivo local principal.
  /// Si ensureLatest=true, guarda un backup antes de devolverlo.
  static Future<File> getLocalBackupFile({bool ensureLatest = false}) async {
    if (ensureLatest) await saveListNow(); // alias al backup completo
    return _backupFile();
  }

  /// Genera el JSON del backup completo (vinyls + wishlist + trash + prefs).
  static Future<Map<String, dynamic>> _buildBackupObject() async {
    final now = DateTime.now();
    final db = await VinylDb.instance.db;

    final userV = await db.rawQuery('PRAGMA user_version;');
    final userVersion = _asInt(userV.first.values.first, fallback: null);

    final vinyls = await VinylDb.instance.getAll();
    final wishlist = await VinylDb.instance.getWishlist();
    final trash = await VinylDb.instance.getTrash();
    List<Map<String, dynamic>> likedTracks = <Map<String, dynamic>>[];
    try {
      likedTracks = await db.query('liked_tracks');
    } catch (_) {
      // DB antigua o tabla no disponible (compat).
      likedTracks = <Map<String, dynamic>>[];
    }

    List<Map<String, dynamic>> priceAlerts = const [];
    try {
      priceAlerts = await db.query('price_alerts');
    } catch (_) {
      // DB antigua o tabla no disponible (compat).
    }

    // prefs relevantes
    final prefs = await SharedPreferences.getInstance();
    final prefsOut = <String, dynamic>{};

    // Auto-backup
    prefsOut[_kAuto] = prefs.getBool(_kAuto) ?? false;

    // Tema/contraste
    prefsOut['app_theme_variant'] = prefs.getInt('app_theme_variant');
    prefsOut['app_text_intensity'] = prefs.getInt('app_text_intensity');
    prefsOut['app_bg_level'] = prefs.getInt('app_bg_level');
    prefsOut['app_card_level'] = prefs.getInt('app_card_level');
    prefsOut['app_card_border_style'] = prefs.getInt('app_card_border_style');

    // Vista (3 modos) + compat
    prefsOut['vinyl_view_mode'] = prefs.getInt('vinyl_view_mode');
    prefsOut['vinyl_view_grid'] = prefs.getBool('vinyl_view_grid');

    // Normaliza favorite -> 0/1
    List<Map<String, dynamic>> normVinyls = vinyls.map((v) {
      final m = Map<String, dynamic>.from(v);
      m['favorite'] = _fav01(m['favorite']);
      return m;
    }).toList();

    return {
      'schemaVersion': _schemaVersion,
      'createdAt': now.toIso8601String(),
      'app': (() {
        const v = String.fromEnvironment('APP_VERSION');
        final out = <String, dynamic>{'name': 'GaBoLP'};
        if (v.trim().isNotEmpty) out['version'] = v.trim();
        return out;
      }()),
      'db': {
        'userVersion': userVersion,
      },
      'counts': {
        'vinyls': normVinyls.length,
        'wishlist': wishlist.length,
        'trash': trash.length,
        'likedTracks': likedTracks.length,
        'priceAlerts': priceAlerts.length,
      },
      'prefs': prefsOut..removeWhere((k, v) => v == null),
      'vinyls': normVinyls,
      'wishlist': wishlist,
      'trash': trash,
      'likedTracks': likedTracks,
      'priceAlerts': priceAlerts,
    };
  }

  /// Guarda un backup completo:
  /// - Actualiza el archivo principal (vinyl_backup.json)
  /// - Crea un backup con timestamp en /backups/
  /// - Mantiene rotación (últimos N)
  static Future<File> saveBackupNow({bool rotate = true}) async {
    final obj = await _buildBackupObject();
    final txt = const JsonEncoder.withIndent('  ').convert(obj);

    // Principal
    final main = await _backupFile();
    await main.writeAsString(txt, flush: true);

    // Rotado
    if (rotate) {
      final dir = await _backupDir();
      final name = _tsFileName(DateTime.now());
      final rotated = File(p.join(dir.path, name));
      await rotated.writeAsString(txt, flush: true);
      await _rotateBackups(dir);
    }

    return main;
  }

  static Future<void> _rotateBackups(Directory dir) async {
    try {
      final files = await dir
          .list()
          .where((e) => e is File && e.path.toLowerCase().endsWith('.json'))
          .cast<File>()
          .toList();

      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync())); // newest first

      for (var i = _kKeep; i < files.length; i++) {
        try {
          await files[i].delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Alias histórico: antes solo guardaba "lista".
  /// Ahora guarda el backup completo (lista + wishlist + papelera + ajustes).
  static Future<void> saveListNow() async {
    await saveBackupNow(rotate: true);
  }

  /// Previsualiza un backup desde un archivo.
  static Future<BackupPreview> peekBackupFile(File f) async {
    final txt = await f.readAsString();
    final decoded = jsonDecode(txt);
    return BackupPreview.fromDecoded(decoded);
  }

  static Future<File> _writeTempBytes(Uint8List bytes, {String fileName = _kFile}) async {
    final dir = await getTemporaryDirectory();
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');
    final f = File(p.join(dir.path, safeName));
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  /// (Android/iOS/Desktop) Abre el selector del sistema para elegir un backup.
  /// Esto evita el error "Permission denied (errno = 13)" al intentar leer /Download directamente.
  /// Devuelve un archivo legible por la app (si el picker entrega bytes, se copia a un temp local).
  static Future<File?> pickBackupFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final pf = result.files.single;

    if (pf.bytes != null) {
      return _writeTempBytes(pf.bytes!, fileName: pf.name);
    }
    if (pf.path != null && pf.path!.isNotEmpty) {
      return File(pf.path!);
    }
    return null;
  }

  /// Exporta el backup con un diálogo "Guardar como".
  /// El usuario puede elegir "Descargas" sin que la app toque /Download directo.
  /// Devuelve la ruta/URI devuelta por el sistema (puede ser null si el usuario cancela).
  static Future<String?> exportToDownloads({String? suggestedName}) async {
    // Asegura backup actualizado
    final src = await getLocalBackupFile(ensureLatest: true);
    final bytes = await src.readAsBytes();

    final name = (suggestedName == null || suggestedName.trim().isEmpty)
        ? _tsFileName(DateTime.now())
        : suggestedName.trim();

    return FilePicker.platform.saveFile(
      dialogTitle: 'Guardar backup',
      fileName: name,
      bytes: bytes,
      allowedExtensions: const ['json'],
    );
  }

  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  static List _asList(dynamic v) {
    if (v is List) return v;
    return const [];
  }

  static Map<String, dynamic>? _normVinyl(dynamic raw) {
    final m = _asMap(raw);
    if (m == null) return null;
    final artista = _trim(m['artista']);
    final album = _trim(m['album']);
    if (artista.isEmpty || album.isEmpty) return null;

    final out = <String, dynamic>{
      'numero': _asInt(m['numero'], fallback: 0) ?? 0,
      'artistKey': _trim(m['artistKey']),
      'artistNo': _asInt(m['artistNo'], fallback: 0) ?? 0,
      'albumNo': _asInt(m['albumNo'], fallback: 0) ?? 0,
      'artista': artista,
      'album': album,
      'year': m['year']?.toString().trim(),
      'genre': m['genre']?.toString().trim(),
      'country': m['country']?.toString().trim(),
      'artistBio': m['artistBio']?.toString().trim(),
      'coverPath': m['coverPath']?.toString().trim(),
      'mbid': m['mbid']?.toString().trim(),
      'barcode': m['barcode']?.toString().trim(),
      'condition': m['condition']?.toString().trim(),
      'format': m['format']?.toString().trim(),
      'favorite': _fav01(m['favorite']),
    };

    // Limpia strings vacíos a null (reduce ruido)
    out.removeWhere((k, v) => v is String && v.trim().isEmpty);
    return out;
  }

  static Map<String, dynamic>? _normWish(dynamic raw) {
    final m = _asMap(raw);
    if (m == null) return null;
    final artista = _trim(m['artista']);
    final album = _trim(m['album']);
    if (artista.isEmpty || album.isEmpty) return null;

    final createdAt = _asInt(m['createdAt'], fallback: DateTime.now().millisecondsSinceEpoch) ?? DateTime.now().millisecondsSinceEpoch;

    final out = <String, dynamic>{
      'artista': artista,
      'album': album,
      'year': m['year']?.toString().trim(),
      'cover250': m['cover250']?.toString().trim(),
      'cover500': m['cover500']?.toString().trim(),
      'artistId': m['artistId']?.toString().trim(),
      'status': m['status']?.toString().trim(),
      'barcode': m['barcode']?.toString().trim(),
      'createdAt': createdAt,
    };
    out.removeWhere((k, v) => v is String && v.trim().isEmpty);
    return out;
  }

  static Map<String, dynamic>? _normTrash(dynamic raw) {
    final m = _asMap(raw);
    if (m == null) return null;
    final artista = _trim(m['artista']);
    final album = _trim(m['album']);
    if (artista.isEmpty || album.isEmpty) return null;

    final deletedAt = _asInt(m['deletedAt'], fallback: DateTime.now().millisecondsSinceEpoch) ?? DateTime.now().millisecondsSinceEpoch;

    final out = <String, dynamic>{
      'vinylId': _asInt(m['vinylId'], fallback: null),
      'numero': _asInt(m['numero'], fallback: 0) ?? 0,
      'artistKey': _trim(m['artistKey']),
      'artistNo': _asInt(m['artistNo'], fallback: 0) ?? 0,
      'albumNo': _asInt(m['albumNo'], fallback: 0) ?? 0,
      'artista': artista,
      'album': album,
      'year': m['year']?.toString().trim(),
      'genre': m['genre']?.toString().trim(),
      'country': m['country']?.toString().trim(),
      'artistBio': m['artistBio']?.toString().trim(),
      'coverPath': m['coverPath']?.toString().trim(),
      'mbid': m['mbid']?.toString().trim(),
      'barcode': m['barcode']?.toString().trim(),
      'condition': m['condition']?.toString().trim(),
      'format': m['format']?.toString().trim(),
      'favorite': _fav01(m['favorite']),
      'deletedAt': deletedAt,
    };
    out.removeWhere((k, v) => v is String && v.trim().isEmpty);
    return out;
  }

  static Map<String, dynamic>? _normLikedTrack(dynamic raw) {
    final m = _asMap(raw);
    if (m == null) return null;

    final artista = _trim(m['artista']);
    final album = _trim(m['album']);
    final releaseGroupId = _trim(m['releaseGroupId']);
    final trackTitle = _trim(m['trackTitle']);

    if (artista.isEmpty || album.isEmpty || releaseGroupId.isEmpty || trackTitle.isEmpty) return null;

    final artistKeyIn = _trim(m['artistKey']);
    final artistKey = artistKeyIn.isNotEmpty ? artistKeyIn : _makeArtistKey(artista);

    final trackKeyIn = _trim(m['trackKey']);
    final trackKey = trackKeyIn.isNotEmpty ? trackKeyIn : normalizeKey(trackTitle);

    final createdAt = _asInt(m['createdAt'], fallback: DateTime.now().millisecondsSinceEpoch) ?? DateTime.now().millisecondsSinceEpoch;

    final out = <String, dynamic>{
      'artistKey': artistKey,
      'artista': artista,
      'album': album,
      'year': m['year']?.toString().trim(),
      'releaseGroupId': releaseGroupId,
      'cover250': m['cover250']?.toString().trim(),
      'cover500': m['cover500']?.toString().trim(),
      'trackTitle': trackTitle,
      'trackKey': trackKey,
      'trackNo': _asInt(m['trackNo'], fallback: null),
      'createdAt': createdAt,
    };

    out.removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));
    return out;
  }


  static double? _asDouble(dynamic v, {double? fallback}) {
    if (v == null) return fallback;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    final s = v.toString().trim().replaceAll(',', '.');
    return double.tryParse(s) ?? fallback;
  }

  static Map<String, dynamic>? _normPriceAlert(dynamic raw) {
    final m = _asMap(raw);
    if (m == null) return null;

    var kind = _trim(m['kind']).toLowerCase();
    if (kind == 'wishlist') kind = 'wish';
    if (kind != 'vinyl' && kind != 'wish') return null;

    final artista = _trim(m['artista']);
    final album = _trim(m['album']);
    if (artista.isEmpty || album.isEmpty) return null;

    final target = _asDouble(m['target'], fallback: null);
    if (target == null) return null;

    final currency = _trim(m['currency']);
    final isActive = _asInt(m['isActive'], fallback: 1) ?? 1;

    final createdAt = _asInt(m['createdAt'], fallback: DateTime.now().millisecondsSinceEpoch) ?? DateTime.now().millisecondsSinceEpoch;

    final out = <String, dynamic>{
      'kind': kind,
      // itemId NO es estable entre dispositivos; se recalcula al importar.
      'artista': artista,
      'album': album,
      'mbid': _trim(m['mbid']),
      'target': target,
      'currency': currency.isEmpty ? 'EUR' : currency,
      'isActive': (isActive == 1) ? 1 : 0,
      'createdAt': createdAt,
      'lastCheckedAt': _asInt(m['lastCheckedAt'], fallback: null),
      'lastHitAt': _asInt(m['lastHitAt'], fallback: null),
      'lastMin': _asDouble(m['lastMin'], fallback: null),
      'lastMax': _asDouble(m['lastMax'], fallback: null),
    };

    out.removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));
    return out;
  }

  static Future<void> _applyPrefs(Map<String, dynamic> prefsIn) async {
    final prefs = await SharedPreferences.getInstance();

    // bool
    final auto = _asBool(prefsIn[_kAuto], fallback: null);
    if (auto != null) await prefs.setBool(_kAuto, auto);

    final modeIdx = _asInt(prefsIn['vinyl_view_mode'], fallback: null);
    if (modeIdx != null) await prefs.setInt('vinyl_view_mode', modeIdx);

    final grid = _asBool(prefsIn['vinyl_view_grid'], fallback: null);
    if (grid != null) await prefs.setBool('vinyl_view_grid', grid);

    // Si solo viene uno de los dos, mantenlos sincronizados.
    if (modeIdx != null && grid == null) {
      await prefs.setBool('vinyl_view_grid', modeIdx == VinylViewMode.grid.index);
    }
    if (grid != null && modeIdx == null) {
      await prefs.setInt('vinyl_view_mode', grid ? VinylViewMode.grid.index : VinylViewMode.list.index);
    }

    // ints
    Future<void> setIntIf(String key) async {
      final v = _asInt(prefsIn[key], fallback: null);
      if (v != null) await prefs.setInt(key, v);
    }

    await setIntIf('app_theme_variant');
    await setIntIf('app_text_intensity');
    await setIntIf('app_bg_level');
    await setIntIf('app_card_level');
    await setIntIf('app_card_border_style');

    // refresca notifiers
    await AppThemeService.load();
    await ViewModeService.load();
  }

  /// Importa desde un archivo (JSON) de forma segura:
  /// - valida formato (soporta backups antiguos)
  /// - aplica en transacción (rollback si falla)
  /// - evita duplicados (merge/onlyMissing)
  /// - opcionalmente copia el archivo a la ubicación local
  static Future<BackupImportResult> importFromFile(
    File f, {
    BackupImportMode mode = BackupImportMode.merge,
    bool applyPrefs = true,
    bool copyToLocal = false,
  }) async {
    final txt = await f.readAsString();

    dynamic decoded;
    try {
      decoded = jsonDecode(txt);
    } catch (e) {
      throw Exception('El archivo no parece ser un JSON válido: $e');
    }

    // Extrae payload (compat)
    Map<String, dynamic>? m = _asMap(decoded);

    List vinylsRaw = [];
    List wishRaw = [];
    List trashRaw = [];
    List likedRaw = [];
    List priceRaw = [];
    Map<String, dynamic> prefsIn = {};

    if (decoded is List) {
      vinylsRaw = decoded;
    } else if (m != null) {
      if (m['payload'] is Map) {
        final payload = Map<String, dynamic>.from(m['payload'] as Map);
        vinylsRaw = _asList(payload['vinyls']);
        wishRaw = _asList(payload['wishlist']);
        trashRaw = _asList(payload['trash']);
        likedRaw = _asList(payload['likedTracks']);
        priceRaw = _asList(payload['priceAlerts']);
        final pmap = _asMap(payload['prefs']);
        if (pmap != null) prefsIn = pmap;
      } else {
        vinylsRaw = _asList(m['vinyls']);
        wishRaw = _asList(m['wishlist']);
        trashRaw = _asList(m['trash']);
        likedRaw = _asList(m['likedTracks']);
        priceRaw = _asList(m['priceAlerts']);
        final pmap = _asMap(m['prefs']);
        if (pmap != null) prefsIn = pmap;
      }

      // compat: backups viejos {vinyls:[...]} sin wishlist/trash
      if (vinylsRaw.isEmpty && m['vinyls'] is List) {
        vinylsRaw = _asList(m['vinyls']);
      }
    }

    if (vinylsRaw.isEmpty && wishRaw.isEmpty && trashRaw.isEmpty && likedRaw.isEmpty && priceRaw.isEmpty) {
      throw Exception('El archivo no tiene datos que importar (vinyls/wishlist/trash/canciones/alertas).');
    }

    final vinyls = <Map<String, dynamic>>[];
    final wishlist = <Map<String, dynamic>>[];
    final trash = <Map<String, dynamic>>[];
    final likedTracks = <Map<String, dynamic>>[];
    final priceAlerts = <Map<String, dynamic>>[];

    final result = BackupImportResult();

    final seenVinyl = <String>{};
    final seenWish = <String>{};
    final seenTrash = <String>{};
    final seenLiked = <String>{};
    final seenPrice = <String>{};

    String _k(String artista, String album) => '${artista.trim().toLowerCase()}|${album.trim().toLowerCase()}';
    String _lk(String rg, String tk) => '${rg.trim().toLowerCase()}|${tk.trim().toLowerCase()}';
    String _pk(String kind, String artista, String album, String mbid) {
      final k = kind.trim().toLowerCase();
      final id = mbid.trim().toLowerCase();
      if (id.isNotEmpty) return '$k|$id';
      return '$k|${artista.trim().toLowerCase()}|${album.trim().toLowerCase()}';
    }

    for (final it in vinylsRaw) {
      final v = _normVinyl(it);
      if (v == null) {
        result.invalidVinyls++;
      } else {
        final k = _k(v['artista'].toString(), v['album'].toString());
        if (seenVinyl.contains(k)) {
          result.invalidVinyls++;
        } else {
          seenVinyl.add(k);
          vinyls.add(v);
        }
      }
    }

    for (final it in wishRaw) {
      final w = _normWish(it);
      if (w == null) {
        result.invalidWishlist++;
      } else {
        final k = _k(w['artista'].toString(), w['album'].toString());
        if (seenWish.contains(k)) {
          result.invalidWishlist++;
        } else {
          seenWish.add(k);
          wishlist.add(w);
        }
      }
    }

    for (final it in trashRaw) {
      final t = _normTrash(it);
      if (t == null) {
        result.invalidTrash++;
      } else {
        final k = _k(t['artista'].toString(), t['album'].toString());
        if (seenTrash.contains(k)) {
          result.invalidTrash++;
        } else {
          seenTrash.add(k);
          trash.add(t);
        }
      }
    }

    for (final it in likedRaw) {
      final lt = _normLikedTrack(it);
      if (lt == null) {
        result.invalidLikedTracks++;
      } else {
        final k = _lk(lt['releaseGroupId'].toString(), lt['trackKey'].toString());
        if (seenLiked.contains(k)) {
          result.invalidLikedTracks++;
        } else {
          seenLiked.add(k);
          likedTracks.add(lt);
        }
      }
    }
    for (final it in priceRaw) {
      final pa = _normPriceAlert(it);
      if (pa == null) {
        result.invalidPriceAlerts++;
      } else {
        final k = _pk(pa['kind'].toString(), pa['artista'].toString(), pa['album'].toString(), (pa['mbid'] ?? '').toString());
        if (seenPrice.contains(k)) {
          result.invalidPriceAlerts++;
        } else {
          seenPrice.add(k);
          priceAlerts.add(pa);
        }
      }
    }


    final db = await VinylDb.instance.db;

    await db.transaction((txn) async {
      // -------- Helpers (Price Alerts) --------
      Future<int?> _findVinylId(String mbid, String artista, String album) async {
        final id = mbid.trim();
        if (id.isNotEmpty) {
          final rows = await txn.query(
            'vinyls',
            columns: ['id'],
            where: 'TRIM(mbid) = TRIM(?)',
            whereArgs: [id],
            limit: 1,
          );
          if (rows.isNotEmpty) return _asInt(rows.first['id'], fallback: null);
        }

        final rows = await txn.query(
          'vinyls',
          columns: ['id'],
          where: 'artista = ? COLLATE NOCASE AND album = ? COLLATE NOCASE',
          whereArgs: [artista.trim(), album.trim()],
          limit: 1,
        );
        if (rows.isNotEmpty) return _asInt(rows.first['id'], fallback: null);
        return null;
      }

      Future<int?> _findWishId(String artista, String album) async {
        final rows = await txn.query(
          'wishlist',
          columns: ['id'],
          where: 'artista = ? COLLATE NOCASE AND album = ? COLLATE NOCASE',
          whereArgs: [artista.trim(), album.trim()],
          limit: 1,
        );
        if (rows.isNotEmpty) return _asInt(rows.first['id'], fallback: null);
        return null;
      }

      Future<void> _upsertPriceAlert(Map<String, dynamic> pa, BackupImportMode mode) async {
        final kind = (pa['kind'] ?? '').toString().trim();
        final artista = _trim(pa['artista']);
        final album = _trim(pa['album']);
        final mbid = _trim(pa['mbid']);

        int? itemId;
        if (kind == 'vinyl') {
          itemId = await _findVinylId(mbid, artista, album);
        } else if (kind == 'wish') {
          itemId = await _findWishId(artista, album);
        } else {
          result.invalidPriceAlerts++;
          return;
        }

        if (itemId == null || itemId <= 0) {
          // No hay item asociado en esta DB (por ej. alerta de wish pero no existe wish).
          result.skippedPriceAlerts++;
          return;
        }

        List<Map<String, Object?>> existingRows = const [];
        try {
          existingRows = await txn.query(
            'price_alerts',
            columns: [
              'id',
              'createdAt',
              'lastCheckedAt',
              'lastHitAt',
              'lastMin',
              'lastMax',
            ],
            where: 'kind = ? AND itemId = ?',
            whereArgs: [kind, itemId],
            limit: 1,
          );
        } catch (_) {
          // tabla no existe / DB antigua (compat)
          result.invalidPriceAlerts++;
          return;
        }

        final payload = <String, dynamic>{
          'kind': kind,
          'itemId': itemId,
          'artista': artista,
          'album': album,
          'mbid': mbid.isEmpty ? null : mbid,
          'target': pa['target'],
          'currency': (pa['currency'] ?? 'EUR').toString().trim().isEmpty ? 'EUR' : (pa['currency'] ?? 'EUR').toString().trim(),
          'isActive': (_asInt(pa['isActive'], fallback: 1) ?? 1) == 1 ? 1 : 0,
          'createdAt': _asInt(pa['createdAt'], fallback: DateTime.now().millisecondsSinceEpoch) ?? DateTime.now().millisecondsSinceEpoch,
          'lastCheckedAt': _asInt(pa['lastCheckedAt'], fallback: null),
          'lastHitAt': _asInt(pa['lastHitAt'], fallback: null),
          'lastMin': pa['lastMin'],
          'lastMax': pa['lastMax'],
        }..removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));

        if (existingRows.isNotEmpty) {
          if (mode == BackupImportMode.onlyMissing) {
            result.skippedPriceAlerts++;
            return;
          }

          final ex = existingRows.first;

          int minInt(int a, int b) => (a < b) ? a : b;
          int maxInt(int a, int b) => (a > b) ? a : b;

          final exCreated = _asInt(ex['createdAt'], fallback: payload['createdAt'] as int) ?? (payload['createdAt'] as int);
          final inCreated = _asInt(payload['createdAt'], fallback: exCreated) ?? exCreated;
          payload['createdAt'] = minInt(exCreated, inCreated);

          final exChecked = _asInt(ex['lastCheckedAt'], fallback: null);
          final inChecked = _asInt(payload['lastCheckedAt'], fallback: null);
          if (exChecked != null && inChecked != null) payload['lastCheckedAt'] = maxInt(exChecked, inChecked);

          final exHit = _asInt(ex['lastHitAt'], fallback: null);
          final inHit = _asInt(payload['lastHitAt'], fallback: null);
          if (exHit != null && inHit != null) payload['lastHitAt'] = maxInt(exHit, inHit);

          if (payload['lastMin'] == null && ex['lastMin'] != null) payload['lastMin'] = ex['lastMin'];
          if (payload['lastMax'] == null && ex['lastMax'] != null) payload['lastMax'] = ex['lastMax'];

          await txn.update(
            'price_alerts',
            payload,
            where: 'id = ?',
            whereArgs: [ex['id']],
          );
          result.updatedPriceAlerts++;
        } else {
          await txn.insert(
            'price_alerts',
            payload,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          result.insertedPriceAlerts++;
        }
      }

      // Replace: borra todo y carga
      if (mode == BackupImportMode.replace) {
        await txn.delete('vinyls');
        await txn.delete('wishlist');
        await txn.delete('trash');
        try { await txn.delete('liked_tracks'); } catch (_) {}
        try { await txn.delete('price_alerts'); } catch (_) {}
        try { await txn.delete('artist_orders'); } catch (_) {}

        // numeración estable
        final used = <int>{};
        var next = 1;

        int pickNumero(int n) {
          int nn = n;
          if (nn <= 0 || used.contains(nn)) {
            while (used.contains(next)) {
              next++;
            }
            nn = next;
            used.add(nn);
            next++;
            return nn;
          }
          used.add(nn);
          return nn;
        }

        for (final v in vinyls) {
          final numero = pickNumero(_asInt(v['numero'], fallback: 0) ?? 0);
          final artista = _trim(v['artista']);
          final aKeyIn = _trim(v['artistKey']);
          final aKey = aKeyIn.isNotEmpty ? aKeyIn : _makeArtistKey(artista);
          final prefArtistNo = _asInt(v['artistNo'], fallback: 0) ?? 0;
          final aNo = prefArtistNo > 0
              ? await _getOrCreateArtistNo(txn, aKey, preferredNo: prefArtistNo)
              : await _getOrCreateArtistNo(txn, aKey);
          int alNo = _asInt(v['albumNo'], fallback: 0) ?? 0;
          if (alNo <= 0) alNo = await _nextAlbumNo(txn, aNo);
          await txn.insert(
            'vinyls',
            {
              'numero': numero,
              'artistKey': aKey,
              'artistNo': aNo,
              'albumNo': alNo,
              'artista': artista,
              'album': _trim(v['album']),
              'year': v['year']?.toString().trim(),
              'genre': v['genre']?.toString().trim(),
              'country': v['country']?.toString().trim(),
              'artistBio': v['artistBio']?.toString().trim(),
              'mbid': v['mbid']?.toString().trim(),
              'barcode': v['barcode']?.toString().trim(),
              'coverPath': _normalizeCoverPathForImport(v['coverPath'], v['mbid']),
              'condition': v['condition']?.toString().trim(),
              'format': v['format']?.toString().trim(),
              'favorite': _fav01(v['favorite']),
            }..removeWhere((k, val) => val == null || (val is String && val.trim().isEmpty)),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
          result.insertedVinyls++;
        }

        for (final w in wishlist) {
          await txn.insert(
            'wishlist',
            {
              'artista': _trim(w['artista']),
              'album': _trim(w['album']),
              'year': w['year']?.toString().trim(),
              'cover250': w['cover250']?.toString().trim(),
              'cover500': w['cover500']?.toString().trim(),
              'artistId': w['artistId']?.toString().trim(),
              'status': w['status']?.toString().trim(),
              'barcode': w['barcode']?.toString().trim(),
              'createdAt': _asInt(w['createdAt'], fallback: DateTime.now().millisecondsSinceEpoch),
            }..removeWhere((k, val) => val == null || (val is String && val.trim().isEmpty)),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
          result.insertedWishlist++;
        }

        for (final t in trash) {
          final artista = _trim(t['artista']);
          final aKeyIn = _trim(t['artistKey']);
          final aKey = aKeyIn.isNotEmpty ? aKeyIn : _makeArtistKey(artista);
          final prefArtistNo = _asInt(t['artistNo'], fallback: 0) ?? 0;
          final aNo = prefArtistNo > 0
              ? await _getOrCreateArtistNo(txn, aKey, preferredNo: prefArtistNo)
              : await _getOrCreateArtistNo(txn, aKey);
          int alNo = _asInt(t['albumNo'], fallback: 0) ?? 0;
          if (alNo <= 0) alNo = await _nextAlbumNo(txn, aNo);
          final mbid = t['mbid']?.toString().trim();
          await txn.insert(
            'trash',
            {
              'vinylId': _asInt(t['vinylId'], fallback: null),
              'numero': _asInt(t['numero'], fallback: 0) ?? 0,
              'artistKey': aKey,
              'artistNo': aNo,
              'albumNo': alNo,
              'artista': artista,
              'album': _trim(t['album']),
              'year': t['year']?.toString().trim(),
              'genre': t['genre']?.toString().trim(),
              'country': t['country']?.toString().trim(),
              'artistBio': t['artistBio']?.toString().trim(),
              'mbid': mbid,
              'barcode': t['barcode']?.toString().trim(),
              'coverPath': _normalizeCoverPathForImport(t['coverPath'], mbid),
              'condition': t['condition']?.toString().trim(),
              'format': t['format']?.toString().trim(),
              'favorite': _fav01(t['favorite']),
              'deletedAt': _asInt(t['deletedAt'], fallback: DateTime.now().millisecondsSinceEpoch),
            }..removeWhere((k, val) => val == null || (val is String && val.trim().isEmpty)),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
          result.insertedTrash++;
        }

        for (final lt in likedTracks) {
          await txn.insert(
            'liked_tracks',
            {
              'artistKey': _trim(lt['artistKey']),
              'artista': _trim(lt['artista']),
              'album': _trim(lt['album']),
              'year': lt['year']?.toString().trim(),
              'releaseGroupId': _trim(lt['releaseGroupId']),
              'cover250': lt['cover250']?.toString().trim(),
              'cover500': lt['cover500']?.toString().trim(),
              'trackTitle': _trim(lt['trackTitle']),
              'trackKey': _trim(lt['trackKey']),
              'trackNo': _asInt(lt['trackNo'], fallback: null),
              'createdAt': _asInt(lt['createdAt'], fallback: DateTime.now().millisecondsSinceEpoch),
            }..removeWhere((k, val) => val == null || (val is String && val.trim().isEmpty)),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
          result.insertedLikedTracks++;
        }

        // PRICE ALERTS (re-link por mbid o artista+album)
        for (final pa in priceAlerts) {
          await _upsertPriceAlert(pa, mode);
        }

        return;
      }

      // Merge / onlyMissing: prepara numeros usados
      final existingNums = await txn.query('vinyls', columns: ['numero']);
      final used = <int>{};
      var next = 1;
      for (final r in existingNums) {
        final n = _asInt(r['numero'], fallback: null);
        if (n != null && n > 0) used.add(n);
        if (n != null && n >= next) next = n + 1;
      }

      int pickNumero(int n) {
        int nn = n;
        if (nn <= 0 || used.contains(nn)) {
          while (used.contains(next)) {
            next++;
          }
          nn = next;
          used.add(nn);
          next++;
          return nn;
        }
        used.add(nn);
        return nn;
      }

      String lc(String s) => s.trim().toLowerCase();

      // VINYLS
      for (final v in vinyls) {
        final artista = _trim(v['artista']);
        final album = _trim(v['album']);

        final rows = await txn.query(
          'vinyls',
          where: 'LOWER(artista)=? AND LOWER(album)=?',
          whereArgs: [lc(artista), lc(album)],
          limit: 1,
        );

        if (rows.isNotEmpty) {
          if (mode == BackupImportMode.onlyMissing) {
            result.skippedVinyls++;
            continue;
          }

          final existing = rows.first;

          // merge: no borra favoritos (OR)
          final existingFav = _fav01(existing['favorite']);
          final incomingFav = _fav01(v['favorite']);
          final fav = (incomingFav == 1 || existingFav == 1) ? 1 : 0;

          String? chooseStr(String? incoming, dynamic cur) {
            final a = incoming?.trim() ?? '';
            if (a.isNotEmpty) return a;
            final b = cur?.toString().trim() ?? '';
            return b.isEmpty ? null : b;
          }

          final update = <String, dynamic>{
            // Mantiene numero existente
            'year': chooseStr(v['year']?.toString(), existing['year']),
            'genre': chooseStr(v['genre']?.toString(), existing['genre']),
            'country': chooseStr(v['country']?.toString(), existing['country']),
            'artistBio': chooseStr(v['artistBio']?.toString(), existing['artistBio']),
            // mbid primero, para poder normalizar coverPath usando ese valor.
            'mbid': chooseStr(v['mbid']?.toString(), existing['mbid']),
            'barcode': chooseStr(v['barcode']?.toString(), existing['barcode']),
            'condition': chooseStr(v['condition']?.toString(), existing['condition']),
            'format': chooseStr(v['format']?.toString(), existing['format']),
            'favorite': fav,
          }..removeWhere((k, val) => val == null);

          // Normaliza carátula (si el path local no existe, usa Cover Art Archive por MBID).
          update['coverPath'] = _normalizeCoverPathForImport(
            chooseStr(v['coverPath']?.toString(), existing['coverPath']),
            update['mbid'],
          );

          await txn.update(
            'vinyls',
            update,
            where: 'id=?',
            whereArgs: [existing['id']],
          );
          result.updatedVinyls++;
        } else {
          final numero = pickNumero(_asInt(v['numero'], fallback: 0) ?? 0);
          final aKeyIn = _trim(v['artistKey']);
          final aKey = aKeyIn.isNotEmpty ? aKeyIn : _makeArtistKey(artista);
          final aNo = await _getOrCreateArtistNo(txn, aKey);
          final alNo = await _nextAlbumNo(txn, aNo);
          final mbid = v['mbid']?.toString().trim();
          await txn.insert(
            'vinyls',
            {
              'numero': numero,
              'artistKey': aKey,
              'artistNo': aNo,
              'albumNo': alNo,
              'artista': artista,
              'album': album,
              'year': v['year']?.toString().trim(),
              'genre': v['genre']?.toString().trim(),
              'country': v['country']?.toString().trim(),
              'artistBio': v['artistBio']?.toString().trim(),
              'mbid': mbid,
              'barcode': v['barcode']?.toString().trim(),
              'coverPath': _normalizeCoverPathForImport(v['coverPath'], mbid),
              'condition': v['condition']?.toString().trim(),
              'format': v['format']?.toString().trim(),
              'favorite': _fav01(v['favorite']),
            }..removeWhere((k, val) => val == null || (val is String && val.trim().isEmpty)),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
          result.insertedVinyls++;
        }
      }

      // WISHLIST
      for (final w in wishlist) {
        final artista = _trim(w['artista']);
        final album = _trim(w['album']);

        final rows = await txn.query(
          'wishlist',
          where: 'LOWER(artista)=? AND LOWER(album)=?',
          whereArgs: [lc(artista), lc(album)],
          limit: 1,
        );

        if (rows.isNotEmpty) {
          if (mode == BackupImportMode.onlyMissing) {
            result.skippedWishlist++;
            continue;
          }

          final existing = rows.first;

          String? chooseStr(String? incoming, dynamic cur) {
            final a = incoming?.trim() ?? '';
            if (a.isNotEmpty) return a;
            final b = cur?.toString().trim() ?? '';
            return b.isEmpty ? null : b;
          }

          final update = <String, dynamic>{
            'year': chooseStr(w['year']?.toString(), existing['year']),
            'cover250': chooseStr(w['cover250']?.toString(), existing['cover250']),
            'cover500': chooseStr(w['cover500']?.toString(), existing['cover500']),
            'artistId': chooseStr(w['artistId']?.toString(), existing['artistId']),
            'status': chooseStr(w['status']?.toString(), existing['status']),
            'barcode': chooseStr(w['barcode']?.toString(), existing['barcode']),
            // no tocamos createdAt
          }..removeWhere((k, val) => val == null);

          await txn.update(
            'wishlist',
            update,
            where: 'id=?',
            whereArgs: [existing['id']],
          );
          result.updatedWishlist++;
        } else {
          await txn.insert(
            'wishlist',
            {
              'artista': artista,
              'album': album,
              'year': w['year']?.toString().trim(),
              'cover250': w['cover250']?.toString().trim(),
              'cover500': w['cover500']?.toString().trim(),
              'artistId': w['artistId']?.toString().trim(),
              'status': w['status']?.toString().trim(),
              'barcode': w['barcode']?.toString().trim(),
              'createdAt': _asInt(w['createdAt'], fallback: DateTime.now().millisecondsSinceEpoch),
            }..removeWhere((k, val) => val == null || (val is String && val.trim().isEmpty)),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
          result.insertedWishlist++;
        }
      }

      // TRASH
      for (final t in trash) {
        final artista = _trim(t['artista']);
        final album = _trim(t['album']);

        final rows = await txn.query(
          'trash',
          where: 'LOWER(artista)=? AND LOWER(album)=?',
          whereArgs: [lc(artista), lc(album)],
          limit: 1,
        );

        if (rows.isNotEmpty) {
          if (mode == BackupImportMode.onlyMissing) {
            result.skippedTrash++;
            continue;
          }

          final existing = rows.first;

          String? chooseStr(String? incoming, dynamic cur) {
            final a = incoming?.trim() ?? '';
            if (a.isNotEmpty) return a;
            final b = cur?.toString().trim() ?? '';
            return b.isEmpty ? null : b;
          }

          final existingFav = _fav01(existing['favorite']);
          final incomingFav = _fav01(t['favorite']);
          final fav = (incomingFav == 1 || existingFav == 1) ? 1 : 0;

          final update = <String, dynamic>{
            'vinylId': _asInt(t['vinylId'], fallback: _asInt(existing['vinylId'], fallback: null)),
            'numero': _asInt(t['numero'], fallback: _asInt(existing['numero'], fallback: 0) ?? 0),
            'year': chooseStr(t['year']?.toString(), existing['year']),
            'genre': chooseStr(t['genre']?.toString(), existing['genre']),
            'country': chooseStr(t['country']?.toString(), existing['country']),
            'artistBio': chooseStr(t['artistBio']?.toString(), existing['artistBio']),
            // mbid primero, para poder normalizar coverPath usando ese valor.
            'mbid': chooseStr(t['mbid']?.toString(), existing['mbid']),
            'barcode': chooseStr(t['barcode']?.toString(), existing['barcode']),
            'condition': chooseStr(t['condition']?.toString(), existing['condition']),
            'format': chooseStr(t['format']?.toString(), existing['format']),
            'favorite': fav,
            'deletedAt': _asInt(t['deletedAt'], fallback: _asInt(existing['deletedAt'], fallback: DateTime.now().millisecondsSinceEpoch)),
          }..removeWhere((k, val) => val == null);

          // Normaliza carátula (si el path local no existe, usa Cover Art Archive por MBID).
          update['coverPath'] = _normalizeCoverPathForImport(
            chooseStr(t['coverPath']?.toString(), existing['coverPath']),
            update['mbid'],
          );

          await txn.update(
            'trash',
            update,
            where: 'id=?',
            whereArgs: [existing['id']],
          );
          result.updatedTrash++;
        } else {
          // Calcula/respeta orden ArtistNo.AlbumNo para la tabla trash.
          final aKeyIn = _trim(t['artistKey']);
          final aKey = aKeyIn.isNotEmpty ? aKeyIn : _makeArtistKey(artista);
          final prefArtistNo = _asInt(t['artistNo'], fallback: 0) ?? 0;
          final aNo = await _getOrCreateArtistNo(txn, aKey, preferredNo: prefArtistNo);

          int alNo = _asInt(t['albumNo'], fallback: 0) ?? 0;
          if (alNo <= 0) alNo = await _nextAlbumNo(txn, aNo);

          await txn.insert(
            'trash',
            {
              'vinylId': _asInt(t['vinylId'], fallback: null),
              'numero': _asInt(t['numero'], fallback: 0) ?? 0,
              'artistKey': aKey,
              'artistNo': aNo,
              'albumNo': alNo,
              'artista': artista,
              'album': album,
              'year': t['year']?.toString().trim(),
              'genre': t['genre']?.toString().trim(),
              'country': t['country']?.toString().trim(),
              'artistBio': t['artistBio']?.toString().trim(),
              'mbid': t['mbid']?.toString().trim(),
              'barcode': t['barcode']?.toString().trim(),
              'coverPath': _normalizeCoverPathForImport(t['coverPath'], t['mbid']),
              'condition': t['condition']?.toString().trim(),
              'format': t['format']?.toString().trim(),
              'favorite': _fav01(t['favorite']),
              'deletedAt': _asInt(t['deletedAt'], fallback: DateTime.now().millisecondsSinceEpoch),
            }..removeWhere((k, val) => val == null || (val is String && val.trim().isEmpty)),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
          result.insertedTrash++;
        }
      }

      // LIKED TRACKS (canciones favoritas)
      for (final lt in likedTracks) {
        final rg = _trim(lt['releaseGroupId']);
        final tk = _trim(lt['trackKey']);
        if (rg.isEmpty || tk.isEmpty) {
          result.invalidLikedTracks++;
          continue;
        }

        final rows = await txn.query(
          'liked_tracks',
          where: 'releaseGroupId = ? AND trackKey = ?',
          whereArgs: [rg, tk],
          limit: 1,
        );

        String? chooseStr(String? incoming, dynamic cur) {
          final a = incoming?.trim() ?? '';
          if (a.isNotEmpty) return a;
          final b = cur?.toString().trim() ?? '';
          return b.isEmpty ? null : b;
        }

        if (rows.isNotEmpty) {
          if (mode == BackupImportMode.onlyMissing) {
            result.skippedLikedTracks++;
            continue;
          }

          final existing = rows.first;
          final existingAt = _asInt(existing['createdAt'], fallback: DateTime.now().millisecondsSinceEpoch) ?? DateTime.now().millisecondsSinceEpoch;
          final incomingAt = _asInt(lt['createdAt'], fallback: existingAt) ?? existingAt;
          final keepAt = (incomingAt < existingAt) ? incomingAt : existingAt;

          final update = <String, dynamic>{
            'artistKey': chooseStr(lt['artistKey']?.toString(), existing['artistKey']),
            'artista': chooseStr(lt['artista']?.toString(), existing['artista']),
            'album': chooseStr(lt['album']?.toString(), existing['album']),
            'year': chooseStr(lt['year']?.toString(), existing['year']),
            'cover250': chooseStr(lt['cover250']?.toString(), existing['cover250']),
            'cover500': chooseStr(lt['cover500']?.toString(), existing['cover500']),
            'trackTitle': chooseStr(lt['trackTitle']?.toString(), existing['trackTitle']),
            'trackNo': _asInt(lt['trackNo'], fallback: _asInt(existing['trackNo'], fallback: null)),
            'createdAt': keepAt,
          }..removeWhere((k, val) => val == null || (val is String && val.trim().isEmpty));

          // releaseGroupId + trackKey son la llave, no se actualizan.
          await txn.update(
            'liked_tracks',
            update,
            where: 'id=?',
            whereArgs: [existing['id']],
          );
          result.updatedLikedTracks++;
        } else {
          await txn.insert(
            'liked_tracks',
            {
              'artistKey': _trim(lt['artistKey']),
              'artista': _trim(lt['artista']),
              'album': _trim(lt['album']),
              'year': lt['year']?.toString().trim(),
              'releaseGroupId': rg,
              'cover250': lt['cover250']?.toString().trim(),
              'cover500': lt['cover500']?.toString().trim(),
              'trackTitle': _trim(lt['trackTitle']),
              'trackKey': tk,
              'trackNo': _asInt(lt['trackNo'], fallback: null),
              'createdAt': _asInt(lt['createdAt'], fallback: DateTime.now().millisecondsSinceEpoch),
            }..removeWhere((k, val) => val == null || (val is String && val.trim().isEmpty)),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          result.insertedLikedTracks++;
        }
      }
      // PRICE ALERTS (re-link por mbid o artista+album)
      for (final pa in priceAlerts) {
        await _upsertPriceAlert(pa, mode);
      }
    });

    // Copia a ubicación local (opcional)
    if (copyToLocal) {
      final dest = await _backupFile();
      await dest.writeAsString(txt, flush: true);
    }

    // Prefs al final (si DB ok)
    if (applyPrefs && prefsIn.isNotEmpty) {
      await _applyPrefs(prefsIn);
      result.prefsApplied = true;
    }

    // ✅ Normaliza el orden/código 1.1 (artistNo.albumNo) según inventario (numero).
    // Esto evita que al importar queden artistas con numeración antigua (ej: kitaro = 1.1)
    // cuando el inventario ya tiene otro orden.
    try {
      await VinylDb.instance.rebuildArtistAlbumCodesByNumeroOrder();
    } catch (_) {
      // No debe romper la importación si algo raro pasa.
    }

    // Deja un backup local "normalizado" post-import (con rotación)
    await saveBackupNow(rotate: true);

    return result;
  }

  /// Alias histórico: antes reemplazaba solo la lista desde el archivo local.
  /// Ahora carga el backup local en modo replace (vinyls + wishlist + trash + prefs).
  static Future<void> loadList() async {
    final f = await _backupFile();
    if (!await f.exists()) {
      throw Exception('No existe un respaldo local todavía. Usa "Guardar lista/backup" primero.');
    }
    await importFromFile(f, mode: BackupImportMode.replace, applyPrefs: true, copyToLocal: false);
  }

  static Future<void> autoSaveIfEnabled() async {
    final on = await isAutoEnabled();
    if (on) {
      await saveListNow();
    }
  }
}