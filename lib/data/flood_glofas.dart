import 'dart:convert';

import 'package:http/http.dart' as http;

/// One day of GloFAS river discharge for the snapped cell, in m³/s. All seven
/// stats come straight from the receipted response — nothing is derived,
/// averaged, or renamed. See docs/contracts/flood-glofas.md.
class FloodDay {
  final String date;
  final double discharge;
  final double mean;
  final double median;
  final double min;
  final double max;
  final double p25;
  final double p75;

  const FloodDay({
    required this.date,
    required this.discharge,
    required this.mean,
    required this.median,
    required this.min,
    required this.max,
    required this.p25,
    required this.p75,
  });
}

/// One parsed GloFAS response. The coordinates are the SNAPPED cell centre
/// the API echoed back — the request point is rounded to the 0.05° grid, and
/// that cell holds the largest river inside it, which may be a different
/// channel than the one the user meant. The card must show the snapped
/// coordinates, never the request coordinates.
class FloodSnapshot {
  final double snappedLat;
  final double snappedLng;
  final double elevation;
  final DateTime fetchedAtUtc;
  final List<FloodDay> days;

  const FloodSnapshot({
    required this.snappedLat,
    required this.snappedLng,
    required this.elevation,
    required this.fetchedAtUtc,
    required this.days,
  });

  bool get isStale {
    final age = DateTime.now().toUtc().difference(fetchedAtUtc);
    return age > const Duration(hours: 30);
  }
}

/// The daily variables the contract pins (docs/contracts/flood-glofas.md).
/// This is the DEFAULT model request — no model parameter is sent. The
/// receipted forecast_v4/seamless_v4 probes returned river_discharge only,
/// so the default is the only receipted full schema.
const String floodDailyVars =
    'river_discharge,river_discharge_mean,river_discharge_median,'
    'river_discharge_min,river_discharge_max,river_discharge_p25,'
    'river_discharge_p75';

double _num(Object? v, String what) {
  if (v is num) return v.toDouble();
  throw ArgumentError('flood snapshot: $what is not a number');
}

/// Parses one GloFAS flood response. Fail-closed: any deviation from the
/// receipted shape (non-JSON, missing daily block, unequal column lengths,
/// missing snapped coordinates, non-numeric values, non-String dates)
/// throws ArgumentError and the panel shows MISSING. Values <= 0 are kept
/// when finite — a dry river is a real reading, not an error.
FloodSnapshot parseFloodSnapshot(String body, DateTime fetchedAtUtc) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (e) {
    throw ArgumentError('flood snapshot: unparseable JSON ($e)');
  }
  if (decoded is! Map<String, dynamic>) {
    throw ArgumentError('flood snapshot: response is not a JSON object');
  }

  final snapped = decoded['latitude'];
  final snappedLng = decoded['longitude'];
  final elevation = decoded['elevation'];
  if (snapped is! num || snappedLng is! num || elevation is! num) {
    throw ArgumentError(
        'flood snapshot: missing snapped coordinates (latitude/longitude/elevation)');
  }

  final daily = decoded['daily'];
  if (daily is! Map<String, dynamic>) {
    throw ArgumentError('flood snapshot: missing daily block');
  }
  final times = daily['time'];
  if (times is! List || times.isEmpty) {
    throw ArgumentError('flood snapshot: missing daily time axis');
  }

  const statKeys = <String>[
    'river_discharge',
    'river_discharge_mean',
    'river_discharge_median',
    'river_discharge_min',
    'river_discharge_max',
    'river_discharge_p25',
    'river_discharge_p75',
  ];
  final columns = <String, List<Object?>>{};
  for (final key in statKeys) {
    final col = daily[key];
    if (col is! List || col.length != times.length) {
      throw ArgumentError(
          'flood snapshot: column $key missing or length mismatch');
    }
    columns[key] = col;
  }

  final days = <FloodDay>[];
  for (var i = 0; i < times.length; i++) {
    final t = times[i];
    if (t is! String) {
      throw ArgumentError('flood snapshot: time entry $i is not a String');
    }
    double stat(String key) => _num(columns[key]![i], '$key[$i]');
    days.add(FloodDay(
      date: t,
      discharge: stat('river_discharge'),
      mean: stat('river_discharge_mean'),
      median: stat('river_discharge_median'),
      min: stat('river_discharge_min'),
      max: stat('river_discharge_max'),
      p25: stat('river_discharge_p25'),
      p75: stat('river_discharge_p75'),
    ));
  }

  return FloodSnapshot(
    snappedLat: snapped.toDouble(),
    snappedLng: snappedLng.toDouble(),
    elevation: elevation.toDouble(),
    fetchedAtUtc: fetchedAtUtc,
    days: days,
  );
}

/// Flood client — one request per place, fail-closed. NOTE: the flood API
/// lives on its own host (flood-api.open-meteo.com), not api.open-meteo.com.
/// The DEFAULT model (no model parameter) is the receipted full schema.
class FloodClient {
  FloodClient(
      {http.Client? client,
      this.baseUrl = 'https://flood-api.open-meteo.com/v1/flood'})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<FloodSnapshot> fetchDaily({
    required double lat,
    required double lng,
    DateTime? now,
  }) async {
    final fetchedAt = now ?? DateTime.now().toUtc();
    final uri = Uri.parse(baseUrl).replace(queryParameters: <String, String>{
      'latitude': lat.toStringAsFixed(4),
      'longitude': lng.toStringAsFixed(4),
      'daily': floodDailyVars,
    });
    final http.Response res;
    try {
      res = await _client.get(uri).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw StateError('flood fetch failed: $e');
    }
    if (res.statusCode != 200) {
      throw StateError('flood fetch: HTTP ${res.statusCode}');
    }
    return parseFloodSnapshot(res.body, fetchedAt);
  }
}
