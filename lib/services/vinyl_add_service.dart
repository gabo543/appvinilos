import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/vinyl_db.dart';
import 'metadata_service.dart';
import 'discography_service.dart';

class AddVinylResult {
  final bool ok;
  final String message;

  AddVinylResult({required this.ok, required this.message});
}

class PreparedVinylAdd {
  final String artist;
  final String album;

  /// Carátula elegida por el usuario (foto/archivo) en el flujo manual.
  /// Si existe, tiene prioridad sobre carátulas descargadas.
  String? localCoverPath;

  /// MusicBrainz Artist ID (si lo conocemos). Útil para reseñas/país.
  final String? artistId;

  final String? year;
  final String? genre;
  final String? country;
  final String? bioShort;

  /// ReleaseGroupID/MBID útil para tracklist/cover
  final String? releaseGroupId;

  /// ReleaseID (útil como fallback de carátula cuando vienes desde búsqueda por barcode)
  final String? releaseId;

  /// Fallback de carátula si el endpoint de release-group no trae imagen.
  final String? coverFallback250;
  final String? coverFallback500;

  /// Opciones de carátula (máx 5)
  final List<CoverCandidate> coverCandidates;

  /// Por defecto: la primera opción
  CoverCandidate? selectedCover;

  PreparedVinylAdd({
    required this.artist,
    required this.album,
    required this.coverCandidates,
    this.selectedCover,
    this.localCoverPath,
    this.artistId,
    this.year,
    this.genre,
    this.country,
    this.bioShort,
    this.releaseGroupId,
    this.releaseId,
    this.coverFallback250,
    this.coverFallback500,
  });

  String? get selectedCover500 => selectedCover?.coverUrl500;
  String? get selectedCover250 => selectedCover?.coverUrl250;
}

class VinylAddService {
  /// 1) Prepara metadata + artist info + opciones de carátula (máx 5)
  static Future<PreparedVinylAdd> prepare({
    required String artist,
    required String album,
    String? artistId, // si lo tienes (por autocomplete), mejor
  }) async {
    final a = artist.trim();
    final al = album.trim();

    // Candidatos de carátula (máx 5)
    final candidatesAll = await MetadataService.fetchCoverCandidates(artist: a, album: al);
    final candidates = candidatesAll.take(5).toList();

    // Metadata del álbum (año, género, releaseGroupId) usando candidates
    final meta = await MetadataService.fetchAutoMetadataWithCandidates(
      artist: a,
      album: al,
      candidates: candidates,
    );

    // Info artista (país + reseña en español)
    ArtistInfo info;
    if (artistId != null && artistId.trim().isNotEmpty) {
      info = await DiscographyService.getArtistInfoById(artistId.trim(), artistName: a);
    } else {
      info = await DiscographyService.getArtistInfo(a);
    }

    final country = (info.country ?? '').trim();
    final bio = (info.bio ?? '').trim();
    final bioShort = bio.isEmpty ? null : (bio.length > 220 ? '${bio.substring(0, 220)}…' : bio);

    final prepared = PreparedVinylAdd(
      artist: a,
      album: al,
      coverCandidates: candidates,
      selectedCover: candidates.isNotEmpty ? candidates.first : null,
      artistId: (artistId ?? '').trim().isEmpty ? null : artistId!.trim(),
      year: (meta.year ?? '').trim().isEmpty ? null : meta.year!.trim(),
      genre: (meta.genre ?? '').trim().isEmpty ? null : meta.genre!.trim(),
      country: country.isEmpty ? null : country,
      bioShort: bioShort,
      releaseGroupId: (meta.releaseGroupId ?? '').trim().isEmpty ? null : meta.releaseGroupId!.trim(),
    );

    return prepared;
  }

  /// Variante optimizada: si ya tienes el releaseGroupId (por ejemplo, desde un scanner),
  /// evitamos el llamado extra para descubrir candidatos.
  static Future<PreparedVinylAdd> prepareFromReleaseGroup({
    required String artist,
    required String album,
    required String releaseGroupId,
    String? releaseId,
    String? year,
    String? artistId,
  }) async {
    final a = artist.trim();
    final al = album.trim();
    final rgid = releaseGroupId.trim();

    final rid = (releaseId ?? '').trim();

    final candidates = <CoverCandidate>[
      CoverCandidate(
        releaseGroupId: rgid,
        year: (year ?? '').trim().isEmpty ? null : year!.trim(),
        coverUrl250: 'https://coverartarchive.org/release-group/$rgid/front-250',
        coverUrl500: 'https://coverartarchive.org/release-group/$rgid/front-500',
      ),
    ];

    // Metadata del álbum (año, género) usando candidates (sin doble llamado)
    final meta = await MetadataService.fetchAutoMetadataWithCandidates(
      artist: a,
      album: al,
      candidates: candidates,
    );

    // Info artista (país + reseña en español)
    ArtistInfo info;
    if (artistId != null && artistId.trim().isNotEmpty) {
      info = await DiscographyService.getArtistInfoById(artistId.trim(), artistName: a);
    } else {
      info = await DiscographyService.getArtistInfo(a);
    }

    final country = (info.country ?? '').trim();
    final bio = (info.bio ?? '').trim();
    final bioShort = bio.isEmpty ? null : (bio.length > 220 ? '${bio.substring(0, 220)}…' : bio);

    return PreparedVinylAdd(
      artist: a,
      album: al,
      coverCandidates: candidates,
      selectedCover: candidates.first,
      artistId: (artistId ?? '').trim().isEmpty ? null : artistId!.trim(),
      year: (meta.year ?? '').trim().isEmpty ? null : meta.year!.trim(),
      genre: (meta.genre ?? '').trim().isEmpty ? null : meta.genre!.trim(),
      country: country.isEmpty ? null : country,
      bioShort: bioShort,
      releaseGroupId: (meta.releaseGroupId ?? rgid).trim().isEmpty ? rgid : (meta.releaseGroupId ?? rgid).trim(),
      releaseId: rid.isEmpty ? null : rid,
      coverFallback250: rid.isEmpty ? null : 'https://coverartarchive.org/release/$rid/front-250',
      coverFallback500: rid.isEmpty ? null : 'https://coverartarchive.org/release/$rid/front-500',
    );
  }

  /// 2) Agrega a SQLite y guarda carátula local
  static Future<AddVinylResult> addPrepared(
    PreparedVinylAdd prepared, {
    String? overrideYear, // si quieres permitir editar año
    bool favorite = false,
    String? condition,
    String? format,
  }) async { 
    final artist = prepared.artist.trim();
    final album = prepared.album.trim();
    if (artist.isEmpty || album.isEmpty) {
      return AddVinylResult(ok: false, message: 'Artista y Álbum son obligatorios.');
    }

    // Carátula local (si el usuario subió foto/archivo)
    String? coverPath;

    final local = (prepared.localCoverPath ?? '').trim();
    if (local.isNotEmpty) {
      coverPath = await _copyLocalCoverToLocal(local);
    }

    // Descargar carátula (si hay). Intentamos con la seleccionada.
    // 1) selected 500
    if (coverPath == null) {
      final primary = (prepared.selectedCover500 ?? '').trim();
      if (primary.isNotEmpty) {
        coverPath = await _downloadCoverToLocal(primary);
      }
    }

    // 2) fallback 500 (release)
    if (coverPath == null) {
      final fb = (prepared.coverFallback500 ?? '').trim();
      if (fb.isNotEmpty) {
        coverPath = await _downloadCoverToLocal(fb);
      }
    }

    // 3) selected 250
    if (coverPath == null) {
      final alt = (prepared.selectedCover250 ?? '').trim();
      if (alt.isNotEmpty) {
        coverPath = await _downloadCoverToLocal(alt);
      }
    }

    // 4) fallback 250 (release)
    if (coverPath == null) {
      final fb = (prepared.coverFallback250 ?? '').trim();
      if (fb.isNotEmpty) {
        coverPath = await _downloadCoverToLocal(fb);
      }
    }

    final y = (overrideYear ?? prepared.year ?? '').trim();
    try {
      await VinylDb.instance.insertVinyl(
        artista: artist,
        album: album,
        year: y.isEmpty ? null : y,
        genre: prepared.genre,
        country: prepared.country,
        artistBio: prepared.bioShort,
        coverPath: coverPath,
        mbid: prepared.releaseGroupId,
        condition: condition,
        format: format,
        favorite: favorite,
      );
      return AddVinylResult(ok: true, message: favorite ? 'Agregado a favoritos ⭐' : 'Vinilo agregado ✅');
    } catch (_) {
      return AddVinylResult(ok: false, message: 'Ese vinilo ya existe (Artista + Álbum).');
    }
  }

  static Future<String?> _downloadCoverToLocal(String url) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;

      final dir = await getApplicationDocumentsDirectory();
      final coversDir = Directory(p.join(dir.path, 'covers'));
      if (!await coversDir.exists()) await coversDir.create(recursive: true);

      final ct = res.headers['content-type'] ?? '';
      final ext = ct.contains('png') ? 'png' : 'jpg';
      final filename = 'cover_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final file = File(p.join(coversDir.path, filename));
      await file.writeAsBytes(res.bodyBytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _copyLocalCoverToLocal(String sourcePath) async {
    try {
      final src = File(sourcePath);
      if (!await src.exists()) return null;

      final dir = await getApplicationDocumentsDirectory();
      final coversDir = Directory(p.join(dir.path, 'covers'));
      if (!await coversDir.exists()) await coversDir.create(recursive: true);

      var ext = p.extension(sourcePath).replaceAll('.', '').toLowerCase();
      if (ext.isEmpty) ext = 'jpg';
      if (ext.length > 5) ext = 'jpg';

      final filename = 'cover_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final dstPath = p.join(coversDir.path, filename);
      final dst = await src.copy(dstPath);
      return dst.path;
    } catch (_) {
      return null;
    }
  }

  /// Expuesto para tareas de mantenimiento (por ejemplo, descargar carátulas
  /// faltantes después de importar un backup).
  static Future<String?> downloadCoverToLocal(String url) async {
    return _downloadCoverToLocal(url);
  }
}

