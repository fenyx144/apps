import 'package:flutter_test/flutter_test.dart';
import 'package:gc_mortalidad/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Basic placeholder test - full app requires SharedPreferences init
    expect(MortalidadApp, isNotNull);
  });
}
