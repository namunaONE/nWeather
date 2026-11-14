import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/open_meteo.dart';

/// UTC clock, injectable so age display and staleness are testable.
final clockProvider = Provider<DateTime>((ref) => DateTime.now().toUtc());

final openMeteoClientProvider = Provider<OpenMeteoClient>((ref) => OpenMeteoClient());

typedef PlaceCoords = ({double lat, double lng});

/// One fail-closed fetch per model, in parallel. A dead model degrades to a
/// MISSING column (its ModelForecast carries an error); the card itself only
/// errors if something truly unexpected escapes.
final compareProvider = FutureProvider.autoDispose.family<List<ModelForecast>, PlaceCoords>((ref, place) async {
  final client = ref.watch(openMeteoClientProvider);
  return Future.wait(<Future<ModelForecast>>[
    for (final m in compareModels)
      client.fetchDaily(model: m.id, label: m.label, lat: place.lat, lng: place.lng),
  ]);
});
