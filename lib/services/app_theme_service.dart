import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persiste y notifica el "diseño" (tema) elegido por el usuario.
///
/// 1 = Diseño 1 (actual, oscuro pro)
/// 2 = Diseño 2 (B3: claro premium)
/// 3 = Diseño 3 (B1: minimal oscuro)
class AppThemeService {
  static const String _kTheme = 'app_theme_variant';

  static final ValueNotifier<int> themeNotifier = ValueNotifier<int>(1);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_kTheme) ?? 1;
    themeNotifier.value = (v < 1 || v > 3) ? 1 : v;
  }

  static Future<void> setTheme(int v) async {
    final next = (v < 1 || v > 3) ? 1 : v;
    themeNotifier.value = next; // ✅ instantáneo
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTheme, next);
  }

  static Future<int> getTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_kTheme) ?? 1;
    return (v < 1 || v > 3) ? 1 : v;
  }
}
