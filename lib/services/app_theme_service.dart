import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
/// 1..10 (más niveles = más contraste)
class AppThemeService {
  static const String _kTheme = 'app_theme_variant';
  static const String _kTextIntensity = 'app_text_intensity';
  static const String _kBgLevel = 'app_bg_level';
  static const String _kCardLevel = 'app_card_level';
  static const String _kCardBorderStyle = 'app_card_border_style';

  static final ValueNotifier<int> themeNotifier = ValueNotifier<int>(1);
  // 1..10
  static final ValueNotifier<int> textIntensityNotifier = ValueNotifier<int>(6);
  // 1..10
  static final ValueNotifier<int> bgLevelNotifier = ValueNotifier<int>(5);
  // 1..10
  static final ValueNotifier<int> cardLevelNotifier = ValueNotifier<int>(5);

  // 1..10 (color del borde / contorno de cards)
  static final ValueNotifier<int> cardBorderStyleNotifier = ValueNotifier<int>(1);

  static int _clampTheme(int v) => (v < 1 || v > 6) ? 1 : v;
  static int _clampIntensity(int v) => v.clamp(1, 10);
  static int _clampLevel(int v) => v.clamp(1, 10);
  static int _clampBorderStyle(int v) => v.clamp(1, 10);

  /// Paleta 1..10 para el borde de los cards.
  /// Pensada para verse bien en tema oscuro y también en claro.
  static const List<Color> _borderPalette = <Color>[
    Color(0xFFF2F2F2), // 1 Blanco suave
    Color(0xFFB9C0CC), // 2 Gris frío
    Color(0xFFC7BDB3), // 3 Gris cálido
    Color(0xFF9FE7C9), // 4 Verde menta
    Color(0xFFB8D8A8), // 5 Verde salvia
    Color(0xFFFFB1B1), // 6 Rojo rosado
    Color(0xFFFFC9A8), // 7 Durazno
    Color(0xFFC79A6B), // 8 Bronce suave
    Color(0xFFC7A6FF), // 9 Lila
    Color(0xFFA9D3FF), // 10 Azul hielo
  ];

  /// Color base (sin opacidad) según índice 1..10.
  static Color borderBaseColor(int style1to10) {
    final i = _clampBorderStyle(style1to10) - 1;
    return _borderPalette[i];
  }

  // Migración: versiones antiguas guardaban 0..4 en niveles visuales.
  static int _migrateOldLevel(int v) {
    if (v <= 4) {
      // 0..4 -> 1..10
      final mapped = ((v / 4.0) * 9.0).round() + 1;
      return _clampLevel(mapped);
    }
    return _clampLevel(v);
  }

  // Migración: versiones antiguas guardaban 0..10 en intensidad.
  static int _migrateOldIntensity(int v) {
    if (v <= 0) return 1;
    return _clampIntensity(v);
  }

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    themeNotifier.value = _clampTheme(prefs.getInt(_kTheme) ?? 1);
    textIntensityNotifier.value = _migrateOldIntensity(prefs.getInt(_kTextIntensity) ?? 6);
    bgLevelNotifier.value = _migrateOldLevel(prefs.getInt(_kBgLevel) ?? 5);
    cardLevelNotifier.value = _migrateOldLevel(prefs.getInt(_kCardLevel) ?? 5);
    cardBorderStyleNotifier.value = _clampBorderStyle(prefs.getInt(_kCardBorderStyle) ?? 1);
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
    return _migrateOldIntensity(prefs.getInt(_kTextIntensity) ?? 6);
  }

  static Future<void> setBackgroundLevel(int v) async {
    final next = _clampLevel(v);
    bgLevelNotifier.value = next; // ✅ instantáneo
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBgLevel, next);
  }

  static Future<int> getBackgroundLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return _migrateOldLevel(prefs.getInt(_kBgLevel) ?? 5);
  }

  static Future<void> setCardLevel(int v) async {
    final next = _clampLevel(v);
    cardLevelNotifier.value = next; // ✅ instantáneo
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCardLevel, next);
  }

  static Future<int> getCardLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return _migrateOldLevel(prefs.getInt(_kCardLevel) ?? 5);
  }

  static Future<void> setCardBorderStyle(int v) async {
    final next = _clampBorderStyle(v);
    cardBorderStyleNotifier.value = next; // ✅ instantáneo
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCardBorderStyle, next);
  }

  static Future<int> getCardBorderStyle() async {
    final prefs = await SharedPreferences.getInstance();
    return _clampBorderStyle(prefs.getInt(_kCardBorderStyle) ?? 1);
  }
  // Compat: nombres antiguos
  static Future<int> getBgLevel() => getBackgroundLevel();
  static Future<void> setBgLevel(int v) => setBackgroundLevel(v);

}
