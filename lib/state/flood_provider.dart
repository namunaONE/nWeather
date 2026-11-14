import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/flood_glofas.dart';
import 'compare_provider.dart' show PlaceCoords, clockProvider;

final floodClientProvider = Provider<FloodClient>((ref) => FloodClient());

/// One fail-closed fetch of the GloFAS daily discharge for this place's
/// snapped cell. Any fetch/parse failure surfaces as the provider's error —
/// the panel shows a MISSING zone with the reason; nothing is substituted.
final floodProvider =
    FutureProvider.autoDispose.family<FloodSnapshot, PlaceCoords>(
        (ref, place) async {
  final client = ref.watch(floodClientProvider);
  final fetchedAt = ref.watch(clockProvider);
  return client.fetchDaily(lat: place.lat, lng: place.lng, now: fetchedAt);
});
