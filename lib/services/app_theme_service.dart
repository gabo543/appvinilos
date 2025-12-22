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
/// 6 = Diseño 6 (Rasta Vibes)
///
/// Intensidad de texto (contraste global):
/// 0..10 (más niveles = más contraste)
class AppThemeService {
  static const String _kTheme = 'app_theme_variant';
  static const String _kTextIntensity = 'app_text_intensity';
  static const String _kBgLevel = 'app_bg_level';
  static const String _kCardLevel = 'app_card_level';

  static final ValueNotifier<int> themeNotifier = ValueNotifier<int>(1);
  // 0..10
  static final ValueNotifier<int> textIntensityNotifier = ValueNotifier<int>(5);
  // 0..4
  static final ValueNotifier<int> bgLevelNotifier = ValueNotifier<int>(2);
  // 0..4
  static final ValueNotifier<int> cardLevelNotifier = ValueNotifier<int>(2);

  static int _clampTheme(int v) => (v < 1 || v > 6) ? 1 : v;
  static int _clampIntensity(int v) => v.clamp(0, 10);
  static int _clampLevel(int v) => v.clamp(0, 4);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    themeNotifier.value = _clampTheme(prefs.getInt(_kTheme) ?? 1);
    textIntensityNotifier.value = _clampIntensity(prefs.getInt(_kTextIntensity) ?? 5);
    bgLevelNotifier.value = _clampLevel(prefs.getInt(_kBgLevel) ?? 2);
    cardLevelNotifier.value = _clampLevel(prefs.getInt(_kCardLevel) ?? 2);
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

  static Future<void> setBackgroundLevel(int v) async {
    final next = _clampLevel(v);
    bgLevelNotifier.value = next; // ✅ instantáneo
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBgLevel, next);
  }

  static Future<int> getBackgroundLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return _clampLevel(prefs.getInt(_kBgLevel) ?? 2);
  }

  static Future<void> setCardLevel(int v) async {
    final next = _clampLevel(v);
    cardLevelNotifier.value = next; // ✅ instantáneo
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCardLevel, next);
  }

  static Future<int> getCardLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return _clampLevel(prefs.getInt(_kCardLevel) ?? 2);
  }
  // Compat: nombres antiguos
  static Future<int> getBgLevel() => getBackgroundLevel();
  static Future<void> setBgLevel(int v) => setBackgroundLevel(v);

}
