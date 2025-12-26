import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../utils/normalize.dart';

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
      version: 12, // ✅ v12: reparar carátulas faltantes tras restore (fallback a Cover Art Archive)
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
            artistKey TEXT NOT NULL,
            artistNo INTEGER NOT NULL,
            albumNo INTEGER NOT NULL,
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
        await d.execute('CREATE INDEX idx_artist_no ON vinyls(artistNo);');
        await d.execute('CREATE INDEX idx_album_no ON vinyls(albumNo);');
        await d.execute('CREATE INDEX idx_artist_key ON vinyls(artistKey);');
        await d.execute('CREATE INDEX idx_fav ON vinyls(favorite);');
        await d.execute('CREATE UNIQUE INDEX idx_vinyl_exact ON vinyls(artista, album);');

        // ✅ tabla artist_orders: asigna un número fijo por artista (sin alfabético)
        await d.execute('''
          CREATE TABLE artist_orders(
            artistKey TEXT PRIMARY KEY,
            artistNo INTEGER NOT NULL
          );
        ''');
        await d.execute('CREATE UNIQUE INDEX idx_artist_orders_no ON artist_orders(artistNo);');

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
            artistKey TEXT NOT NULL,
            artistNo INTEGER NOT NULL,
            albumNo INTEGER NOT NULL,
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
              artistKey TEXT NOT NULL,
              artistNo INTEGER NOT NULL,
              albumNo INTEGER NOT NULL,
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

        if (oldV < 11) {
          // v11: orden Artista.Album (artistNo.albumNo)
          await d.execute('''
            CREATE TABLE IF NOT EXISTS artist_orders(
              artistKey TEXT PRIMARY KEY,
              artistNo INTEGER NOT NULL
            );
          ''');
          await d.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_artist_orders_no ON artist_orders(artistNo);');

          // Añadir columnas a vinyls
          try {
            await d.execute("ALTER TABLE vinyls ADD COLUMN artistKey TEXT NOT NULL DEFAULT '';");
          } catch (_) {}
          try {
            await d.execute("ALTER TABLE vinyls ADD COLUMN artistNo INTEGER NOT NULL DEFAULT 0;");
          } catch (_) {}
          try {
            await d.execute("ALTER TABLE vinyls ADD COLUMN albumNo INTEGER NOT NULL DEFAULT 0;");
          } catch (_) {}

          // Añadir columnas a trash
          try {
            await d.execute("ALTER TABLE trash ADD COLUMN artistKey TEXT NOT NULL DEFAULT '';");
          } catch (_) {}
          try {
            await d.execute("ALTER TABLE trash ADD COLUMN artistNo INTEGER NOT NULL DEFAULT 0;");
          } catch (_) {}
          try {
            await d.execute("ALTER TABLE trash ADD COLUMN albumNo INTEGER NOT NULL DEFAULT 0;");
          } catch (_) {}

          // Índices nuevos
          await d.execute('CREATE INDEX IF NOT EXISTS idx_artist_no ON vinyls(artistNo);');
          await d.execute('CREATE INDEX IF NOT EXISTS idx_album_no ON vinyls(albumNo);');
          await d.execute('CREATE INDEX IF NOT EXISTS idx_artist_key ON vinyls(artistKey);');

          // ✅ Migración: asigna artistNo y albumNo según el orden actual "numero"
          final rows = await d.query(
            'vinyls',
            columns: ['id', 'numero', 'artista', 'artistKey', 'artistNo', 'albumNo'],
            orderBy: 'numero ASC',
          );

          final keyToNo = <String, int>{};
          final keyToAlbum = <String, int>{};
          var nextArtistNo = 1;

          for (final r in rows) {
            final id = r['id'] as int? ?? 0;
            if (id <= 0) continue;

            final artista = (r['artista'] ?? '').toString();
            var key = _makeArtistKey(artista);
            if (key.isEmpty) key = 'unknown';

            // artistNo
            int aNo = _asInt(r['artistNo']);
            if (aNo <= 0) {
              aNo = keyToNo[key] ?? 0;
              if (aNo <= 0) {
                aNo = nextArtistNo++;
                keyToNo[key] = aNo;
                await d.insert(
                  'artist_orders',
                  {'artistKey': key, 'artistNo': aNo},
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                );
              }
            } else {
              keyToNo[key] = aNo;
              // Asegura que el mapping exista
              await d.insert(
                'artist_orders',
                {'artistKey': key, 'artistNo': aNo},
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
              if (aNo >= nextArtistNo) nextArtistNo = aNo + 1;
            }

            // albumNo
            int alNo = _asInt(r['albumNo']);
            final cur = keyToAlbum[key] ?? 0;
            if (alNo <= 0) {
              alNo = cur + 1;
            }
            if (alNo > cur) keyToAlbum[key] = alNo;

            await d.update(
              'vinyls',
              {'artistKey': key, 'artistNo': aNo, 'albumNo': alNo},
              where: 'id = ?',
              whereArgs: [id],
            );
          }

          // ✅ Papelera: intenta completar artistKey/artistNo (albumNo se deja si vino)
          final trashRows = await d.query(
            'trash',
            columns: ['id', 'artista', 'artistKey', 'artistNo', 'albumNo'],
            orderBy: 'deletedAt ASC',
          );
          for (final t in trashRows) {
            final id = t['id'] as int? ?? 0;
            if (id <= 0) continue;

            final artista = (t['artista'] ?? '').toString();
            var key = (t['artistKey'] ?? '').toString().trim();
            if (key.isEmpty) key = _makeArtistKey(artista);
            if (key.isEmpty) key = 'unknown';

            int aNo = _asInt(t['artistNo']);
            if (aNo <= 0) {
              // si ya existe en mapping, úsalo; si no, crea uno nuevo al final
              final existing = await d.query(
                'artist_orders',
                columns: ['artistNo'],
                where: 'artistKey = ?',
                whereArgs: [key],
                limit: 1,
              );
              if (existing.isNotEmpty) {
                aNo = _asInt(existing.first['artistNo']);
              } else {
                final r = await d.rawQuery('SELECT MAX(artistNo) as m FROM artist_orders');
                final m = _asInt(r.first['m']);
                aNo = m + 1;
                await d.insert(
                  'artist_orders',
                  {'artistKey': key, 'artistNo': aNo},
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                );
              }
            }

            await d.update(
              'trash',
              {'artistKey': key, 'artistNo': aNo},
              where: 'id = ?',
              whereArgs: [id],
            );
          }
        }

        if (oldV < 12) {
          // v12: si la carátula era un path local que ya no existe (por reinstalación/restore),
          // caemos a un URL de Cover Art Archive usando el mbid (release-group).
          Future<void> repairTable(String table) async {
            final rows = await d.query(table, columns: ['id', 'coverPath', 'mbid']);
            for (final r in rows) {
              final id = (r['id'] as int?) ?? 0;
              if (id <= 0) continue;

              final cp = (r['coverPath'] ?? '').toString().trim();
              final mbid = (r['mbid'] ?? '').toString().trim();

              // Si ya es URL, lo dejamos.
              if (cp.startsWith('http://') || cp.startsWith('https://')) continue;

              String? next;
              if (cp.isNotEmpty) {
                final exists = await File(cp).exists();
                if (exists) continue; // path válido
              }

              // Si no hay archivo local, intentamos URL por MBID.
              if (mbid.isNotEmpty) {
                next = 'https://coverartarchive.org/release-group/$mbid/front-250';
              }

              await d.update(
                table,
                {'coverPath': next},
                where: 'id = ?',
                whereArgs: [id],
              );
            }
          }

          await repairTable('vinyls');
          try {
            await repairTable('trash');
          } catch (_) {}
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
    return d.query('vinyls', orderBy: 'artistNo ASC, albumNo ASC');
  }

  Future<List<Map<String, dynamic>>> getFavorites() async {
    final d = await db;
    // Robusto ante backups antiguos (favorite como texto).
    return d.query(
      'vinyls',
      where: "CAST(favorite AS INTEGER) = 1 OR LOWER(CAST(favorite AS TEXT)) = 'true'",
      orderBy: 'artistNo ASC, albumNo ASC',
    );
  }

  /// Marca/Desmarca favorito.
  ///
  /// ✅ Ruta principal: actualiza por `id`.
  /// ✅ Fallback: si el `id` no actualiza ninguna fila, intenta por `artista` + `album`.
  ///
  /// Esto evita estados “marcado pero no guardado” cuando la UI tiene un mapa sin `id` válido.
  Future<void> setFavoriteSafe({
    required bool favorite,
    int? id,
    String? artista,
    String? album,
    int? numero,
    String? mbid,
  }) async {
    final d = await db;
    final fav01 = favorite ? 1 : 0;

    // 1) Ruta principal: por id
    if (id != null && id > 0) {
      final changed = await d.update(
        'vinyls',
        {'favorite': fav01},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changed > 0) return;
    }

    // 2) Fallback: por artista + álbum
    if (artista != null && album != null) {
      final a = artista.trim();
      final al = album.trim();

      final changed = await d.update(
        'vinyls',
        {'favorite': fav01},
        where: 'LOWER(TRIM(artista))=LOWER(TRIM(?)) AND LOWER(TRIM(album))=LOWER(TRIM(?))',
        whereArgs: [a, al],
      );
      if (changed > 0) return;
    }


    // 3) Fallback: por mbid (ReleaseGroupID) si existe (suele ser único)
    if (mbid != null && mbid.trim().isNotEmpty) {
      final key = mbid.trim();
      final changed = await d.update(
        'vinyls',
        {'favorite': fav01},
        where: 'TRIM(mbid) = TRIM(?)',
        whereArgs: [key],
      );
      if (changed > 0) return;
    }

    // 4) Fallback: por número (colección). Útil si el mapa de UI trae id desincronizado.
    if (numero != null && numero > 0) {
      // Si tenemos artista/álbum, acotamos para evitar colisiones si existieran números repetidos.
      final where = (artista != null && album != null)
          ? 'numero = ? AND LOWER(TRIM(artista))=LOWER(TRIM(?)) AND LOWER(TRIM(album))=LOWER(TRIM(?))'
          : 'numero = ?';
      final args = (artista != null && album != null)
          ? [numero, artista.trim(), album.trim()]
          : [numero];

      final changed = await d.update(
        'vinyls',
        {'favorite': fav01},
        where: where,
        whereArgs: args,
      );
      if (changed > 0) return;
    }

    throw Exception('No se pudo actualizar favorito (0 filas afectadas).');
  }

  /// ✅ Actualización estricta por ID.
  ///
  /// Esto es útil cuando la UI está mostrando una fila concreta (por ejemplo,
  /// en la pantalla de Favoritos). Evita que un fallback actualice otra fila
  /// distinta y deje el vinilo “pegado” en Favoritos.
  Future<void> setFavoriteStrictById({
    required int id,
    required bool favorite,
  }) async {
    final d = await db;
    final fav01 = favorite ? 1 : 0;

    // Hacemos el UPDATE y luego verificamos el valor real guardado.
    await d.rawUpdate(
      'UPDATE vinyls SET favorite = ? WHERE id = ?',
      [fav01, id],
    );

    final rows = await d.query(
      'vinyls',
      columns: ['favorite'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw Exception('Vinilo no encontrado.');

    final v = rows.first['favorite'];
    final saved = (v == 1 || v == true || v == '1' || v == 'true' || v == 'TRUE');
    if (saved != favorite) {
      throw Exception('No se pudo persistir favorito.');
    }
  }

  /// Compat: firma antigua usada en varias pantallas.

  Future<void> setFavorite({required int id, required bool favorite}) async {
    await setFavoriteSafe(favorite: favorite, id: id);
  }

  
  Future<Map<String, dynamic>?> findByMbid({required String mbid}) async {
    final d = await db;
    final key = mbid.trim();
    if (key.isEmpty) return null;
    final rows = await d.query(
      'vinyls',
      where: 'TRIM(mbid) = TRIM(?)',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
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
        orderBy: 'artistNo ASC, albumNo ASC',
      );
    }
    if (a.isNotEmpty) {
      return d.query(
        'vinyls',
        where: 'LOWER(artista) LIKE ?',
        whereArgs: ['%${a.toLowerCase()}%'],
        orderBy: 'artistNo ASC, albumNo ASC',
      );
    }
    return d.query(
      'vinyls',
      where: 'LOWER(album) LIKE ?',
      whereArgs: ['%${al.toLowerCase()}%'],
      orderBy: 'artistNo ASC, albumNo ASC',
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


  // ---------------- ORDEN Artista.Album ----------------
  //
  // Regla:
  // - Un artista tiene SIEMPRE el mismo número (artistNo).
  // - Cada álbum del artista se numera 1..n (albumNo).
  // - El “código” que muestra la UI es: artistNo.albumNo (ej: 1.3)

  String _makeArtistKey(String artista) {
    return normalizeKey(artista);
  }

  Future<int> _getOrCreateArtistNo(
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
    if (rows.isNotEmpty) return _asInt(rows.first['artistNo']);

    int chosen = 0;

    // Si viene de un backup “replace”, intentamos respetar el número original.
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
      final m = _asInt(r.first['m']);
      chosen = m + 1;
    }

    await ex.insert(
      'artist_orders',
      {'artistKey': key, 'artistNo': chosen},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    return chosen;
  }

  Future<int> _nextAlbumNo(DatabaseExecutor ex, int artistNo) async {
    if (artistNo <= 0) return 0;
    final r = await ex.rawQuery(
      'SELECT MAX(albumNo) as m FROM vinyls WHERE artistNo = ?',
      [artistNo],
    );
    final m = _asInt(r.first['m']);
    return m + 1;
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

    final aKey = _makeArtistKey(artista);
    final aNo = await _getOrCreateArtistNo(d, aKey);
    final alNo = await _nextAlbumNo(d, aNo);

    await d.insert(
      'vinyls',
      {
        'numero': numero,
        'artistKey': aKey,
        'artistNo': aNo,
        'albumNo': alNo,
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

  /// Actualiza metadatos editables de un vinilo.
  ///
  /// Útil para correcciones manuales (año/condición/formato/caratula).
  Future<void> updateVinylMeta({
    required int id,
    String? year,
    String? condition,
    String? format,
    String? coverPath,
  }) async {
    final d = await db;
    final values = <String, Object?>{};
    if (year != null) values['year'] = year.trim();
    if (condition != null) values['condition'] = condition.trim();
    if (format != null) values['format'] = format.trim();
    if (coverPath != null) values['coverPath'] = coverPath.trim();
    if (values.isEmpty) return;
    await d.update('vinyls', values, where: 'id = ?', whereArgs: [id]);
  }

  /// Busca duplicados “suaves” por artista+álbum (+año opcional).
  ///
  /// Aunque existe un índice UNIQUE (artista, album), pueden aparecer duplicados
  /// por diferencias de espacios/mayúsculas/acentos o por imports.
  Future<List<List<Map<String, dynamic>>>> findDuplicateGroups({bool includeYear = true}) async {
    final d = await db;
    final groups = await d.rawQuery(
      '''
      SELECT
        LOWER(TRIM(artista)) AS a,
        LOWER(TRIM(album)) AS al,
        ${includeYear ? "COALESCE(TRIM(year), '')" : "''"} AS y,
        COUNT(*) AS c
      FROM vinyls
      GROUP BY a, al, y
      HAVING c > 1
      ORDER BY c DESC
      LIMIT 50
      ''',
    );

    final out = <List<Map<String, dynamic>>>[];
    for (final g in groups) {
      final a = (g['a'] ?? '').toString();
      final al = (g['al'] ?? '').toString();
      final y = (g['y'] ?? '').toString();
      final rows = await d.query(
        'vinyls',
        where: includeYear
            ? "LOWER(TRIM(artista))=? AND LOWER(TRIM(album))=? AND COALESCE(TRIM(year), '')=?"
            : "LOWER(TRIM(artista))=? AND LOWER(TRIM(album))=?",
        whereArgs: includeYear ? [a, al, y] : [a, al],
        orderBy: 'id ASC',
      );
      if (rows.length > 1) out.add(rows);
    }
    return out;
  }

  /// Fusiona duplicados “suaves”. Conserva un registro por grupo y elimina el resto.
  ///
  /// Regla de conservación:
  /// - Si alguno es favorito -> conserva el favorito
  /// - si no, conserva el de menor id
  ///
  /// Devuelve cuántas filas eliminó.
  Future<int> mergeDuplicates({bool includeYear = true}) async {
    final d = await db;
    final groups = await findDuplicateGroups(includeYear: includeYear);
    if (groups.isEmpty) return 0;

    int deleted = 0;

    await d.transaction((txn) async {
      for (final rows in groups) {
        if (rows.length <= 1) continue;

        // Elegir “keep”
        Map<String, dynamic> keep = rows.first;
        for (final r in rows) {
          final fav = _fav01(r['favorite']);
          if (fav == 1) {
            keep = r;
            break;
          }
        }

        final keepId = _asInt(keep['id']);
        if (keepId <= 0) continue;

        // Mezclar campos “mejor esfuerzo”
        String bestYear = (keep['year'] ?? '').toString().trim();
        String bestCondition = (keep['condition'] ?? '').toString().trim();
        String bestFormat = (keep['format'] ?? '').toString().trim();
        String bestCover = (keep['coverPath'] ?? '').toString().trim();
        int bestFav = _fav01(keep['favorite']);

        for (final r in rows) {
          if (_asInt(r['id']) == keepId) continue;
          if (bestYear.isEmpty) bestYear = (r['year'] ?? '').toString().trim();
          if (bestCondition.isEmpty) bestCondition = (r['condition'] ?? '').toString().trim();
          if (bestFormat.isEmpty) bestFormat = (r['format'] ?? '').toString().trim();
          if (bestCover.isEmpty) bestCover = (r['coverPath'] ?? '').toString().trim();
          if (bestFav == 0) bestFav = _fav01(r['favorite']);
        }

        await txn.update(
          'vinyls',
          {
            'year': bestYear.isEmpty ? null : bestYear,
            'condition': bestCondition.isEmpty ? null : bestCondition,
            'format': bestFormat.isEmpty ? null : bestFormat,
            'coverPath': bestCover.isEmpty ? null : bestCover,
            'favorite': bestFav,
          },
          where: 'id = ?',
          whereArgs: [keepId],
        );

        // Eliminar el resto
        for (final r in rows) {
          final id = _asInt(r['id']);
          if (id <= 0 || id == keepId) continue;
          final c = await txn.delete('vinyls', where: 'id = ?', whereArgs: [id]);
          deleted += c;
        }
      }
    });

    return deleted;
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
        'artistKey': (v['artistKey'] ?? '').toString(),
        'artistNo': _asInt(v['artistNo']),
        'albumNo': _asInt(v['albumNo']),
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

    final aKey = ((t['artistKey'] ?? '').toString().trim().isNotEmpty)
        ? (t['artistKey'] ?? '').toString().trim()
        : _makeArtistKey((t['artista'] ?? '').toString());
    final prefArtistNo = _asInt(t['artistNo']);
    final aNo = prefArtistNo > 0
        ? await _getOrCreateArtistNo(txn, aKey, preferredNo: prefArtistNo)
        : await _getOrCreateArtistNo(txn, aKey);
    int alNo = _asInt(t['albumNo']);
    if (alNo <= 0) {
      alNo = await _nextAlbumNo(txn, aNo);
    }

    try {
      await txn.insert(
        'vinyls',
        {
          'numero': n,
          'artistKey': aKey,
          'artistNo': aNo,
          'albumNo': alNo,
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
      // ✅ v11: reinicia mapping artista->número
      try { await txn.delete('artist_orders'); } catch (_) {}

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

        final artista = (v['artista'] ?? '').toString().trim();
        final aKey = (v['artistKey'] ?? '').toString().trim().isNotEmpty
            ? (v['artistKey'] ?? '').toString().trim()
            : _makeArtistKey(artista);
        final prefArtistNo = _asInt(v['artistNo']);
        final aNo = prefArtistNo > 0
            ? await _getOrCreateArtistNo(txn, aKey, preferredNo: prefArtistNo)
            : await _getOrCreateArtistNo(txn, aKey);
        int alNo = _asInt(v['albumNo']);
        if (alNo <= 0) {
          alNo = await _nextAlbumNo(txn, aNo);
        }

        final favRaw = v['favorite'];
        final fav01 = (favRaw == 1 || favRaw == true || favRaw == '1' || favRaw == 'true' || favRaw == 'TRUE') ? 1 : 0;

        await txn.insert(
          'vinyls',
          {
            'numero': finalNumero,
            'artistKey': aKey,
            'artistNo': aNo,
            'albumNo': alNo,
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
