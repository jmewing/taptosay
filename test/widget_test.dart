import 'package:flutter_test/flutter_test.dart';

import 'package:taptosay/main.dart';

void main() {
  testWidgets('TapToSay grid renders and taps speak', (tester) async {
    await tester.pumpWidget(const TapToSayApp());

    // Title shows
    expect(find.text('TapToSay 🌻'), findsOneWidget);

    // A few core tiles are present
    expect(find.text('Mom'), findsOneWidget);
    expect(find.text('Dad'), findsOneWidget);
    expect(find.text('Eat'), findsOneWidget);
    expect(find.text('Drink'), findsOneWidget);
    expect(find.text('All Done'), findsOneWidget);
  });
}
