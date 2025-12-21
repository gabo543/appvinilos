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
      version: 7, // ✅ nuevo: wishlist
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
            createdAt INTEGER NOT NULL
          );
        ''');
        await d.execute('CREATE UNIQUE INDEX idx_wish_unique ON wishlist(artista, album);');
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
              createdAt INTEGER NOT NULL
            );
          ''');
          await d.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_wish_unique ON wishlist(artista, album);');
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
    return d.query('vinyls', where: 'favorite = 1', orderBy: 'numero ASC');
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
        'favorite': favorite ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> deleteById(int id) async {
    final d = await db;
    await d.delete('vinyls', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> replaceAll(List<Map<String, dynamic>> vinyls) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('vinyls');
      for (final v in vinyls) {
        await txn.insert(
          'vinyls',
          {
            'numero': v['numero'],
            'artista': (v['artista'] ?? '').toString().trim(),
            'album': (v['album'] ?? '').toString().trim(),
            'year': v['year']?.toString().trim(),
            'genre': v['genre']?.toString().trim(),
            'country': v['country']?.toString().trim(),
            'artistBio': v['artistBio']?.toString().trim(),
            'coverPath': v['coverPath']?.toString().trim(),
            'mbid': v['mbid']?.toString().trim(),
            'favorite': (v['favorite'] == 1 || v['favorite'] == true) ? 1 : 0,
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
