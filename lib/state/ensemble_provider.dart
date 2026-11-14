import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/open_meteo_ensemble.dart';
import 'compare_provider.dart' show PlaceCoords, clockProvider;

final ensembleClientProvider =
    Provider<EnsembleClient>((ref) => EnsembleClient());

/// One fail-closed fetch per ensemble model, in parallel. A dead model
/// degrades to a MISSING row; the card only goes MISSING when all fail.
final ensembleProvider =
    FutureProvider.autoDispose.family<List<EnsembleForecast>, PlaceCoords>(
        (ref, place) async {
  final client = ref.watch(ensembleClientProvider);
  final fetchedAt = ref.watch(clockProvider);
  return Future.wait(<Future<EnsembleForecast>>[
    for (final m in ensembleModels)
      client.fetchPrecipitation(
          model: m.id, label: m.label, lat: place.lat, lng: place.lng, now: fetchedAt),
  ]);
});
