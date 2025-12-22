import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persiste y notifica el "diseño" (tema) y la intensidad de texto elegida.
///
/// Tema:
/// 1 = Diseño 1 (Pro oscuro)
/// 2 = Diseño 2 (Claro premium)
/// 3 = Diseño 3 (Minimal oscuro)
/// 4 = Diseño 4 (Pastel Citrus)
/// 5 = Diseño 5 (Pastel Sky)
///
/// Intensidad de texto:
/// 0 = suave
/// 1 = normal
/// 2 = alto
/// 3 = máximo
class AppThemeService {
  static const String _kTheme = 'app_theme_variant';
  static const String _kTextIntensity = 'app_text_intensity';

  static final ValueNotifier<int> themeNotifier = ValueNotifier<int>(1);
  static final ValueNotifier<int> textIntensityNotifier = ValueNotifier<int>(2);

  static int _clampTheme(int v) => (v < 1 || v > 5) ? 1 : v;
  static int _clampIntensity(int v) => (v < 0 || v > 3) ? 2 : v;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    themeNotifier.value = _clampTheme(prefs.getInt(_kTheme) ?? 1);
    textIntensityNotifier.value = _clampIntensity(prefs.getInt(_kTextIntensity) ?? 2);
  }

  static Future<void> setTheme(int v) async {
    final next = _clampTheme(v);
    themeNotifier.value = next; // ✅ instantáneo
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTheme, next);
  }

  static Future<int> getTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return _clampTheme(prefs.getInt(_kTheme) ?? 1);
  }

  static Future<void> setTextIntensity(int v) async {
    final next = _clampIntensity(v);
    textIntensityNotifier.value = next; // ✅ instantáneo
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTextIntensity, next);
  }

  static Future<int> getTextIntensity() async {
    final prefs = await SharedPreferences.getInstance();
    return _clampIntensity(prefs.getInt(_kTextIntensity) ?? 2);
  }
}
