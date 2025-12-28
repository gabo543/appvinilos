import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Historial liviano de escaneos/búsquedas recientes.
///
/// Guardamos sólo lo necesario para volver a abrir la ficha:
/// artista, álbum y (si existe) MB releaseGroupId/releaseId.
class RecentScanEntry {
  final String artist;
  final String album;
  final String? releaseGroupId;
  final String? releaseId;
  final String source; // barcode | cover | listen
  final int tsMs;

  const RecentScanEntry({
    required this.artist,
    required this.album,
    this.releaseGroupId,
    this.releaseId,
    required this.source,
    required this.tsMs,
  });

  Map<String, dynamic> toJson() => {
        'artist': artist,
        'album': album,
        'rgid': releaseGroupId,
        'rid': releaseId,
        'source': source,
        'ts': tsMs,
      };

  static RecentScanEntry? fromJson(dynamic raw) {
    try {
      if (raw is String) raw = jsonDecode(raw);
      if (raw is! Map<String, dynamic>) return null;
      final artist = (raw['artist'] as String?)?.trim() ?? '';
      final album = (raw['album'] as String?)?.trim() ?? '';
      if (artist.isEmpty || album.isEmpty) return null;
      final rgid = (raw['rgid'] as String?)?.trim();
      final rid = (raw['rid'] as String?)?.trim();
      final source = (raw['source'] as String?)?.trim() ?? 'scan';
      final ts = (raw['ts'] as num?)?.toInt() ?? 0;
      return RecentScanEntry(
        artist: artist,
        album: album,
        releaseGroupId: (rgid == null || rgid.isEmpty) ? null : rgid,
        releaseId: (rid == null || rid.isEmpty) ? null : rid,
        source: source,
        tsMs: ts > 0 ? ts : DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      return null;
    }
  }
}

class RecentScansService {
  static const _prefsKey = 'recent_scans_v1';
  static const int _max = 10;

  static Future<List<RecentScanEntry>> getRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsKey) ?? const <String>[];
      final out = <RecentScanEntry>[];
      for (final s in list) {
        final e = RecentScanEntry.fromJson(s);
        if (e != null) out.add(e);
      }
      return out;
    } catch (_) {
      return const <RecentScanEntry>[];
    }
  }

  static Future<void> add(RecentScanEntry entry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsKey) ?? <String>[];

      // De-dup: si ya existe el mismo (artist+album+rgid), lo subimos arriba.
      final norm = _normKey(entry);
      final filtered = <String>[];
      for (final s in list) {
        final e = RecentScanEntry.fromJson(s);
        if (e == null) continue;
        if (_normKey(e) == norm) continue;
        filtered.add(s);
      }

      final newList = <String>[jsonEncode(entry.toJson()), ...filtered];
      if (newList.length > _max) newList.removeRange(_max, newList.length);
      await prefs.setStringList(_prefsKey, newList);
    } catch (_) {
      // ignore
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {
      // ignore
    }
  }

  static String _normKey(RecentScanEntry e) {
    final a = e.artist.toLowerCase().trim();
    final al = e.album.toLowerCase().trim();
    final rgid = (e.releaseGroupId ?? '').toLowerCase().trim();
    return '$a||$al||$rgid';
  }
}
