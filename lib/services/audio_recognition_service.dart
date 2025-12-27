import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Reconocimiento de audio ("modo escuchar").
///
/// Implementación cross-platform usando AudD (API). Funciona con un token
/// configurado por el usuario en Ajustes.
///
/// - Endpoint: https://api.audd.io/
/// - Se sube un archivo corto (ej. 8-10s) y devuelve track/artist/album (si existe).
///
/// Importante: el token lo guarda el usuario en el dispositivo.
class AudioRecognitionService {
  static const String _kTokenKey = 'audd_api_token';

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = (prefs.getString(_kTokenKey) ?? '').trim();
    return t.isEmpty ? null : t;
  }

  static Future<void> setToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    final t = (token ?? '').trim();
    if (t.isEmpty) {
      await prefs.remove(_kTokenKey);
    } else {
      await prefs.setString(_kTokenKey, t);
    }
  }

  static Future<AudioRecognitionResult> identifyFromFile(File audioFile) async {
    final token = await getToken();
    if (token == null) {
      return const AudioRecognitionResult.error(
        'Falta configurar el token. Ve a Ajustes → Reconocimiento (Escuchar).',
      );
    }

    if (!await audioFile.exists()) {
      return const AudioRecognitionResult.error('No se encontró el audio grabado.');
    }

    final uri = Uri.parse('https://api.audd.io/');
    final req = http.MultipartRequest('POST', uri);
    req.fields['api_token'] = token;
    req.fields['return'] = 'apple_music,spotify';
    req.files.add(await http.MultipartFile.fromPath('file', audioFile.path));

    http.StreamedResponse res;
    try {
      res = await req.send().timeout(const Duration(seconds: 30));
    } catch (_) {
      return const AudioRecognitionResult.error('No pude conectar con el servicio.');
    }

    final body = await res.stream.bytesToString();
    if (res.statusCode != 200) {
      return AudioRecognitionResult.error('Error del servicio (${res.statusCode}).');
    }

    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString().toLowerCase();
      if (status != 'success') {
        final msg = (data['error']?['error_message'] ?? 'No se pudo reconocer la canción.').toString();
        return AudioRecognitionResult.error(msg);
      }

      final r = data['result'];
      if (r is! Map<String, dynamic>) {
        return const AudioRecognitionResult.error('No se encontró resultado.');
      }

      final artist = (r['artist'] ?? '').toString().trim();
      final title = (r['title'] ?? '').toString().trim();
      final album = (r['album'] ?? '').toString().trim();
      final releaseDate = (r['release_date'] ?? '').toString().trim();

      if (artist.isEmpty && title.isEmpty) {
        return const AudioRecognitionResult.error('Resultado incompleto.');
      }

      return AudioRecognitionResult.ok(
        artist: artist.isEmpty ? 'Desconocido' : artist,
        title: title.isEmpty ? 'Desconocido' : title,
        album: album.isEmpty ? null : album,
        releaseDate: releaseDate.isEmpty ? null : releaseDate,
      );
    } catch (_) {
      return const AudioRecognitionResult.error('Respuesta inválida del servicio.');
    }
  }
}

class AudioRecognitionResult {
  final bool ok;
  final String? error;
  final String? artist;
  final String? title;
  final String? album;
  final String? releaseDate;

  const AudioRecognitionResult._({
    required this.ok,
    this.error,
    this.artist,
    this.title,
    this.album,
    this.releaseDate,
  });

  const AudioRecognitionResult.ok({
    required String artist,
    required String title,
    String? album,
    String? releaseDate,
  }) : this._(
          ok: true,
          artist: artist,
          title: title,
          album: album,
          releaseDate: releaseDate,
        );

  const AudioRecognitionResult.error(String message)
      : this._(
          ok: false,
          error: message,
        );
}
