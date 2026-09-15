import 'package:flutter_test/flutter_test.dart';

import 'package:taptosay/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TapToSay category home renders', (tester) async {
    // Skip the orientation lock call in main(): pump the widget directly.
    await tester.pumpWidget(const TapToSayApp());

    // Title shows
    expect(find.text('TapToSay 🌻'), findsOneWidget);

    // Core categories present on the home grid
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('I Feel'), findsOneWidget);
    expect(find.text('I Want'), findsOneWidget);
    expect(find.text('I Need'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('Category grid opens and shows word tiles', (tester) async {
    await tester.pumpWidget(const TapToSayApp());

    // Tap the People category
    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();

    // Its words are now visible
    expect(find.text('Mom'), findsOneWidget);
    expect(find.text('Dad'), findsOneWidget);
    expect(find.text('Teacher'), findsOneWidget);
  });
}
