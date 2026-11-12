import 'package:flutter_test/flutter_test.dart';
import 'package:net_design/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NetDesignApp());
    expect(find.text('Net Design Sandbox'), findsOneWidget);
  });
}
