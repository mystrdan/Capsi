import 'package:capsi/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Capsi shell UI renders independently of native runtime', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CapsiHome(autoInitialize: false),
      ),
    );
    await tester.pump();

    expect(find.text('Nearby'), findsWidgets);
    expect(find.text('Workplace'), findsWidgets);
    expect(find.text('Messages'), findsWidgets);
    expect(find.text('Files'), findsWidgets);
    expect(find.text('Trusted devices'), findsWidgets);
  });
}
