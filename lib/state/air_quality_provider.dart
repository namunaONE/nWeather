import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/air_quality.dart';
import 'compare_provider.dart' show PlaceCoords;

final airQualityClientProvider = Provider<AirQualityClient>((ref) => AirQualityClient());

/// One fail-closed fetch of CAMS-global air guidance for the place's
/// coordinates. Any failure surfaces as the provider's error — MISSING tile.
final airQualityProvider = FutureProvider.autoDispose.family<AirSnapshot, PlaceCoords>((ref, place) {
  final client = ref.watch(airQualityClientProvider);
  return client.fetch(lat: place.lat, lng: place.lng);
});
