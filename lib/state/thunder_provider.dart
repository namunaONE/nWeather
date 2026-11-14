import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/open_meteo.dart' show compareModels;
import '../data/thunder.dart';
import 'compare_provider.dart' show PlaceCoords;

final thunderClientProvider = Provider<ThunderClient>((ref) => ThunderClient());

/// One fail-closed fetch per model, in parallel. A dead model degrades to a
/// MISSING row; the others still show.
final thunderProvider = FutureProvider.autoDispose.family<List<ThunderReport>, PlaceCoords>((ref, place) {
  final client = ref.watch(thunderClientProvider);
  return Future.wait(<Future<ThunderReport>>[
    for (final m in compareModels)
      client.fetch(model: m.id, label: m.label, lat: place.lat, lng: place.lng),
  ]);
});
