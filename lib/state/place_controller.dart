import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nepal_admin_api/nepal_admin_api.dart';

/// The currently selected place (palika). Defaults to Kathmandu Metropolitan
/// City until the user picks one (HYA-458 place picker).
final placeProvider = StateProvider<LocalBody>((ref) {
  final ktm = NepalAdminApi.getLocalBodiesByName('Kathmandu', 'Kathmandu');
  if (ktm.isNotEmpty) return ktm.first;
  return NepalAdminApi.getAllLocalBodies().first;
});

/// Best available coordinates for a place, with provenance. Prefers the
/// official HDX COD-AB centroid; falls back to the geocoded centroid.
/// Null when the palika is unmapped — never guessed (honesty contract).
({double lat, double lng, String source})? coordinatesOf(LocalBody place) {
  if (place.latHdx != null && place.lngHdx != null) {
    return (
      lat: place.latHdx!,
      lng: place.lngHdx!,
      source: 'HDX COD-AB official centroid',
    );
  }
  if (place.lat != null && place.lng != null) {
    return (
      lat: place.lat!,
      lng: place.lng!,
      source: place.geoSource ?? 'geocoded centroid',
    );
  }
  return null;
}
