import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencia UI: mostrar texto pequeño bajo las carátulas en "Últimos agregados".
///
/// - true  -> muestra texto pequeño debajo
/// - false -> solo carátula (más grande)
class RecentAddedTextService {
  static const String _k = 'recent_show_text';

  /// Notifier global (cambio instantáneo sin reiniciar).
  static final ValueNotifier<bool> notifier = ValueNotifier<bool>(false);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    notifier.value = p.getBool(_k) ?? false;
  }

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_k) ?? false;
  }

  static Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_k, v);
    notifier.value = v;
  }
}
