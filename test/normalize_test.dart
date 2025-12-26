import 'package:flutter_test/flutter_test.dart';

import 'package:gabolp/utils/normalize.dart';

void main() {
  test('normalizeKey removes accents and normalizes spaces', () {
    expect(normalizeKey('  Piñk   Flóyd  '), 'pink floyd');
    expect(normalizeKey('AC/DC'), 'ac dc');
    expect(normalizeKey('Björk'), 'bjork');
  });
}
