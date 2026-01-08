import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../services/preview_player_controller.dart';
import '../../services/track_preview_service.dart';

/// Botón Play/Stop para previews de canciones (máx 30s).
///
/// - Muestra ▶️ por defecto.
/// - Muestra ⏹️ si esta pista está reproduciendo (o cargando dentro del player).
/// - Si no hay preview disponible, muestra un SnackBar.
class TrackPreviewButton extends StatefulWidget {
  final String cacheKey;
  final String artist;
  final String title;
  final String? album;

  final double iconSize;
  final bool compact;

  const TrackPreviewButton({
    super.key,
    required this.cacheKey,
    required this.artist,
    required this.title,
    this.album,
    this.iconSize = 20,
    this.compact = true,
  });

  @override
  State<TrackPreviewButton> createState() => _TrackPreviewButtonState();
}

class _TrackPreviewButtonState extends State<TrackPreviewButton> {
  bool _loading = false;
  int _opToken = 0; // permite cancelar una búsqueda/reproducción en curso

  Future<void> _snack(String text) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr(text))),
    );
  }

  Future<void> _onTap() async {
    final player = PreviewPlayerController.instance;

    final key = widget.cacheKey;
    final st = player.status.value;
    final ck = player.currentKey.value;

    // Si esta pista está activa → stop inmediato (por si no quiere escuchar los 30s).
    final isThis = ck == key;
    final isActive = isThis &&
        (st == PreviewPlaybackStatus.playing ||
            st == PreviewPlaybackStatus.paused ||
            st == PreviewPlaybackStatus.loading);
    if (isActive) {
      // Cancela operaciones en curso (HTTP / setUrl) y detiene.
      ++_opToken;
      if (mounted) setState(() => _loading = false);
      await player.stop();
      return;
    }

    if (_loading) return;

    final int myOp = ++_opToken;
    setState(() => _loading = true);
    try {
      // Cambia el botón a ⏹ inmediatamente, incluso mientras buscamos el preview.
      player.markPending(key);

      final preview = await TrackPreviewService.findPreview(
        cacheKey: key,
        artist: widget.artist,
        title: widget.title,
        album: widget.album,
      );

      // Si el usuario presionó Stop mientras cargaba, ignoramos este resultado.
      if (myOp != _opToken) return;

      if (preview == null || preview.previewUrl.trim().isEmpty) {
        await _snack('No hay preview disponible.');
        await player.stop();
        return;
      }
      await player.play(key: key, url: preview.previewUrl);
    } catch (_) {
      await _snack('No pude reproducir el preview.');
      if (myOp == _opToken) {
        await player.stop();
      }
    } finally {
      if (mounted && myOp == _opToken) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = PreviewPlayerController.instance;

    final btnConstraints = widget.compact
        ? const BoxConstraints.tightFor(width: 36, height: 36)
        : null;

    return ValueListenableBuilder<String?>(
      valueListenable: player.currentKey,
      builder: (context, ck, _) {
        return ValueListenableBuilder<PreviewPlaybackStatus>(
          valueListenable: player.status,
          builder: (context, st, __) {
            final isThis = ck == widget.cacheKey;
            final active = isThis &&
                (st == PreviewPlaybackStatus.playing ||
                    st == PreviewPlaybackStatus.paused ||
                    st == PreviewPlaybackStatus.loading);

            // Solo deshabilitamos durante la búsqueda de preview (HTTP),
            // no durante el loading interno del player, para permitir "Stop".
            final loading = _loading;

            // Si la pista está activa o pending, SIEMPRE mostramos Stop.
            // Esto permite detener incluso si el preview aún se está resolviendo.
            Widget icon;
            if (active) {
              icon = Icon(Icons.stop, size: widget.iconSize);
            } else if (loading) {
              icon = SizedBox(
                width: widget.iconSize,
                height: widget.iconSize,
                child: const CircularProgressIndicator(strokeWidth: 2),
              );
            } else {
              icon = Icon(Icons.play_arrow, size: widget.iconSize);
            }

            return IconButton(
              tooltip: active ? context.tr('Detener') : context.tr('Escuchar preview'),
              // No deshabilizamos: si está active/pending, _onTap hará Stop.
              onPressed: _onTap,
              constraints: btnConstraints,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: icon,
            );
          },
        );
      },
    );
  }
}
