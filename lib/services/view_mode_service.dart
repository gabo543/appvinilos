import 'package:shared_preferences/shared_preferences.dart';

/// Persiste la preferencia de vista (lista vs grid) para la lista de vinilos.
///
/// - false (default): vista lista
/// - true: vista grid
class ViewModeService {
  static const String _kGrid = 'vinyl_view_grid';

  static Future<bool> isGridEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kGrid) ?? false;
  }

  static Future<void> setGridEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGrid, value);
  }
}
