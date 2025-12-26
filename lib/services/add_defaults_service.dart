import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias simples para que el flujo de "agregar vinilo" sea más rápido.
///
/// Guarda las últimas opciones usadas (condición y formato) para prellenarlas
/// automáticamente la próxima vez.
class AddDefaultsService {
  static const String _kLastCondition = 'add_last_condition';
  static const String _kLastFormat = 'add_last_format';

  static Future<String> getLastCondition({String fallback = 'VG+'}) async {
    final prefs = await SharedPreferences.getInstance();
    final v = (prefs.getString(_kLastCondition) ?? '').trim();
    return v.isEmpty ? fallback : v;
  }

  static Future<String> getLastFormat({String fallback = 'LP'}) async {
    final prefs = await SharedPreferences.getInstance();
    final v = (prefs.getString(_kLastFormat) ?? '').trim();
    return v.isEmpty ? fallback : v;
  }

  static Future<void> saveLast({required String condition, required String format}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastCondition, condition.trim().isEmpty ? 'VG+' : condition.trim());
    await prefs.setString(_kLastFormat, format.trim().isEmpty ? 'LP' : format.trim());
  }
}
