import 'package:capsi/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Capsi shell renders without native runtime', (tester) async {
    await tester.pumpWidget(const CapsiApp());
    await tester.pumpAndSettle();
    expect(find.text('Capsi could not start'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('Capsi shell UI renders independently of native runtime', (tester) async {
    await tester.pumpWidget(
      const CapsiHome(autoInitialize: false),
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
