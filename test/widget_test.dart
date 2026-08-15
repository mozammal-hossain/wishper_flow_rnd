import 'package:flutter_test/flutter_test.dart';

import 'package:wishper_flow_rnd/main.dart';

void main() {
  testWidgets('App loads the voice demo screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Voice Demo'), findsOneWidget);
    expect(find.text('Speech to text'), findsOneWidget);
    expect(find.text('Text to speech'), findsOneWidget);
  });
}
