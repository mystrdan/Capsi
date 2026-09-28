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

    expect(find.text('Nearby'), findsOneWidget);
    expect(find.text('Workplace'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Trusted devices'), findsOneWidget);
    expect(find.text('Run it. Find devices. Send.'), findsOneWidget);
  });
}
