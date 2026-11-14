import 'dart:convert';

import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// Which catalogue an event came from. nWeather shows the catalogues apart
/// and matches them — it never merges them into one authority.
enum QuakeSource { usgs, emsc }

/// One earthquake event, exactly as one catalogue reported it. Magnitudes
/// are NOT comparable across scales (mb vs ml vs m) and are never averaged.
class QuakeEvent {
  final QuakeSource source;
  final String id;
  final DateTime timeUtc;
  final double mag;
  final String magType;
  final double depthKm;
  final double lat;
  final double lng;
  final String place;
  final String? url;

  const QuakeEvent({
    required this.source,
    required this.id,
    required this.timeUtc,
    required this.mag,
    required this.magType,
    required this.depthKm,
    required this.lat,
    required this.lng,
    required this.place,
    this.url,
  });

  String get sourceName => source == QuakeSource.usgs ? 'USGS' : 'EMSC';
}

/// One row of the quake table: a USGS event, an EMSC event, or a matched
/// pair. Both magnitudes travel with the row — the disagreement between the
/// catalogues is the product, never averaged away.
class QuakeMatch {
  final QuakeEvent? usgs;
  final QuakeEvent? emsc;

  /// Haversine distance between the two catalogues' epicentres, when matched.
  final double? distanceKm;

  const QuakeMatch({this.usgs, this.emsc, this.distanceKm});

  bool get isMatched => usgs != null && emsc != null;
  bool get isSingleSource => !isMatched;

  DateTime get timeUtc => (usgs ?? emsc)!.timeUtc;
  double get lat => (usgs ?? emsc)!.lat;
  double get lng => (usgs ?? emsc)!.lng;
  double get depthKm => (usgs ?? emsc)!.depthKm;
}

class QuakeBundle {
  final List<QuakeEvent> usgs;
  final List<QuakeEvent> emsc;
  final List<QuakeMatch> matches;
  final DateTime fetchedAtUtc;

  /// Receipted per-catalogue failure reasons. One dead catalogue degrades to
  /// single-source rows; both dead is a provider error (MISSING panel).
  final String? usgsError;
  final String? emscError;

  const QuakeBundle({
    required this.usgs,
    required this.emsc,
    required this.matches,
    required this.fetchedAtUtc,
    this.usgsError,
    this.emscError,
  });

  bool get isStale {
    final age = DateTime.now().toUtc().difference(fetchedAtUtc);
    return age > const Duration(hours: 12);
  }
}

/// Great-circle distance in kilometres (haversine).
double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final toRad = 3.141592653589793 / 180.0;
  final dLat = (lat2 - lat1) * toRad;
  final dLng = (lng2 - lng1) * toRad;
  final a = 0.5 -
      0.5 * _cos(dLat) +
      _cos(lat1 * toRad) * _cos(lat2 * toRad) * (1 - _cos(dLng)) / 2;
  return 2 * r * _asin(_sqrt(a));
}

double _cos(double x) => math.cos(x);
double _asin(double x) => math.asin(x);
double _sqrt(double x) => math.sqrt(x);

/// Parses the USGS FDSN GeoJSON (receipt: api 2.8.4, epoch-ms times,
/// coordinates [lon, lat, depthKm]). Fail-closed: non-JSON, wrong type,
/// missing features, or an unparseable time throw ArgumentError. A feature
/// with a null magnitude is SKIPPED — a magnitudeless event cannot be shown
/// honestly, and one odd feature must not blank the catalogue.
List<QuakeEvent> parseUsgsQuakes(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (e) {
    throw ArgumentError('usgs quakes: unparseable JSON ($e)');
  }
  if (decoded is! Map<String, dynamic>) {
    throw ArgumentError('usgs quakes: response is not a JSON object');
  }
  if (decoded['type'] != 'FeatureCollection') {
    throw ArgumentError('usgs quakes: not a FeatureCollection');
  }
  final features = decoded['features'];
  if (features is! List) {
    throw ArgumentError('usgs quakes: missing features list');
  }
  final events = <QuakeEvent>[];
  for (final f in features) {
    if (f is! Map<String, dynamic>) {
      throw ArgumentError('usgs quakes: feature is not an object');
    }
    final props = f['properties'];
    if (props is! Map<String, dynamic>) {
      throw ArgumentError('usgs quakes: feature missing properties');
    }
    final geom = f['geometry'];
    if (geom is! Map<String, dynamic>) {
      throw ArgumentError('usgs quakes: feature missing geometry');
    }
    final coords = geom['coordinates'];
    if (coords is! List || coords.length < 2) {
      throw ArgumentError('usgs quakes: bad geometry coordinates');
    }
    final lng = coords[0];
    final lat = coords[1];
    final depth = coords.length > 2 ? coords[2] : null;
    if (lng is! num || lat is! num) {
      throw ArgumentError('usgs quakes: non-numeric coordinates');
    }
    final mag = props['mag'];
    if (mag is! num) continue; // magnitudeless event: skipped, never guessed
    final timeMs = props['time'];
    if (timeMs is! num) {
      throw ArgumentError('usgs quakes: event time is not epoch ms');
    }
    final depthVal = depth is num ? depth.toDouble() : 0.0;
    events.add(QuakeEvent(
      source: QuakeSource.usgs,
      id: '${f['id'] ?? props['code'] ?? ''}',
      timeUtc: DateTime.fromMillisecondsSinceEpoch(timeMs.round(), isUtc: true),
      mag: mag.toDouble(),
      magType: props['magType'] is String ? props['magType'] as String : '',
      depthKm: depthVal,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      place: props['place'] is String ? props['place'] as String : '',
      url: props['url'] is String ? props['url'] as String : null,
    ));
  }
  events.sort((a, b) => b.timeUtc.compareTo(a.timeUtc));
  return events;
}

/// Parses the EMSC fdsnws JSON (receipt: ISO-8601 string times, flat lat/lon
/// properties, [lon, lat, depth] geometry). Same fail-closed rules.
List<QuakeEvent> parseEmscQuakes(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (e) {
    throw ArgumentError('emsc quakes: unparseable JSON ($e)');
  }
  if (decoded is! Map<String, dynamic>) {
    throw ArgumentError('emsc quakes: response is not a JSON object');
  }
  final features = decoded['features'];
  if (features is! List) {
    throw ArgumentError('emsc quakes: missing features list');
  }
  final events = <QuakeEvent>[];
  for (final f in features) {
    if (f is! Map<String, dynamic>) {
      throw ArgumentError('emsc quakes: feature is not an object');
    }
    final props = f['properties'];
    if (props is! Map<String, dynamic>) {
      throw ArgumentError('emsc quakes: feature missing properties');
    }
    final mag = props['mag'];
    if (mag is! num) continue; // magnitudeless event: skipped, never guessed
    final timeStr = props['time'];
    if (timeStr is! String) {
      throw ArgumentError('emsc quakes: event time is not a String');
    }
    final DateTime timeUtc;
    try {
      timeUtc = DateTime.parse(timeStr);
    } catch (e) {
      throw ArgumentError('emsc quakes: unparseable time "$timeStr"');
    }
    final lat = props['lat'];
    final lng = props['lon'];
    final depth = props['depth'];
    if (lat is! num || lng is! num) {
      throw ArgumentError('emsc quakes: non-numeric coordinates');
    }
    final geom = f['geometry'];
    var depthVal = depth is num ? depth.toDouble() : 0.0;
    if (geom is Map<String, dynamic> && geom['coordinates'] is List) {
      final coords = geom['coordinates'] as List;
      if (coords.length > 2 && coords[2] is num) depthVal = (coords[2] as num).toDouble();
    }
    events.add(QuakeEvent(
      source: QuakeSource.emsc,
      id: props['unid'] is String ? props['unid'] as String : '${f['id'] ?? ''}',
      timeUtc: timeUtc.toUtc(),
      mag: mag.toDouble(),
      magType: props['magtype'] is String ? props['magtype'] as String : '',
      depthKm: depthVal,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      place: props['flynn_region'] is String ? props['flynn_region'] as String : '',
    ));
  }
  events.sort((a, b) => b.timeUtc.compareTo(a.timeUtc));
  return events;
}

/// Cross-catalogue matching (docs/contracts/quake-usgs-emsc.md): same quake
/// iff |dt| <= 60 s AND haversine <= 30 km. Greedy nearest match over USGS
/// rows in time order; each EMSC event matches at most one USGS event.
/// Unmatched events stay single-source rows. Magnitudes are never merged.
List<QuakeMatch> matchQuakes(
  List<QuakeEvent> usgs,
  List<QuakeEvent> emsc, {
  Duration maxDt = const Duration(seconds: 60),
  double maxKm = 30.0,
}) {
  final matches = <QuakeMatch>[];
  final used = <String>{};
  final ordered = [...usgs]..sort((a, b) => b.timeUtc.compareTo(a.timeUtc));
  for (final u in ordered) {
    QuakeEvent? best;
    var bestKm = double.infinity;
    for (final e in emsc) {
      if (used.contains(e.id)) continue;
      final dt = (u.timeUtc.difference(e.timeUtc)).abs();
      if (dt > maxDt) continue;
      final km = haversineKm(u.lat, u.lng, e.lat, e.lng);
      if (km > maxKm) continue;
      if (km < bestKm) {
        bestKm = km;
        best = e;
      }
    }
    if (best != null) {
      used.add(best.id);
      matches.add(QuakeMatch(usgs: u, emsc: best, distanceKm: bestKm));
    } else {
      matches.add(QuakeMatch(usgs: u));
    }
  }
  for (final e in emsc) {
    if (!used.contains(e.id)) matches.add(QuakeMatch(emsc: e));
  }
  matches.sort((a, b) => b.timeUtc.compareTo(a.timeUtc));
  return matches;
}

/// Quake client — one request per catalogue, fail-closed. USGS and EMSC are
/// independent: one dead catalogue degrades to single-source rows (recorded
/// in the bundle's error fields); both dead raises StateError.
class QuakeClient {
  QuakeClient({
    http.Client? client,
    this.usgsBase = 'https://earthquake.usgs.gov/fdsnws/event/1/query',
    this.emscBase = 'https://www.seismicportal.eu/fdsnws/event/1/query',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String usgsBase;
  final String emscBase;

  Future<QuakeBundle> fetchAll({DateTime? now, int days = 30}) async {
    final nowUtc = now ?? DateTime.now().toUtc();
    final start =
        nowUtc.subtract(Duration(days: days)).toIso8601String().substring(0, 10);

    final usgsUri = Uri.parse(usgsBase).replace(queryParameters: <String, String>{
      'format': 'geojson',
      'starttime': start,
      'minlatitude': '26.0',
      'maxlatitude': '30.5',
      'minlongitude': '80.0',
      'maxlongitude': '88.5',
      'minmagnitude': '2.5',
      'orderby': 'time',
    });
    final emscUri = Uri.parse(emscBase).replace(queryParameters: <String, String>{
      'format': 'json',
      'starttime': start,
      'minlatitude': '26.0',
      'maxlatitude': '30.5',
      'minlongitude': '80.0',
      'maxlongitude': '88.5',
      'orderby': 'time',
    });

    List<QuakeEvent>? usgs;
    List<QuakeEvent>? emsc;
    String? usgsError;
    String? emscError;

    Future<void> runUsgs() async {
      try {
        final res = await _client.get(usgsUri).timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) {
          throw StateError('HTTP ${res.statusCode}');
        }
        usgs = parseUsgsQuakes(res.body);
      } catch (e) {
        usgsError = '$e';
      }
    }

    Future<void> runEmsc() async {
      try {
        final res = await _client.get(emscUri).timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) {
          throw StateError('HTTP ${res.statusCode}');
        }
        emsc = parseEmscQuakes(res.body);
      } catch (e) {
        emscError = '$e';
      }
    }

    await Future.wait<void>([runUsgs(), runEmsc()]);

    if (usgs == null && emsc == null) {
      throw StateError(
          'both quake catalogues failed (usgs: $usgsError; emsc: $emscError)');
    }
    return QuakeBundle(
      usgs: usgs ?? const [],
      emsc: emsc ?? const [],
      matches: matchQuakes(usgs ?? const [], emsc ?? const []),
      fetchedAtUtc: nowUtc,
      usgsError: usgsError,
      emscError: emscError,
    );
  }
}
