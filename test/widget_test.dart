import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gabolp/main.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const GaBoLpApp());
    // A very lightweight sanity check.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
