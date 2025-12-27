import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persiste el idioma elegido por el usuario.
/// - 'es' (Español)
/// - 'en' (English)
///
/// Por defecto usamos Español para mantener compatibilidad con el contenido actual.
class LocaleService {
  static const String _kLocaleCode = 'app_locale_code';

  static final ValueNotifier<Locale> localeNotifier = ValueNotifier(const Locale('es'));

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLocaleCode);
    if (code == 'en') {
      localeNotifier.value = const Locale('en');
    } else {
      // Default + fallback
      localeNotifier.value = const Locale('es');
    }
  }

  static String get code => localeNotifier.value.languageCode;

  static Future<void> setCode(String code) async {
    final safe = (code == 'en') ? 'en' : 'es';
    localeNotifier.value = Locale(safe);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleCode, safe);
  }

  static Future<void> toggleEsEn() async {
    await setCode(code == 'en' ? 'es' : 'en');
  }
}
