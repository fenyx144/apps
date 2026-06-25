import 'package:flutter_test/flutter_test.dart';
import 'package:ag_causales/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    expect(const AgCausalesApp(), isNotNull);
  });
}
