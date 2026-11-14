import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/home_page.dart';

void main() {
  runApp(const ProviderScope(child: NWeatherApp()));
}

class NWeatherApp extends StatelessWidget {
  const NWeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'nWeather',
      theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E7490)),
      ),
      darkTheme: ThemeData(
                brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0E7490),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}
