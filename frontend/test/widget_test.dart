import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';

void main() {
  testWidgets('BC Super App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BCApp());
    expect(find.byType(BCApp), findsOneWidget);
  });
}
