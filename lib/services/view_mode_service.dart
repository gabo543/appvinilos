import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persiste la preferencia de vista (lista vs grid) para la lista de vinilos.
///
/// - false (default): vista lista
/// - true: vista grid
class ViewModeService {
  static const String _kGrid = 'vinyl_view_grid';

  /// Notificador en memoria para cambios instantáneos (sin esperar leer prefs).
  static final ValueNotifier<bool> gridNotifier = ValueNotifier<bool>(false);

  /// Carga la preferencia guardada (llamar 1 vez al inicio).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    gridNotifier.value = prefs.getBool(_kGrid) ?? false;
  }

  static Future<bool> isGridEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kGrid) ?? false;
  }

  static Future<void> setGridEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    // ✅ cambia instantáneo en memoria
    gridNotifier.value = value;
    await prefs.setBool(_kGrid, value);
  }
}
