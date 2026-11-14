import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nweather/main.dart';

void main() {
  testWidgets('home renders the place and date panels', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: NWeatherApp()));
    await tester.pump();

    expect(find.text('nWeather'), findsOneWidget);
    expect(find.text('Place'), findsOneWidget);
    expect(find.textContaining('Kathmandu'), findsWidgets);
  });
}
