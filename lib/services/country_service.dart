import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CountryOption {
  /// ISO 3166-1 alpha-2 (ej: CL, FI, US)
  final String code;

  /// Nombre en español si existe (translations.spa.common), si no name.common
  final String name;

  const CountryOption({required this.code, required this.name});

  Map<String, dynamic> toJson() => {'code': code, 'name': name};

  static CountryOption? fromJson(dynamic v) {
    if (v is! Map) return null;
    final code = (v['code'] ?? '').toString().trim().toUpperCase();
    final name = (v['name'] ?? '').toString().trim();
    if (code.length != 2 || name.isEmpty) return null;
    return CountryOption(code: code, name: name);
  }

  @override
  String toString() => name;
}

class CountryService {
  static const String _prefsKey = 'countries_all_v1';
  static const String _prefsTsKey = 'countries_all_ts_v1';
  static const Duration _ttl = Duration(days: 30);

  static List<CountryOption>? _mem;
  static int _memTs = 0;

  static Future<List<CountryOption>> getAllCountries({bool forceRefresh = false}) async {
    if (!forceRefresh && _mem != null && _mem!.isNotEmpty) {
      final dt = DateTime.fromMillisecondsSinceEpoch(_memTs);
      if (DateTime.now().difference(dt) <= _ttl) return _mem!;
    }

    if (!forceRefresh) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final ts = prefs.getInt(_prefsTsKey) ?? 0;
        final raw = prefs.getString(_prefsKey);
        if (ts > 0 && raw != null && raw.trim().isNotEmpty) {
          final dt = DateTime.fromMillisecondsSinceEpoch(ts);
          if (DateTime.now().difference(dt) <= _ttl) {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              final list = decoded
                  .map((e) => CountryOption.fromJson(e))
                  .whereType<CountryOption>()
                  .toList()
                ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
              if (list.isNotEmpty) {
                _mem = list;
                _memTs = ts;
                return list;
              }
            }
          }
        }
      } catch (_) {
        // ignore
      }
    }

    // RestCountries: usamos fields para bajar el tamaño de payload.
    final url = Uri.parse('https://restcountries.com/v3.1/all?fields=cca2,name,translations');
    final res = await http
        .get(url, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      if (_mem != null) return _mem!;
      return const <CountryOption>[];
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! List) return const <CountryOption>[];

    final out = <CountryOption>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final code = (item['cca2'] ?? '').toString().trim().toUpperCase();
      if (code.length != 2) continue;

      String name = '';
      final translations = item['translations'];
      if (translations is Map) {
        final spa = translations['spa'];
        if (spa is Map) {
          name = (spa['common'] ?? spa['official'] ?? '').toString().trim();
        }
      }
      if (name.isEmpty) {
        final n = item['name'];
        if (n is Map) name = (n['common'] ?? n['official'] ?? '').toString().trim();
      }
      if (name.isEmpty) continue;

      out.add(CountryOption(code: code, name: name));
    }

    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(out.map((e) => e.toJson()).toList()));
      await prefs.setInt(_prefsTsKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // ignore
    }

    _mem = out;
    _memTs = DateTime.now().millisecondsSinceEpoch;
    return out;
  }

  static Iterable<CountryOption> suggest(List<CountryOption> all, String q, {int limit = 12}) {
    final query = _norm(q);
    if (query.isEmpty) return const Iterable<CountryOption>.empty();

    // Si escribe código (2 letras), priorizamos matches por código.
    if (query.length == 2) {
      final code = query.toUpperCase();
      final byCode = all.where((c) => c.code == code);
      if (byCode.isNotEmpty) return byCode.take(limit);
    }

    final starts = <CountryOption>[];
    final contains = <CountryOption>[];

    for (final c in all) {
      final n = _norm(c.name);
      if (n.startsWith(query)) {
        starts.add(c);
      } else if (n.contains(query)) {
        contains.add(c);
      }
    }

    final merged = [...starts, ...contains];
    return merged.take(limit);
  }

  static String _norm(String s) => s.toLowerCase().trim();
}
