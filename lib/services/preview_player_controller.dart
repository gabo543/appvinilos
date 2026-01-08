import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

enum PreviewPlaybackStatus {
  stopped,
  loading,
  playing,
  paused,
  error,
}

/// Reproductor único de previews (máx 30s) para toda la app.
///
/// - Mantiene un solo AudioPlayer para evitar que suenen múltiples audios.
/// - Corta automáticamente al llegar a 30 segundos de reproducción.
class PreviewPlayerController {
  PreviewPlayerController._();

  static final PreviewPlayerController instance = PreviewPlayerController._();

  final AudioPlayer _player = AudioPlayer();

  final ValueNotifier<String?> currentKey = ValueNotifier<String?>(null);
  final ValueNotifier<PreviewPlaybackStatus> status =
      ValueNotifier<PreviewPlaybackStatus>(PreviewPlaybackStatus.stopped);

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;
  bool _sessionReady = false;

  // Token para cancelar operaciones en curso (setUrl/play) cuando el usuario
  // presiona Stop o inicia otra reproducción.
  int _token = 0;

  /// Marca una pista como "activa" inmediatamente, incluso antes de resolver
  /// el previewUrl o de que el audio comience a sonar. Esto permite que el UI
  /// cambie a ⏹ Stop al instante.
  void markPending(String key) {
    currentKey.value = key;
    status.value = PreviewPlaybackStatus.loading;
  }

  Future<void> _ensureSession() async {
    if (_sessionReady) return;
    _sessionReady = true;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {
      // silencioso
    }

    _stateSub ??= _player.playerStateStream.listen((s) {
      final ps = s.processingState;
      if (ps == ProcessingState.loading || ps == ProcessingState.buffering) {
        status.value = PreviewPlaybackStatus.loading;
        return;
      }
      if (ps == ProcessingState.completed) {
        // Se completó (o llegó a 30s y se detuvo) → dejamos listo.
        status.value = PreviewPlaybackStatus.stopped;
        currentKey.value = null;
        return;
      }

      if (s.playing) {
        status.value = PreviewPlaybackStatus.playing;
      } else {
        // Pausa/stop
        if (currentKey.value == null) {
          status.value = PreviewPlaybackStatus.stopped;
        } else {
          status.value = PreviewPlaybackStatus.paused;
        }
      }
    });

    _posSub ??= _player.positionStream.listen((pos) async {
      // Cortamos a los 30 segundos SI se está reproduciendo.
      if (currentKey.value == null) return;
      if (!_player.playing) return;
      if (pos >= const Duration(seconds: 30)) {
        await stop();
      }
    });
  }

  bool isPlayingKey(String key) =>
      currentKey.value == key && status.value == PreviewPlaybackStatus.playing;

  bool isPausedKey(String key) =>
      currentKey.value == key && status.value == PreviewPlaybackStatus.paused;

  Future<void> play({required String key, required String url}) async {
    await _ensureSession();
    final int myToken = ++_token;
    try {
      // Cambiamos el UI a "Stop" de inmediato.
      markPending(key);

      await _player.stop();
      if (myToken != _token) return;

      await _player.setUrl(url);
      if (myToken != _token) return;

      await _player.seek(Duration.zero);
      if (myToken != _token) return;

      await _player.play();
      if (myToken != _token) return;
    } catch (_) {
      if (myToken == _token) {
        status.value = PreviewPlaybackStatus.error;
        currentKey.value = null;
      }
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause();
      status.value = PreviewPlaybackStatus.paused;
    } catch (_) {
      // ignore
    }
  }

  Future<void> stop() async {
    // Invalida cualquier operación en curso.
    ++_token;
    try {
      await _player.stop();
    } catch (_) {
      // ignore
    }
    currentKey.value = null;
    status.value = PreviewPlaybackStatus.stopped;
  }

  Future<void> toggle({required String key, required String url}) async {
    final ck = currentKey.value;
    final st = status.value;

    if (ck == key && st == PreviewPlaybackStatus.playing) {
      await pause();
      return;
    }
    if (ck == key && st == PreviewPlaybackStatus.paused) {
      // Reanudar (mantiene posición)
      try {
        await _player.play();
        status.value = PreviewPlaybackStatus.playing;
      } catch (_) {
        status.value = PreviewPlaybackStatus.error;
      }
      return;
    }

    // Otra canción (o estaba detenido)
    await play(key: key, url: url);
  }

  Future<void> dispose() async {
    await _posSub?.cancel();
    await _stateSub?.cancel();
    await _player.dispose();
  }
}
