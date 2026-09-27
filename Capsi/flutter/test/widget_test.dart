import 'package:capsi/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Capsi shell renders', (tester) async {
    await tester.pumpWidget(const CapsiApp());
    expect(find.text('Nearby'), findsOneWidget);
    expect(find.text('Run it. Find devices. Send.'), findsOneWidget);
  });
}
