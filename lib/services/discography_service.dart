import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

class ArtistHit {
  final String id;
  final String name;
  final String? country;
  final int? score;

  ArtistHit({
    required this.id,
    required this.name,
    this.country,
    this.score,
  });
}

class SimilarArtistHit {
  final String id;
  final String name;
  final String? country;
  /// Score combinado (0..1 aprox). Mientras más alto, más similar.
  final double score;
  /// Tags compartidos usados para la similitud.
  final List<String> tags;

  SimilarArtistHit({
    required this.id,
    required this.name,
    this.country,
    required this.score,
    required this.tags,
  });
}

class _TagCount {
  final String name;
  final int count;

  _TagCount(this.name, this.count);
}

class _SimilarAgg {
  String name;
  String? country;
  double score;
  final Set<String> tags;

  _SimilarAgg({
    required this.name,
    required this.country,
    required this.score,
    required Set<String> tags,
  }) : tags = tags;
}


class AlbumItem {
  final String releaseGroupId;
  final String title;
  final String? year;
  final String cover250;
  final String cover500;

  AlbumItem({
    required this.releaseGroupId,
    required this.title,
    required this.cover250,
    required this.cover500,
    this.year,
  });
}

class ExploreAlbumHit {
  final String releaseGroupId;
  final String title;
  final String artistName;
  final String? year;
  final String cover250;
  final String cover500;

  ExploreAlbumHit({
    required this.releaseGroupId,
    required this.title,
    required this.artistName,
    required this.cover250,
    required this.cover500,
    this.year,
  });
}

class ExploreAlbumPage {
  final List<ExploreAlbumHit> items;
  final int total;
  final int offset;
  final int limit;

  ExploreAlbumPage({
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
  });
}

class TrackItem {
  final int number;
  final String title;
  final String? length;

  TrackItem({
    required this.number,
    required this.title,
    this.length,
  });
}

class SongHit {
  final String id;
  final String title;
  final int? score;

  SongHit({
    required this.id,
    required this.title,
    this.score,
  });
}

class ArtistInfo {
  final String? country;
  final List<String> genres;
  final String? bio;

  ArtistInfo({
    this.country,
    required this.genres,
    this.bio,
  });
}

class DiscographyService {
  static const _mbBase = 'https://musicbrainz.org/ws/2';
  static DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

  static const _luceneSpecial = '+-!(){}[]^"~*?:\\/&|';

  static String _escLucene(String s) {
    final sb = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      if (_luceneSpecial.contains(ch)) sb.write('\\');
      sb.write(ch);
    }
    return sb.toString();
  }

  static Future<void> _throttle() async {
    final now = DateTime.now();
    final diff = now.difference(_lastCall);
    if (diff.inMilliseconds < 1100) {
      await Future.delayed(
        Duration(milliseconds: 1100 - diff.inMilliseconds),
      );
    }
    _lastCall = DateTime.now();
  }

  static Map<String, String> _headers() => {
        'User-Agent': 'GaBoLP/1.0 (contact: gabo.hachim@gmail.com)',
        'Accept': 'application/json',
      };

  static Future<http.Response> _get(Uri url) async {
    await _throttle();
    return http.get(url, headers: _headers()).timeout(const Duration(seconds: 15));
  }

  // ==================================================
  // 🧭 EXPLORAR ÁLBUMES (GÉNERO + RANGO DE AÑOS)
  // ==================================================
  /// Devuelve una página de álbumes (release-groups) filtrados por:
  /// - tag (género)
  /// - firstreleasedate (rango de años)
  ///
  /// Nota: MusicBrainz usa tags comunitarios; los resultados dependen de cómo
  /// estén etiquetados los release-groups.
  static Future<ExploreAlbumPage> exploreAlbumsByGenreAndYear({
    required String genre,
    required int yearFrom,
    required int yearTo,
    int limit = 30,
    int offset = 0,
  }) async {
    final g = genre.trim();
    if (g.isEmpty) {
      return ExploreAlbumPage(items: const <ExploreAlbumHit>[], total: 0, offset: offset, limit: limit);
    }

    var y1 = yearFrom;
    var y2 = yearTo;
    if (y1 <= 0 && y2 <= 0) {
      // Si el usuario no pone año, dejamos abierto (pero normalmente lo usará).
      y1 = 0;
      y2 = 0;
    } else {
      if (y1 <= 0) y1 = y2;
      if (y2 <= 0) y2 = y1;
      if (y2 < y1) {
        final tmp = y1;
        y1 = y2;
        y2 = tmp;
      }
    }

    final genreTerm = g.contains(' ') ? 'tag:"${_escLucene(g)}"' : 'tag:${_escLucene(g)}';
    final typeTerm = 'primarytype:album';
    final dateTerm = (y1 > 0 && y2 > 0)
        ? 'firstreleasedate:[${y1.toString().padLeft(4, '0')}-01-01 TO ${y2.toString().padLeft(4, '0')}-12-31]'
        : '';

    final lucene = [genreTerm, typeTerm, if (dateTerm.isNotEmpty) dateTerm].join(' AND ');
    final url = Uri.parse(
      '$_mbBase/release-group/?query=${Uri.encodeQueryComponent(lucene)}&fmt=json&limit=$limit&offset=$offset',
    );
    final res = await _get(url);
    if (res.statusCode != 200) {
      return ExploreAlbumPage(items: const <ExploreAlbumHit>[], total: 0, offset: offset, limit: limit);
    }

    final data = jsonDecode(res.body);
    final total = (data['count'] as int?) ?? 0;
    final groups = (data['release-groups'] as List?) ?? [];

    final out = <ExploreAlbumHit>[];
    for (final g in groups) {
      if (g is! Map) continue;
      // Solo álbumes.
      final pt = (g['primary-type'] ?? g['primaryType'] ?? '').toString().toLowerCase();
      if (pt.isNotEmpty && pt != 'album') continue;

      final id = (g['id'] ?? '').toString().trim();
      final title = (g['title'] ?? '').toString().trim();
      if (id.isEmpty || title.isEmpty) continue;

      final date = (g['first-release-date'] ?? '').toString();
      final year = date.length >= 4 ? date.substring(0, 4) : null;

      // Artist credit suele venir como lista.
      String artistName = '';
      final ac = g['artist-credit'];
      if (ac is List && ac.isNotEmpty) {
        final first = ac.first;
        if (first is Map) {
          final name = (first['name'] ?? '').toString().trim();
          if (name.isNotEmpty) artistName = name;
          final art = first['artist'];
          if (artistName.isEmpty && art is Map) {
            artistName = (art['name'] ?? '').toString().trim();
          }
        }
      } else if (ac is Map) {
        artistName = (ac['name'] ?? '').toString().trim();
      }
      artistName = artistName.isEmpty ? '—' : artistName;

      out.add(
        ExploreAlbumHit(
          releaseGroupId: id,
          title: title,
          artistName: artistName,
          year: year,
          cover250: 'https://coverartarchive.org/release-group/$id/front-250',
          cover500: 'https://coverartarchive.org/release-group/$id/front-500',
        ),
      );
    }

    return ExploreAlbumPage(items: out, total: total, offset: offset, limit: limit);
  }

  // ============================================
  // 🎵 BUSCAR CANCIÓN (para filtrar discografía)
  // ============================================
  /// Sugerencias de canciones (autocomplete) para un artista.
  ///
  /// Devuelve una lista corta y deduplicada de títulos (con su recording id)
  /// para poder aplicar el filtro con un click.
  static Future<List<SongHit>> searchSongSuggestions({
    required String artistId,
    required String songQuery,
    int limit = 8,
  }) async {
    final arid = artistId.trim();
    final q = songQuery.trim();
    if (arid.isEmpty || q.isEmpty) return <SongHit>[];

    const specialChars = '+-!(){}[]^"~*?:\\/&|';
    String esc(String s) {
      final sb = StringBuffer();
      for (final rune in s.runes) {
        final ch = String.fromCharCode(rune);
        if (specialChars.contains(ch)) sb.write('\\');
        sb.write(ch);
      }
      return sb.toString();
    }

    final tokens = q.split(RegExp(r'\s+')).where((t) => t.trim().isNotEmpty).toList();
    if (tokens.isEmpty) return <SongHit>[];

    late final String recPart;
    if (tokens.length == 1) {
      final term = esc(tokens.first);
      // Con 1 letra ya queremos sugerencias: siempre wildcard.
      recPart = 'recording:${term}*';
    } else {
      final phrase = esc(q);
      recPart = 'recording:"$phrase"';
    }

    final lucene = '$recPart AND arid:$arid';
    final url = Uri.parse(
      '$_mbBase/recording/?query=${Uri.encodeQueryComponent(lucene)}&fmt=json&limit=$limit',
    );
    final res = await _get(url);
    if (res.statusCode != 200) return <SongHit>[];

    final data = jsonDecode(res.body);
    final recs = (data['recordings'] as List?) ?? [];

    final out = <SongHit>[];
    final seen = <String>{};
    for (final r in recs) {
      if (r is! Map) continue;
      final id = (r['id'] ?? '').toString().trim();
      final title = (r['title'] ?? '').toString().trim();
      if (id.isEmpty || title.isEmpty) continue;

      final k = title.toLowerCase();
      if (seen.contains(k)) continue;
      seen.add(k);

      out.add(
        SongHit(
          id: id,
          title: title,
          score: (r['score'] as num?)?.toInt(),
        ),
      );
    }
    return out;
  }

  /// Resuelve release-groups (preferentemente "Album") para un recording id.
  ///
  /// Esto es más preciso que buscar por texto cuando el usuario selecciona
  /// una opción del dropdown.
  static Future<Set<String>> getAlbumReleaseGroupsForRecordingId({
    required String recordingId,
  }) async {
    final rid = recordingId.trim();
    if (rid.isEmpty) return <String>{};

    try {
      final u = Uri.parse('$_mbBase/recording/$rid?inc=releases+release-groups&fmt=json');
      final rr = await _get(u);
      if (rr.statusCode != 200) return <String>{};
      final d = jsonDecode(rr.body);
      final releases = (d is Map ? (d['releases'] as List?) : null) ?? [];
      final out = <String>{};
      for (final rel in releases) {
        if (rel is! Map) continue;
        final rg = rel['release-group'];
        if (rg is Map) {
          final id = (rg['id'] ?? '').toString().trim();
          final pt = (rg['primary-type'] ?? '').toString().trim();
          if (id.isNotEmpty && (pt.isEmpty || pt.toLowerCase() == 'album')) out.add(id);
        } else if (rg is String) {
          final id = rg.trim();
          if (id.isNotEmpty) out.add(id);
        }
      }
      return out;
    } catch (_) {
      return <String>{};
    }
  }

  /// Devuelve IDs de release-groups (álbumes) donde aparece una canción.
  ///
  /// En UI esto se usa para filtrar la lista de álbumes SIN descargar todos
  /// los tracklists.
  static Future<Set<String>> searchAlbumReleaseGroupsBySong({
    required String artistId,
    required String songQuery,
    int limit = 100,
  }) async {
    final arid = artistId.trim();
    final q = songQuery.trim();
    if (arid.isEmpty || q.isEmpty) return <String>{};

    // Estrategia robusta (evita que el endpoint de búsqueda ignore `inc=`):
    // 1) Buscar recordings (top match) filtrado por artista.
    // 2) Hacer 1 lookup al recording id para obtener releases + release-groups.
    const specialChars = '+-!(){}[]^"~*?:\\/&|';
    String esc(String s) {
      final sb = StringBuffer();
      for (final rune in s.runes) {
        final ch = String.fromCharCode(rune);
        if (specialChars.contains(ch)) sb.write('\\');
        sb.write(ch);
      }
      return sb.toString();
    }

    final tokens = q.split(RegExp(r'\s+')).where((t) => t.trim().isNotEmpty).toList();
    if (tokens.isEmpty) return <String>{};

    late final String recPart;
    if (tokens.length == 1) {
      final term = esc(tokens.first);
      recPart = tokens.first.length >= 3 ? 'recording:${term}*' : 'recording:$term';
    } else {
      final phrase = esc(q);
      final terms = tokens.map(esc).toList();
      recPart = '(recording:"$phrase" OR recording:(${terms.join(' AND ')}))';
    }

    final lucene = '$recPart AND arid:$arid';
    final url = Uri.parse(
      '$_mbBase/recording/?query=${Uri.encodeQueryComponent(lucene)}&fmt=json&limit=$limit',
    );
    final res = await _get(url);
    if (res.statusCode != 200) return <String>{};

    final data = jsonDecode(res.body);
    final recs = (data['recordings'] as List?) ?? [];
    if (recs.isEmpty) return <String>{};

    // Tomamos el mejor match (1er resultado). Para la UI es suficiente.
    final best = recs.first;
    final rid = (best is Map ? (best['id'] ?? '').toString().trim() : '');
    if (rid.isEmpty) return <String>{};

    return getAlbumReleaseGroupsForRecordingId(recordingId: rid);
  }

  // ===============================
  // 🔍 BUSCAR ARTISTAS (AUTOCOMPLETE)
  // ===============================
  static Future<List<ArtistHit>> searchArtists(String name) async {
    final q = name.trim();
    if (q.isEmpty) return [];

    final url = Uri.parse(
      '$_mbBase/artist/?query=${Uri.encodeQueryComponent(q)}&fmt=json&limit=10',
    );
    final res = await _get(url);
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body);
    final artists = (data['artists'] as List?) ?? [];

    return artists.map<ArtistHit>((a) {
      return ArtistHit(
        id: a['id'],
        name: a['name'],
        country: a['country'],
        score: a['score'],
      );
    }).toList()
      ..sort((a, b) => (b.score ?? 0).compareTo(a.score ?? 0));
  }

  // ============================================
  // ✨ ARTISTAS SIMILARES (por tags de MusicBrainz)
  // ============================================
  /// Aproximación "sin API keys":
  /// 1) toma los tags principales del artista (ej: progressive rock, art rock)
  /// 2) busca otros artistas con esos tags
  /// 3) combina resultados y rankea
  static Future<List<SimilarArtistHit>> getSimilarArtistsByArtistId(
    String artistId, {
    int limit = 20,
    int _tagLimit = 2,
    int _perTag = 12,
  }) async {
    final id = artistId.trim();
    if (id.isEmpty) return <SimilarArtistHit>[];

    // 1) Tags del artista
    final infoUrl = Uri.parse('$_mbBase/artist/$id?inc=tags&fmt=json');
    final infoRes = await _get(infoUrl);
    if (infoRes.statusCode != 200) return <SimilarArtistHit>[];

    final data = jsonDecode(infoRes.body);
    final rawTags = (data['tags'] as List?) ?? const <dynamic>[];

    final tags = <_TagCount>[];
    for (final t in rawTags) {
      if (t is! Map) continue;
      final name = (t['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      // evita "1990s", "70s", etc.
      if (RegExp(r'\d').hasMatch(name)) continue;
      final c = (t['count'] is int) ? (t['count'] as int) : int.tryParse((t['count'] ?? '0').toString()) ?? 0;
      tags.add(_TagCount(name, c));
    }
    if (tags.isEmpty) return <SimilarArtistHit>[];

    tags.sort((a, b) => b.count.compareTo(a.count));

    // Filtra tags ultra genéricos si hay alternativas.
    const broad = <String>{
      'rock',
      'pop',
      'electronic',
      'metal',
      'jazz',
      'classical',
      'hip hop',
      'rap',
      'folk',
      'punk',
      'indie',
    };

    final filtered = tags.where((t) => !broad.contains(t.name.toLowerCase())).toList();
    final picked = (filtered.isNotEmpty ? filtered : tags).take(_tagLimit).toList();

    // 2) Buscar artistas por tag y combinar
    final Map<String, _SimilarAgg> agg = <String, _SimilarAgg>{};

    for (final tg in picked) {
      final tagTerm = tg.name.contains(' ')
          ? 'tag:"${_escLucene(tg.name)}"'
          : 'tag:${_escLucene(tg.name)}';

      final url = Uri.parse(
        '$_mbBase/artist/?query=${Uri.encodeQueryComponent(tagTerm)}&fmt=json&limit=$_perTag',
      );
      final res = await _get(url);
      if (res.statusCode != 200) continue;

      final d = jsonDecode(res.body);
      final artists = (d['artists'] as List?) ?? const <dynamic>[];

      // Peso del tag: suavizado por raíz para que no domine un tag con count gigante.
      final tagWeight = tg.count <= 0 ? 1.0 : math.sqrt(tg.count.toDouble());

      for (final a in artists) {
        if (a is! Map) continue;
        final aid = (a['id'] ?? '').toString().trim();
        if (aid.isEmpty) continue;
        if (aid == id) continue;

        final name = (a['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        final country = (a['country'] ?? '').toString().trim();
        final mbScoreNum = (a['score'] is num) ? (a['score'] as num).toDouble() : double.tryParse((a['score'] ?? '0').toString()) ?? 0.0;
        final base = (mbScoreNum / 100.0).clamp(0.0, 1.0);

        final inc = base * tagWeight;

        final cur = agg[aid];
        if (cur == null) {
          agg[aid] = _SimilarAgg(
            name: name,
            country: country.isEmpty ? null : country,
            score: inc,
            tags: <String>{tg.name},
          );
        } else {
          cur.score += inc;
          cur.tags.add(tg.name);
          if ((cur.country == null || cur.country!.isEmpty) && country.isNotEmpty) {
            cur.country = country;
          }
        }
      }
    }

    if (agg.isEmpty) return <SimilarArtistHit>[];

    final out = agg.entries.map((e) {
      final v = e.value;
      final tagList = v.tags.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return SimilarArtistHit(
        id: e.key,
        name: v.name,
        country: v.country,
        score: v.score,
        tags: tagList,
      );
    }).toList();

    out.sort((a, b) => b.score.compareTo(a.score));
    if (out.length > limit) return out.take(limit).toList();
    return out;
  }


  // ==================================================
  // ✅ COMPATIBILIDAD (ARREGLA TU ERROR DE COMPILACIÓN)
  // ==================================================
  static Future<ArtistInfo> getArtistInfo(String artistName) async {
    final hits = await searchArtists(artistName);
    if (hits.isEmpty) {
      return ArtistInfo(country: null, genres: [], bio: null);
    }
    return getArtistInfoById(hits.first.id, artistName: hits.first.name);
  }

  // ==========================================
  // 🎸 INFO ARTISTA (PAÍS, GÉNERO, RESEÑA)
  // ==========================================
  static Future<ArtistInfo> getArtistInfoById(
    String artistId, {
    String? artistName,
  }) async {
    final url = Uri.parse(
      '$_mbBase/artist/$artistId?inc=tags+url-rels&fmt=json',
    );
    final res = await _get(url);

    String? country;
    List<String> genres = [];
    String? name = artistName;

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      country = data['country'];
      name ??= data['name'];

      final tags = (data['tags'] as List?) ?? [];
      for (final t in tags) {
        final g = (t['name'] as String).trim();
        if (g.isEmpty) continue;
        if (RegExp(r'\d').hasMatch(g)) continue; // evita "1990s"
        genres.add(g);
        if (genres.length == 4) break;
      }
    }

    String? bio;
    // 1) Intentar Wikipedia desde relaciones de MusicBrainz (más preciso que buscar por nombre)
    if (res.statusCode == 200) {
      try {
        final data = jsonDecode(res.body);
        final wikiUrl = _pickWikipediaUrlFromRelations(data);
        if (wikiUrl != null) {
          bio = await _fetchWikipediaSummaryFromUrl(wikiUrl);
        }
      } catch (_) {}
    }
    // 2) Fallback: búsqueda por nombre (puede devolver cosas que no son música)
    bio ??= (name == null ? null : await _fetchWikipediaBioES(name));
    // 3) Filtro anti-basura: si no parece reseña musical, la descartamos
    if (bio != null && name != null && !_isRelevantMusicBio(bio!, name)) {
      bio = null;
    }

    return ArtistInfo(
      country: country,
      genres: genres,
      bio: bio,
    );
  }

  // =====================================
  // 📀 DISCOGRAFÍA (ORDENADA POR AÑO)
  // =====================================
  static Future<List<AlbumItem>> getDiscographyByArtistId(
    String artistId,
  ) async {
    final url = Uri.parse(
      '$_mbBase/release-group/?artist=$artistId&fmt=json&limit=100',
    );
    final res = await _get(url);
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body);
    final groups = (data['release-groups'] as List?) ?? [];

    final albums = <AlbumItem>[];

    for (final g in groups) {
      if ((g['primary-type'] ?? '').toString().toLowerCase() != 'album') {
        continue;
      }

      final id = g['id'];
      final title = g['title'];
      final date = g['first-release-date'] ?? '';
      final year = date.length >= 4 ? date.substring(0, 4) : null;

      albums.add(
        AlbumItem(
          releaseGroupId: id,
          title: title,
          year: year,
          cover250:
              'https://coverartarchive.org/release-group/$id/front-250',
          cover500:
              'https://coverartarchive.org/release-group/$id/front-500',
        ),
      );
    }

    albums.sort((a, b) {
      final ay = int.tryParse(a.year ?? '') ?? 9999;
      final by = int.tryParse(b.year ?? '') ?? 9999;
      return ay.compareTo(by);
    });

    return albums;
  }

  // =========================
  // 🎵 TRACKLIST DEL ÁLBUM
  // =========================
  static Future<List<TrackItem>> getTracksFromReleaseGroup(
    String rgid,
  ) async {
    final urlRg = Uri.parse(
      '$_mbBase/release-group/$rgid?inc=releases&fmt=json',
    );
    final resRg = await _get(urlRg);
    if (resRg.statusCode != 200) return [];

    final releases = (jsonDecode(resRg.body)['releases'] as List?) ?? [];
    if (releases.isEmpty) return [];

    final releaseId = releases.first['id'];

    final urlRel = Uri.parse(
      '$_mbBase/release/$releaseId?inc=recordings&fmt=json',
    );
    final resRel = await _get(urlRel);
    if (resRel.statusCode != 200) return [];

    final media = (jsonDecode(resRel.body)['media'] as List?) ?? [];
    if (media.isEmpty) return [];

    final tracks = <TrackItem>[];
    int n = 1;

    for (final m in media) {
      for (final t in (m['tracks'] as List? ?? [])) {
        tracks.add(
          TrackItem(
            number: n++,
            title: t['title'],
            length: _fmtMs(t['length']),
          ),
        );
      }
    }
    return tracks;
  }

  static String? _fmtMs(dynamic ms) {
    if (ms == null) return null;
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  
// =====================================
// 🧠 SELECCIÓN DE WIKIPEDIA + FILTRO
// =====================================
  static String? _pickWikipediaUrlFromRelations(dynamic data) {
    final rels = (data['relations'] as List?) ?? [];
    String? esUrl;
    String? enUrl;
    String? anyUrl;

    for (final r in rels) {
      final urlObj = r is Map ? r['url'] : null;
      final resource = urlObj is Map ? (urlObj['resource'] ?? '').toString() : '';
      if (resource.isEmpty) continue;

      final type = (r is Map ? (r['type'] ?? '').toString().toLowerCase() : '');
      final isWiki = type == 'wikipedia' || resource.contains('wikipedia.org/wiki/');
      if (!isWiki) continue;

      anyUrl ??= resource;
      if (resource.contains('es.wikipedia.org')) esUrl ??= resource;
      if (resource.contains('en.wikipedia.org')) enUrl ??= resource;
    }

    // Preferimos ES, luego EN, luego cualquiera
    return esUrl ?? enUrl ?? anyUrl;
  }

  static Future<String?> _fetchWikipediaSummaryFromUrl(String wikiUrl) async {
    try {
      final uri = Uri.parse(wikiUrl);
      final host = uri.host; // ej: en.wikipedia.org
      if (!host.contains('wikipedia.org')) return null;

      // Ruta típica: /wiki/Titulo
      if (uri.pathSegments.isEmpty) return null;
      final titleRaw = uri.pathSegments.last;
      final title = Uri.decodeComponent(titleRaw);

      final sum = Uri.parse(
        'https://$host/api/rest_v1/page/summary/${Uri.encodeComponent(title)}',
      );
      final sumRes = await http.get(sum, headers: _headers()).timeout(const Duration(seconds: 15));
      if (sumRes.statusCode != 200) return null;

      final decoded = jsonDecode(sumRes.body);
      final extract = decoded['extract'];
      if (extract == null) return null;

      final txt = extract.toString().trim();
      return txt.isEmpty ? null : txt;
    } catch (_) {
      return null;
    }
  }

  static bool _isRelevantMusicBio(String text, String artistName) {
    final t = text.toLowerCase();

    // Red flags típicos de texto basura / e-commerce / políticas.
    const bad = [
      'privacy policy',
      'política de privacidad',
      'cookies',
      'cookie policy',
      'terms of service',
      'términos y condiciones',
      'shipping',
      'envío',
      'returns',
      'devoluciones',
      'subscribe',
      'suscríbete',
      'login',
      'iniciar sesión',
      'warranty',
      'garantía',
      'free shipping',
    ];
    for (final b in bad) {
      if (t.contains(b)) return false;
    }

    // Señales musicales (ES + EN).
    const music = [
      'album',
      'álbum',
      'band',
      'banda',
      'musician',
      'músico',
      'singer',
      'cantante',
      'song',
      'canción',
      'record',
      'disco',
      'studio',
      'estudio',
      'debut',
      'track',
      'pista',
      'release',
      'lanzamiento',
      'genre',
      'género',
      'rock',
      'pop',
      'hip hop',
      'metal',
      'jazz',
      'electronic',
      'electrónica',
    ];

    final name = artistName.toLowerCase().trim();
    final mentionsName = name.isNotEmpty && t.contains(name);

    int hits = 0;
    for (final k in music) {
      if (t.contains(k)) hits++;
      if (hits >= 2) break;
    }

    // Aceptamos si menciona al artista o tiene suficientes señales musicales.
    return mentionsName || hits >= 2;
  }

// =====================================
  // 📝 WIKIPEDIA EN ESPAÑOL (PRIMERO)
  // =====================================
  static Future<String?> _fetchWikipediaBioES(String name) async {
    for (final lang in ['es', 'en']) {
      try {
        final search = Uri.parse(
          'https://$lang.wikipedia.org/w/api.php?action=opensearch&search=${Uri.encodeQueryComponent(name)}&limit=1&format=json',
        );
        final sRes = await http.get(search, headers: _headers()).timeout(const Duration(seconds: 15));
        if (sRes.statusCode != 200) continue;

        final data = jsonDecode(sRes.body);
        if (data[1].isEmpty) continue;

        final title = data[1][0];
        final sum = Uri.parse(
          'https://$lang.wikipedia.org/api/rest_v1/page/summary/$title',
        );
        final sumRes = await http.get(sum, headers: _headers()).timeout(const Duration(seconds: 15));
        if (sumRes.statusCode != 200) continue;

        final extract = jsonDecode(sumRes.body)['extract'];
        if (extract != null && extract.toString().isNotEmpty) {
          return extract;
        }
      } catch (_) {}
    }
    return null;
  }
}
