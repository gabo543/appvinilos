/// Normaliza strings para usarlos como claves (artistKey, etc.).
///
/// - lowercase
/// - quita acentos comunes
/// - reemplaza símbolos por espacios
/// - colapsa espacios
String normalizeKey(String input) {
  var out = input.toLowerCase().trim();

  const rep = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
    'ñ': 'n',
  };

  rep.forEach((k, v) => out = out.replaceAll(k, v));

  // Conserva letras, números, # y espacios.
  out = out.replaceAll(RegExp(r'[^a-z0-9# ]'), ' ');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  return out;
}
