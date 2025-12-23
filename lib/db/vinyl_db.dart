import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class VinylDb {
  VinylDb._();
  static final instance = VinylDb._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final base = await getDatabasesPath();
    final path = p.join(base, 'gabolp.db');

    return openDatabase(
      path,
      version: 10, // ✅ v9: condition/format + wishlistStatus
      onOpen: (d) async {
        // Normaliza valores antiguos (por si quedaron como texto 'true'/'false')
        try {
          await d.execute("UPDATE vinyls SET favorite = 1 WHERE favorite = 'true'");
          await d.execute("UPDATE vinyls SET favorite = 0 WHERE favorite = 'false'");
        } catch (_) {
          // si la tabla/columna no existe todavía en algún estado raro, ignorar
        }
      },
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE vinyls(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            numero INTEGER NOT NULL,
            artista TEXT NOT NULL,
            album TEXT NOT NULL,
            year TEXT,
            genre TEXT,
            country TEXT,
            artistBio TEXT,
            coverPath TEXT,
            mbid TEXT,
            condition TEXT,
            format TEXT,
            favorite INTEGER NOT NULL DEFAULT 0
          );
        ''');
        await d.execute('CREATE INDEX idx_artist ON vinyls(artista);');
        await d.execute('CREATE INDEX idx_album ON vinyls(album);');
        await d.execute('CREATE INDEX idx_fav ON vinyls(favorite);');
        await d.execute('CREATE UNIQUE INDEX idx_vinyl_exact ON vinyls(artista, album);');

        // ✅ tabla wishlist (no tiene numero)
        await d.execute('''
          CREATE TABLE wishlist(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            artista TEXT NOT NULL,
            album TEXT NOT NULL,
            year TEXT,
            cover250 TEXT,
            cover500 TEXT,
            artistId TEXT,
            status TEXT,
            createdAt INTEGER NOT NULL
          );
        ''');
        await d.execute('CREATE UNIQUE INDEX idx_wish_unique ON wishlist(artista, album);');

        // ✅ tabla trash (papelera)
        await d.execute('''
          CREATE TABLE trash(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            vinylId INTEGER,
            numero INTEGER NOT NULL,
            artista TEXT NOT NULL,
            album TEXT NOT NULL,
            year TEXT,
            genre TEXT,
            country TEXT,
            artistBio TEXT,
            coverPath TEXT,
            mbid TEXT,
            condition TEXT,
            format TEXT,
            favorite INTEGER NOT NULL DEFAULT 0,
            deletedAt INTEGER NOT NULL
          );
        ''');
        await d.execute('CREATE INDEX idx_trash_deleted ON trash(deletedAt);');
        await d.execute('CREATE UNIQUE INDEX idx_trash_unique ON trash(artista, album);');
      },
      onUpgrade: (d, oldV, newV) async {
        if (oldV < 3) {
          await d.execute('ALTER TABLE vinyls ADD COLUMN genre TEXT;');
        }
        if (oldV < 4) {
          await d.execute('ALTER TABLE vinyls ADD COLUMN artistBio TEXT;');
        }
        if (oldV < 5) {
          await d.execute('ALTER TABLE vinyls ADD COLUMN country TEXT;');
        }
        if (oldV < 6) {
          await d.execute('ALTER TABLE vinyls ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0;');
          await d.execute('CREATE INDEX IF NOT EXISTS idx_fav ON vinyls(favorite);');
        }
        // índice exacto para búsquedas por artista + álbum
        await d.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_vinyl_exact ON vinyls(artista, album);');
        if (oldV < 7) {
          await d.execute('''
            CREATE TABLE IF NOT EXISTS wishlist(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              artista TEXT NOT NULL,
              album TEXT NOT NULL,
              year TEXT,
              cover250 TEXT,
              cover500 TEXT,
              artistId TEXT,
              status TEXT,
              createdAt INTEGER NOT NULL
            );
          ''');
          await d.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_wish_unique ON wishlist(artista, album);');
        }
        if (oldV < 8) {
          // normaliza valores antiguos tipo 'true'/'false'
          await d.execute("UPDATE vinyls SET favorite = 1 WHERE favorite = 'true' OR favorite = 'TRUE'");
          await d.execute("UPDATE vinyls SET favorite = 0 WHERE favorite = 'false' OR favorite = 'FALSE'");
        }

if (oldV < 9) {
  // v9: condition/format en vinyls y status en wishlist
  try {
    await d.execute('ALTER TABLE vinyls ADD COLUMN condition TEXT;');
  } catch (_) {}
  try {
    await d.execute('ALTER TABLE vinyls ADD COLUMN format TEXT;');
  } catch (_) {}
  try {
    await d.execute('ALTER TABLE wishlist ADD COLUMN status TEXT;');
  } catch (_) {}
}

        if (oldV < 10) {
          // v10: papelera (trash)
          await d.execute('''
            CREATE TABLE IF NOT EXISTS trash(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              vinylId INTEGER,
              numero INTEGER NOT NULL,
              artista TEXT NOT NULL,
              album TEXT NOT NULL,
              year TEXT,
              genre TEXT,
              country TEXT,
              artistBio TEXT,
              coverPath TEXT,
              mbid TEXT,
              condition TEXT,
              format TEXT,
              favorite INTEGER NOT NULL DEFAULT 0,
              deletedAt INTEGER NOT NULL
            );
          ''');
          await d.execute('CREATE INDEX IF NOT EXISTS idx_trash_deleted ON trash(deletedAt);');
          await d.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_trash_unique ON trash(artista, album);');
        }

      },
    );
  }

  // ---------------- VINYLS (colección) ----------------

  Future<int> getCount() async {
    final d = await db;
    final r = Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM vinyls'));
    return r ?? 0;
  }

  Future<List<Map<String, dynamic>>> getAll() async {
    final d = await db;
    return d.query('vinyls', orderBy: 'numero ASC');
  }

  Future<List<Map<String, dynamic>>> getFavorites() async {
    final d = await db;
    // Robusto ante backups antiguos (favorite como texto).
    return d.query(
      'vinyls',
      where: "CAST(favorite AS INTEGER) = 1 OR LOWER(CAST(favorite AS TEXT)) = 'true'",
      orderBy: 'numero ASC',
    );
  }

  Future<void> setFavorite({required int id, required bool favorite}) async {
    final d = await db;
    await d.update(
      'vinyls',
      {'favorite': favorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>?> findByExact({
    required String artista,
    required String album,
  }) async {
    final d = await db;
    final a = artista.trim().toLowerCase();
    final al = album.trim().toLowerCase();
    final rows = await d.query(
      'vinyls',
      where: 'LOWER(artista)=? AND LOWER(album)=?',
      whereArgs: [a, al],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> search({
    required String artista,
    required String album,
  }) async {
    final d = await db;
    final a = artista.trim();
    final al = album.trim();

    if (a.isNotEmpty && al.isNotEmpty) {
      return d.query(
        'vinyls',
        where: 'LOWER(artista) LIKE ? AND LOWER(album) LIKE ?',
        whereArgs: ['%${a.toLowerCase()}%', '%${al.toLowerCase()}%'],
        orderBy: 'numero ASC',
      );
    }
    if (a.isNotEmpty) {
      return d.query(
        'vinyls',
        where: 'LOWER(artista) LIKE ?',
        whereArgs: ['%${a.toLowerCase()}%'],
        orderBy: 'numero ASC',
      );
    }
    return d.query(
      'vinyls',
      where: 'LOWER(album) LIKE ?',
      whereArgs: ['%${al.toLowerCase()}%'],
      orderBy: 'numero ASC',
    );
  }

  Future<bool> existsExact({required String artista, required String album}) async {
    final d = await db;
    final a = artista.trim().toLowerCase();
    final al = album.trim().toLowerCase();
    final rows = await d.query(
      'vinyls',
      columns: ['id'],
      where: 'LOWER(artista)=? AND LOWER(album)=?',
      whereArgs: [a, al],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> _nextNumero() async {
    final d = await db;
    final r = await d.rawQuery('SELECT MAX(numero) as m FROM vinyls');
    final m = (r.first['m'] as int?) ?? 0;
    return m + 1;
  }

  Future<void> insertVinyl({
    required String artista,
    required String album,
    String? year,
    String? genre,
    String? country,
    String? artistBio,
    String? coverPath,
    String? mbid,
    String? condition,
    String? format,
    bool favorite = false,
  }) async {
    final d = await db;

    final exists = await existsExact(artista: artista, album: album);
    if (exists) throw Exception('Duplicado');

    final numero = await _nextNumero();

    await d.insert(
      'vinyls',
      {
        'numero': numero,
        'artista': artista.trim(),
        'album': album.trim(),
        'year': year?.trim(),
        'genre': genre?.trim(),
        'country': country?.trim(),
        'artistBio': artistBio?.trim(),
        'coverPath': coverPath?.trim(),
        'mbid': mbid?.trim(),
        'condition': condition?.trim(),
        'format': format?.trim(),
        'favorite': favorite ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> deleteById(int id) async {
    final d = await db;
    await d.delete('vinyls', where: 'id = ?', whereArgs: [id]);
  }


// ---------------- TRASH (papelera) ----------------

Future<List<Map<String, dynamic>>> getTrash() async {
  final d = await db;
  return d.query('trash', orderBy: 'deletedAt DESC');
}

Future<int> countTrash() async {
  final d = await db;
  final r = await d.rawQuery('SELECT COUNT(*) as c FROM trash');
  final v = r.first['c'];
  return (v is int) ? v : int.tryParse(v.toString()) ?? 0;
}

int _asInt(dynamic v) {
  if (v is int) return v;
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

int _fav01(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v == 1 ? 1 : 0;
  if (v is bool) return v ? 1 : 0;
  final s = v.toString().trim().toLowerCase();
  return (s == '1' || s == 'true') ? 1 : 0;
}

Future<void> moveToTrash(int vinylId) async {
  final d = await db;
  await d.transaction((txn) async {
    final rows = await txn.query('vinyls', where: 'id = ?', whereArgs: [vinylId], limit: 1);
    if (rows.isEmpty) return;
    final v = rows.first;

    await txn.insert(
      'trash',
      {
        'vinylId': _asInt(v['id']),
        'numero': _asInt(v['numero']),
        'artista': (v['artista'] ?? '').toString(),
        'album': (v['album'] ?? '').toString(),
        'year': v['year']?.toString(),
        'genre': v['genre']?.toString(),
        'country': v['country']?.toString(),
        'artistBio': v['artistBio']?.toString(),
        'coverPath': v['coverPath']?.toString(),
        'mbid': v['mbid']?.toString(),
        'condition': v['condition']?.toString(),
        'format': v['format']?.toString(),
        'favorite': _fav01(v['favorite']),
        'deletedAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace, // si ya estaba en papelera, se actualiza
    );

    await txn.delete('vinyls', where: 'id = ?', whereArgs: [vinylId]);
  });
}

Future<bool> restoreFromTrash(int trashId) async {
  final d = await db;
  return d.transaction((txn) async {
    final rows = await txn.query('trash', where: 'id = ?', whereArgs: [trashId], limit: 1);
    if (rows.isEmpty) return false;
    final t = rows.first;

    // Si 'numero' vino vacío por alguna razón, asignamos el siguiente.
    final numero = _asInt(t['numero']) == 0
        ? (() async {
            final r = await txn.rawQuery('SELECT MAX(numero) as m FROM vinyls');
            final m = (r.first['m'] as int?) ?? 0;
            return m + 1;
          })()
        : Future.value(_asInt(t['numero']));

    final n = await numero;

    try {
      await txn.insert(
        'vinyls',
        {
          'numero': n,
          'artista': (t['artista'] ?? '').toString().trim(),
          'album': (t['album'] ?? '').toString().trim(),
          'year': t['year']?.toString(),
          'genre': t['genre']?.toString(),
          'country': t['country']?.toString(),
          'artistBio': t['artistBio']?.toString(),
          'coverPath': t['coverPath']?.toString(),
          'mbid': t['mbid']?.toString(),
          'condition': t['condition']?.toString(),
          'format': t['format']?.toString(),
          'favorite': _fav01(t['favorite']),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } catch (_) {
      // Si existe duplicado (índice exacto), no restauramos.
      return false;
    }

    await txn.delete('trash', where: 'id = ?', whereArgs: [trashId]);
    return true;
  });
}

Future<void> deleteTrashById(int trashId) async {
  final d = await db;
  await d.delete('trash', where: 'id = ?', whereArgs: [trashId]);
}

  Future<void> replaceAll(List<Map<String, dynamic>> vinyls) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('vinyls');
      // ✅ Asegura numeración estable:
      // - Si el backup trae "numero" válido (>0), lo respetamos.
      // - Si viene vacío/0, asignamos el siguiente disponible.
      final used = <int>{};
      var next = 1;
      for (final v in vinyls) {
        final nRaw = v['numero'];
        final numero = (nRaw is int)
            ? nRaw
            : int.tryParse(nRaw?.toString() ?? '') ?? 0;

        // Si el backup trae numero inválido, asignamos uno nuevo.
        int finalNumero = numero;
        if (finalNumero <= 0) {
          while (used.contains(next)) {
            next++;
          }
          finalNumero = next;
          used.add(finalNumero);
          next++;
        } else {
          // evita colisiones (si vinieron repetidos)
          if (used.contains(finalNumero)) {
            while (used.contains(next)) {
              next++;
            }
            finalNumero = next;
            used.add(finalNumero);
            next++;
          } else {
            used.add(finalNumero);
          }
        }

        final favRaw = v['favorite'];
        final fav01 = (favRaw == 1 || favRaw == true || favRaw == '1' || favRaw == 'true' || favRaw == 'TRUE') ? 1 : 0;

        await txn.insert(
          'vinyls',
          {
            'numero': finalNumero,
            'artista': (v['artista'] ?? '').toString().trim(),
            'album': (v['album'] ?? '').toString().trim(),
            'year': v['year']?.toString().trim(),
            'genre': v['genre']?.toString().trim(),
            'country': v['country']?.toString().trim(),
            'artistBio': v['artistBio']?.toString().trim(),
            'coverPath': v['coverPath']?.toString().trim(),
            'mbid': v['mbid']?.toString().trim(),
            // ✅ v9: preserva condition/format si existen
            'condition': v['condition']?.toString().trim(),
            'format': v['format']?.toString().trim(),
            'favorite': fav01,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });
  }

  // ---------------- WISHLIST (lista deseos) ----------------

  Future<List<Map<String, dynamic>>> getWishlist() async {
    final d = await db;
    return d.query('wishlist', orderBy: 'createdAt DESC');
  }

  // ✅ Contadores rápidos (evita cargar listas completas solo para contar)
  Future<int> countAll() async {
    final d = await db;
    final r = await d.rawQuery('SELECT COUNT(*) as c FROM vinyls');
    final v = r.first['c'];
    return (v is int) ? v : int.tryParse(v.toString()) ?? 0;
  }

  Future<int> countFavorites() async {
    final d = await db;
    // CAST ayuda si el valor quedó guardado como texto
    final r = await d.rawQuery(
      "SELECT COUNT(*) as c FROM vinyls WHERE CAST(favorite AS INTEGER) = 1 OR favorite = 'true' OR favorite = 'TRUE'",
    );
    final v = r.first['c'];
    return (v is int) ? v : int.tryParse(v.toString()) ?? 0;
  }

  Future<int> countWishlist() async {
    final d = await db;
    final r = await d.rawQuery('SELECT COUNT(*) as c FROM wishlist');
    final v = r.first['c'];
    return (v is int) ? v : int.tryParse(v.toString()) ?? 0;
  }

  Future<Map<String, dynamic>?> findWishlistByExact({
    required String artista,
    required String album,
  }) async {
    final d = await db;
    final a = artista.trim().toLowerCase();
    final al = album.trim().toLowerCase();
    final rows = await d.query(
      'wishlist',
      where: 'LOWER(artista)=? AND LOWER(album)=?',
      whereArgs: [a, al],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> addToWishlist({
    required String artista,
    required String album,
    String? year,
    String? cover250,
    String? cover500,
    String? artistId,
    String? status,
  }) async {
    final d = await db;
    await d.insert(
      'wishlist',
      {
        'artista': artista.trim(),
        'album': album.trim(),
        'year': year?.trim(),
        'cover250': cover250?.trim(),
        'cover500': cover500?.trim(),
        'artistId': artistId?.trim(),
        'status': status?.trim(),
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore, // si ya existe, no duplica
    );
  }

  Future<void> removeWishlistById(int id) async {
    final d = await db;
    await d.delete('wishlist', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> removeWishlistExact({
    required String artista,
    required String album,
  }) async {
    final d = await db;
    await d.delete(
      'wishlist',
      where: 'LOWER(artista)=? AND LOWER(album)=?',
      whereArgs: [artista.trim().toLowerCase(), album.trim().toLowerCase()],
    );
  }
}
