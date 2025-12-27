import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Modos de vista para Vinilos/Favoritos.
///
/// - [VinylViewMode.list]: lista vertical
/// - [VinylViewMode.grid]: cuadrícula con tarjetas
/// - [VinylViewMode.cover]: solo carátula + número
enum VinylViewMode { list, grid, cover }

/// Servicio que persiste y notifica cambios del modo de vista.
///
/// Compatibilidad: versiones anteriores guardaban solo lista/grid en
/// `vinyl_view_grid` (bool). Si existe ese valor y no existe el nuevo,
/// se migra automáticamente.
class ViewModeService {
  // Nuevo (3 modos)
  static const String _kMode = 'vinyl_view_mode';

  // Legacy (2 modos)
  static const String _kLegacyGrid = 'vinyl_view_grid';

  /// Notificador en memoria para cambios instantáneos (sin esperar leer prefs).
  static final ValueNotifier<VinylViewMode> modeNotifier =
      ValueNotifier<VinylViewMode>(VinylViewMode.list);

  /// Carga la preferencia guardada (llamar 1 vez al inicio).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final idx = prefs.getInt(_kMode);
    if (idx != null && idx >= 0 && idx < VinylViewMode.values.length) {
      modeNotifier.value = VinylViewMode.values[idx];
      return;
    }

    // Compat: si venimos de la preferencia vieja, la migramos.
    final legacyGrid = prefs.getBool(_kLegacyGrid);
    if (legacyGrid != null) {
      modeNotifier.value = legacyGrid ? VinylViewMode.grid : VinylViewMode.list;
      await prefs.setInt(_kMode, modeNotifier.value.index);
      return;
    }

    modeNotifier.value = VinylViewMode.list;
  }

  static Future<VinylViewMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();

    final idx = prefs.getInt(_kMode);
    if (idx != null && idx >= 0 && idx < VinylViewMode.values.length) {
      return VinylViewMode.values[idx];
    }

    final legacyGrid = prefs.getBool(_kLegacyGrid);
    if (legacyGrid != null) {
      return legacyGrid ? VinylViewMode.grid : VinylViewMode.list;
    }

    return VinylViewMode.list;
  }

  static Future<void> setMode(VinylViewMode mode) async {
    final prefs = await SharedPreferences.getInstance();

    // ✅ cambia instantáneo en memoria
    modeNotifier.value = mode;

    await prefs.setInt(_kMode, mode.index);

    // Mantén el valor legacy sincronizado (sirve para backups viejos).
    await prefs.setBool(_kLegacyGrid, mode == VinylViewMode.grid);
  }

  // ----------------- API legacy (para no romper código/backups previos) -----------------
  static Future<bool> isGridEnabled() async => (await getMode()) == VinylViewMode.grid;

  static Future<void> setGridEnabled(bool value) async {
    await setMode(value ? VinylViewMode.grid : VinylViewMode.list);
  }
}
