import 'dart:convert';

import 'package:http/http.dart' as http;

class BarcodeReleaseHit {
  final String barcode;
  final String artist;
  final String album;
  final String? artistId;
  final String? releaseId;
  final String? releaseGroupId;
  final String? year;
  final String? country;
  final bool isVinyl;
  final String? mediaFormat;

  /// MusicBrainz puede incluir `cover-art-archive` para indicar si existe carátula.
  ///
  /// Esto nos sirve para priorizar resultados al escanear.
  final bool hasFrontCover;

  BarcodeReleaseHit({
    required this.barcode,
    required this.artist,
    required this.album,
    this.artistId,
    this.releaseId,
    this.releaseGroupId,
    this.year,
    this.country,
    this.isVinyl = false,
    this.mediaFormat,
    this.hasFrontCover = false,
  });
}

/// Lookup de releases por código de barras (EAN/UPC) usando MusicBrainz.
///
/// MusicBrainz permite buscar releases por el campo `barcode`.
/// Ver:
/// - MusicBrainz API Search: https://musicbrainz.org/doc/MusicBrainz_API/Search
/// - ReleaseSearch fields (incluye `barcode`): https://wiki.musicbrainz.org/MusicBrainz_API/Search/ReleaseSearch
class BarcodeLookupService {
  static const _mbBase = 'https://musicbrainz.org/ws/2';

  // Respeta el rate-limit recomendado (1 req/seg) como el resto de servicios.
  static DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<void> _throttle() async {
    final now = DateTime.now();
    final diff = now.difference(_lastCall);
    if (diff.inMilliseconds < 1100) {
      await Future.delayed(Duration(milliseconds: 1100 - diff.inMilliseconds));
    }
    _lastCall = DateTime.now();
  }

  static Map<String, String> _headers() => {
        'User-Agent': 'GaBoLP/1.0 (contact: gabo.hachim@gmail.com)',
        'Accept': 'application/json',
      };

  static String _artistCreditToString(List credit) {
    final buf = StringBuffer();
    for (final c in credit) {
      if (c is! Map<String, dynamic>) continue;
      final name = (c['name'] as String?)?.trim();
      final join = (c['joinphrase'] as String?) ?? '';
      if (name == null || name.isEmpty) continue;
      buf.write(name);
      buf.write(join);
    }
    final out = buf.toString().trim();
    return out.isEmpty ? 'Desconocido' : out;
  }

  static String? _yearFromDate(String? date) {
    final d = (date ?? '').trim();
    if (d.length >= 4) return d.substring(0, 4);
    return null;
  }

  /// Busca releases asociados a un código de barras.
  ///
  /// Devuelve una lista ordenada por score (MusicBrainz), reducida a un máximo razonable.
  static Future<List<BarcodeReleaseHit>> searchReleasesByBarcode(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return [];

    await _throttle();

    // MusicBrainz search (releases)
    final q = 'barcode:$code';
    // Intentamos pedir información de medios para priorizar Vinilos cuando esté disponible.
    final url = Uri.parse(
      '$_mbBase/release/?query=${Uri.encodeQueryComponent(q)}&fmt=json&limit=20&inc=media+release-groups+artist-credits+cover-art-archive',
    );

    late http.Response res;
    try {
      res = await http.get(url, headers: _headers()).timeout(const Duration(seconds: 15));
    } catch (_) {
      return [];
    }
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final releases = (data['releases'] as List?) ?? [];

    final out = <BarcodeReleaseHit>[];

    for (final r in releases) {
      if (r is! Map<String, dynamic>) continue;

      final title = (r['title'] as String?)?.trim();
      if (title == null || title.isEmpty) continue;

      final releaseId = (r['id'] as String?)?.trim();
      final rg = r['release-group'];
      String? releaseGroupId;
      if (rg is Map<String, dynamic>) {
        releaseGroupId = (rg['id'] as String?)?.trim();
      }

      final credit = (r['artist-credit'] as List?) ?? [];
      final artistName = _artistCreditToString(credit);

      String? artistId;
      if (credit.isNotEmpty && credit.first is Map<String, dynamic>) {
        final first = credit.first as Map<String, dynamic>;
        final a = first['artist'];
        if (a is Map<String, dynamic>) {
          artistId = (a['id'] as String?)?.trim();
        }
      }

      final date = (r['date'] as String?)?.trim();
      final year = _yearFromDate(date);
      final country = (r['country'] as String?)?.trim();

      // Detecta formato Vinyl si la respuesta incluye `media`.
      bool isVinyl = false;
      String? mediaFormat;
      final media = r['media'];
      if (media is List) {
        for (final m in media) {
          if (m is! Map<String, dynamic>) continue;
          final f = (m['format'] as String?)?.trim() ?? '';
          if (f.isNotEmpty && mediaFormat == null) mediaFormat = f;
          if (f.toLowerCase().contains('vinyl')) {
            isVinyl = true;
            mediaFormat = f;
            break;
          }
        }
      }

      // ¿Existe carátula? (si está disponible en el search payload)
      bool hasFrontCover = false;
      final caa = r['cover-art-archive'];
      if (caa is Map<String, dynamic>) {
        hasFrontCover = (caa['front'] == true);
      }

      out.add(
        BarcodeReleaseHit(
          barcode: code,
          artist: artistName,
          album: title,
          artistId: artistId,
          releaseId: releaseId,
          releaseGroupId: releaseGroupId,
          year: year,
          country: country,
          isVinyl: isVinyl,
          mediaFormat: mediaFormat,
          hasFrontCover: hasFrontCover,
        ),
      );
    }

    // MusicBrainz ya ordena por relevancia, pero filtramos duplicados obvios.
    final seen = <String>{};
    final dedup = <BarcodeReleaseHit>[];
    for (final h in out) {
      final key = '${h.artist.toLowerCase()}||${h.album.toLowerCase()}||${h.releaseGroupId ?? ''}';
      if (seen.contains(key)) continue;
      seen.add(key);
      dedup.add(h);
      if (dedup.length >= 10) break;
    }

    // Preferimos Vinilos primero (si tenemos info), manteniendo un orden estable por defecto.
    dedup.sort((a, b) {
      if (a.isVinyl == b.isVinyl) return 0;
      return a.isVinyl ? -1 : 1;
    });

    return dedup;
  }

  /// Busca releases por texto (artista/álbum) usando MusicBrainz.
  ///
  /// Se usa en el modo "Carátula": se hace OCR y luego se busca con el texto obtenido.
  ///
  /// `query` puede ser simple ("pink floyd animals") o una query más precisa
  /// tipo: `artist:"Pink Floyd" AND release:"Animals"`.
  static Future<List<BarcodeReleaseHit>> searchReleasesByText(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    await _throttle();

    final url = Uri.parse(
      '$_mbBase/release/?query=${Uri.encodeQueryComponent(q)}&fmt=json&limit=20&inc=media+release-groups+artist-credits+cover-art-archive',
    );

    late http.Response res;
    try {
      res = await http.get(url, headers: _headers()).timeout(const Duration(seconds: 15));
    } catch (_) {
      return [];
    }
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final releases = (data['releases'] as List?) ?? [];

    final out = <BarcodeReleaseHit>[];

    for (final r in releases) {
      if (r is! Map<String, dynamic>) continue;

      final title = (r['title'] as String?)?.trim();
      if (title == null || title.isEmpty) continue;

      final releaseId = (r['id'] as String?)?.trim();
      final rg = r['release-group'];
      String? releaseGroupId;
      if (rg is Map<String, dynamic>) {
        releaseGroupId = (rg['id'] as String?)?.trim();
      }

      final credit = (r['artist-credit'] as List?) ?? [];
      final artistName = _artistCreditToString(credit);

      String? artistId;
      if (credit.isNotEmpty && credit.first is Map<String, dynamic>) {
        final first = credit.first as Map<String, dynamic>;
        final a = first['artist'];
        if (a is Map<String, dynamic>) {
          artistId = (a['id'] as String?)?.trim();
        }
      }

      final date = (r['date'] as String?)?.trim();
      final year = _yearFromDate(date);
      final country = (r['country'] as String?)?.trim();

      bool isVinyl = false;
      String? mediaFormat;
      final media = r['media'];
      if (media is List) {
        for (final m in media) {
          if (m is! Map<String, dynamic>) continue;
          final f = (m['format'] as String?)?.trim() ?? '';
          if (f.isNotEmpty && mediaFormat == null) mediaFormat = f;
          if (f.toLowerCase().contains('vinyl')) {
            isVinyl = true;
            mediaFormat = f;
            break;
          }
        }
      }

      bool hasFrontCover = false;
      final caa = r['cover-art-archive'];
      if (caa is Map<String, dynamic>) {
        hasFrontCover = (caa['front'] == true);
      }

      out.add(
        BarcodeReleaseHit(
          barcode: q,
          artist: artistName,
          album: title,
          artistId: artistId,
          releaseId: releaseId,
          releaseGroupId: releaseGroupId,
          year: year,
          country: country,
          isVinyl: isVinyl,
          mediaFormat: mediaFormat,
          hasFrontCover: hasFrontCover,
        ),
      );
    }

    final seen = <String>{};
    final dedup = <BarcodeReleaseHit>[];
    for (final h in out) {
      final key = '${h.artist.toLowerCase()}||${h.album.toLowerCase()}||${h.releaseGroupId ?? ''}';
      if (seen.contains(key)) continue;
      seen.add(key);
      dedup.add(h);
      if (dedup.length >= 10) break;
    }

    dedup.sort((a, b) {
      if (a.isVinyl == b.isVinyl) return 0;
      return a.isVinyl ? -1 : 1;
    });

    return dedup;
  }
}
