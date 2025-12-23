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

  final String? year;
  final String? genre;
  final String? country;
  final String? bioShort;

  /// ReleaseGroupID/MBID útil para tracklist/cover
  final String? releaseGroupId;

  /// Opciones de carátula (máx 5)
  final List<CoverCandidate> coverCandidates;

  /// Por defecto: la primera opción
  CoverCandidate? selectedCover;

  PreparedVinylAdd({
    required this.artist,
    required this.album,
    required this.coverCandidates,
    this.selectedCover,
    this.year,
    this.genre,
    this.country,
    this.bioShort,
    this.releaseGroupId,
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
      year: (meta.year ?? '').trim().isEmpty ? null : meta.year!.trim(),
      genre: (meta.genre ?? '').trim().isEmpty ? null : meta.genre!.trim(),
      country: country.isEmpty ? null : country,
      bioShort: bioShort,
      releaseGroupId: (meta.releaseGroupId ?? '').trim().isEmpty ? null : meta.releaseGroupId!.trim(),
    );

    return prepared;
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

    // Descargar carátula (si hay). Intentamos con la seleccionada.
    String? coverPath;
    final coverUrl = (prepared.selectedCover500 ?? '').trim();
    if (coverUrl.isNotEmpty) {
      coverPath = await _downloadCoverToLocal(coverUrl);
      // si falla, NO bloqueamos: se guarda igual, pero sin cover
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
}

