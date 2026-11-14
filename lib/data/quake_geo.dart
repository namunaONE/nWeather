import 'package:nepal_admin_api/nepal_admin_api.dart';

import 'quake_catalogue.dart' show haversineKm;

/// The nearest Nepali palika to a point, by centroid distance. Uses the HDX
/// official centroid (latHdx/lngHdx) when present, else the approximate
/// centroid (lat/lng). This is a nearest-centroid approximation — labelled
/// as such in the UI — never a point-in-polygon claim, and epicentres
/// outside Nepal still resolve to the nearest Nepali palika.
class NearestPalika {
  final LocalBody body;
  final double distanceKm;

  const NearestPalika({required this.body, required this.distanceKm});
}

NearestPalika? nearestPalikaTo(double lat, double lng) {
  NearestPalika? best;
  for (final b in NepalAdminApi.getAllLocalBodies()) {
    final plat = b.latHdx ?? b.lat;
    final plng = b.lngHdx ?? b.lng;
    if (plat == null || plng == null) continue;
    final d = haversineKm(lat, lng, plat, plng);
    if (best == null || d < best.distanceKm) {
      best = NearestPalika(body: b, distanceKm: d);
    }
  }
  return best;
}
