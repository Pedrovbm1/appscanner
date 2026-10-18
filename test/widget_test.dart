import 'package:flutter_test/flutter_test.dart';

import 'package:escaner/main.dart';

void main() {
  testWidgets('home screen shows the scan entry point', (WidgetTester tester) async {
    await tester.pumpWidget(const EscanerApp());

    expect(find.text('AppScanner'), findsOneWidget);
    expect(find.text('Nuevo escaneo'), findsOneWidget);
  });
}
