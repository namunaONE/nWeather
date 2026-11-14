import 'dart:convert';

import 'package:http/http.dart' as http;

/// One hour of CAMS-global air guidance (docs/contracts/air-quality-cams.md).
/// Null means the model has not issued a value for that hour — rendered as
/// not issued, never as 0, never interpolated.
class AirHour {
  final DateTime timeUtc;
  final double? pm10;
  final double? pm25;
  final double? carbonMonoxide;
  final double? nitrogenDioxide;
  final double? sulphurDioxide;
  final double? ozone;
  final double? aerosolOpticalDepth;
  final double? dust;
  final double? uvIndex;
  final double? usAqi;

  const AirHour({
    required this.timeUtc,
    this.pm10,
    this.pm25,
    this.carbonMonoxide,
    this.nitrogenDioxide,
    this.sulphurDioxide,
    this.ozone,
    this.aerosolOpticalDepth,
    this.dust,
    this.uvIndex,
    this.usAqi,
  });

  bool get hasAnyValue =>
      pm10 != null ||
      pm25 != null ||
      carbonMonoxide != null ||
      nitrogenDioxide != null ||
      sulphurDioxide != null ||
      ozone != null ||
      aerosolOpticalDepth != null ||
      dust != null ||
      uvIndex != null ||
      usAqi != null;
}

class AirSnapshot {
  final double requestLat;
  final double requestLng;

  /// The CAMS grid cell the request snapped to (receipted 0.4 deg class:
  /// 27.7172/85.3240 -> 27.700005/85.30002). Shown, never hidden.
  final double snappedLat;
  final double snappedLng;
  final double? elevationM;
  final List<AirHour> hours;
  final DateTime fetchedAtUtc;

  const AirSnapshot({
    required this.requestLat,
    required this.requestLng,
    required this.snappedLat,
    required this.snappedLng,
    required this.hours,
    required this.fetchedAtUtc,
    this.elevationM,
  });

  /// CAMS global runs lag issuance: the tile is STALE after 30 h.
  bool isStale(DateTime nowUtc) =>
      nowUtc.difference(fetchedAtUtc) > const Duration(hours: 30);

  /// Last hour with any issued value — the tile "issued through" line.
  AirHour? get lastIssued {
    for (var i = hours.length - 1; i >= 0; i--) {
      if (hours[i].hasAnyValue) return hours[i];
    }
    return null;
  }
}

/// The receipted hourly variable set (docs/contracts/air-quality-cams.md).
/// European pollen variables are absent ON PURPOSE: the cams_europe domain
/// is receipted HTTP 400 for Nepal ("No data is available for this
/// location").
const List<String> airHourlyVars = <String>[
  'pm10',
  'pm2_5',
  'carbon_monoxide',
  'nitrogen_dioxide',
  'sulphur_dioxide',
  'ozone',
  'aerosol_optical_depth',
  'dust',
  'uv_index',
  'us_aqi',
];

/// Receipted times are GMT iso8601 WITHOUT an offset suffix (e.g.
/// 2026-11-13T00:00). Dart parses offset-less strings as LOCAL time, so the
/// zone is normalized to UTC explicitly before parsing.
DateTime parseGmtHour(String raw) {
  final s = raw.trim();
  if (s.isEmpty) {
    throw ArgumentError('air quality: empty time');
  }
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
  final normalized = hasZone ? s : (s.length == 16 ? '${s}:00Z' : '${s}Z');
  try {
    return DateTime.parse(normalized).toUtc();
  } catch (e) {
    throw ArgumentError('air quality: unparseable time ($raw): $e');
  }
}

double? _numAt(Map<String, dynamic> hourly, String key, List times, int i) {
  final raw = hourly[key];
  if (raw is! List) {
    throw ArgumentError('air quality: hourly.$key is not a list');
  }
  if (raw.length != times.length) {
    throw ArgumentError('air quality: hourly.$key length mismatch');
  }
  final v = raw[i];
  if (v == null) return null;
  if (v is! num) {
    throw ArgumentError('air quality: hourly.$key has a non-numeric value');
  }
  return v.toDouble();
}

/// Parses the receipted CAMS-global response. Fail-closed: any shape
/// deviation throws ArgumentError; null VALUES pass through as not-issued.
AirSnapshot parseAirQuality(
  String body, {
  required double requestLat,
  required double requestLng,
  required DateTime fetchedAtUtc,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (e) {
    throw ArgumentError('air quality: unparseable JSON ($e)');
  }
  if (decoded is! Map<String, dynamic>) {
    throw ArgumentError('air quality: response is not a JSON object');
  }
  if (decoded['error'] == true) {
    throw ArgumentError('air quality: API error: ${decoded['reason']}');
  }
  final lat = decoded['latitude'];
  final lng = decoded['longitude'];
  if (lat is! num || lng is! num) {
    throw ArgumentError('air quality: missing snapped coordinates');
  }
  final hourly = decoded['hourly'];
  if (hourly is! Map<String, dynamic>) {
    throw ArgumentError('air quality: missing hourly block');
  }
  final times = hourly['time'];
  if (times is! List || times.isEmpty) {
    throw ArgumentError('air quality: missing hourly time axis');
  }
  final hours = <AirHour>[];
  for (var i = 0; i < times.length; i++) {
    final t = times[i];
    if (t is! String) {
      throw ArgumentError('air quality: time axis has a non-string entry');
    }
    hours.add(AirHour(
      timeUtc: parseGmtHour(t),
      pm10: _numAt(hourly, 'pm10', times, i),
      pm25: _numAt(hourly, 'pm2_5', times, i),
      carbonMonoxide: _numAt(hourly, 'carbon_monoxide', times, i),
      nitrogenDioxide: _numAt(hourly, 'nitrogen_dioxide', times, i),
      sulphurDioxide: _numAt(hourly, 'sulphur_dioxide', times, i),
      ozone: _numAt(hourly, 'ozone', times, i),
      aerosolOpticalDepth: _numAt(hourly, 'aerosol_optical_depth', times, i),
      dust: _numAt(hourly, 'dust', times, i),
      uvIndex: _numAt(hourly, 'uv_index', times, i),
      usAqi: _numAt(hourly, 'us_aqi', times, i),
    ));
  }
  return AirSnapshot(
    requestLat: requestLat,
    requestLng: requestLng,
    snappedLat: lat.toDouble(),
    snappedLng: lng.toDouble(),
    elevationM: decoded['elevation'] is num ? (decoded['elevation'] as num).toDouble() : null,
    hours: hours,
    fetchedAtUtc: fetchedAtUtc,
  );
}

/// NPT (+05:45) calendar-day label for a UTC hour.
String nptDateLabel(DateTime utc) {
  final npt = utc.toUtc().add(const Duration(hours: 5, minutes: 45));
  final y = npt.year.toString().padLeft(4, '0');
  final m = npt.month.toString().padLeft(2, '0');
  final d = npt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

double? _maxOf(List<AirHour> list, double? pick(AirHour h)) {
  double? best;
  for (final h in list) {
    final v = pick(h);
    if (v == null) continue;
    if (best == null || v > best) best = v;
  }
  return best;
}

/// Daily max PM2.5 and US AQI per NPT day, forecast part only (hours at or
/// after [fromUtc]), up to [maxDays] days in NPT-date order.
List<({String day, double? maxPm25, double? maxUsAqi})> dailyMaxFrom(
  List<AirHour> hours,
  DateTime fromUtc, {
  int maxDays = 3,
}) {
  final byDay = <String, List<AirHour>>{};
  for (final h in hours) {
    if (h.timeUtc.isBefore(fromUtc)) continue;
    byDay.putIfAbsent(nptDateLabel(h.timeUtc), () => <AirHour>[]).add(h);
  }
  final days = byDay.keys.toList()..sort();
  return <({String day, double? maxPm25, double? maxUsAqi})>[
    for (final d in days.take(maxDays))
      (
        day: d,
        maxPm25: _maxOf(byDay[d]!, (h) => h.pm25),
        maxUsAqi: _maxOf(byDay[d]!, (h) => h.usAqi),
      ),
  ];
}

/// US EPA AQI band names (the scale Open-Meteo computes for us_aqi).
String usAqiBand(double aqi) {
  if (aqi <= 50) return 'Good';
  if (aqi <= 100) return 'Moderate';
  if (aqi <= 150) return 'Unhealthy for sensitive groups';
  if (aqi <= 200) return 'Unhealthy';
  if (aqi <= 300) return 'Very unhealthy';
  return 'Hazardous';
}

/// WHO UV index band names.
String uvBand(double uv) {
  if (uv < 3) return 'Low';
  if (uv < 6) return 'Moderate';
  if (uv < 8) return 'High';
  if (uv < 11) return 'Very high';
  return 'Extreme';
}

/// Air-quality client — one request, fail-closed (single source: any failure
/// propagates and the provider renders a MISSING tile).
class AirQualityClient {
  AirQualityClient({http.Client? client, this.baseUrl = 'https://air-quality-api.open-meteo.com/v1/air-quality'})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  /// Receipted request shape: domains=cams_global is the only domain that
  /// covers Nepal; temporal_resolution is receipted INVALID and never sent.
  Future<AirSnapshot> fetch({
    required double lat,
    required double lng,
    DateTime? now,
    int pastDays = 1,
    int forecastDays = 5,
  }) async {
    final fetchedAt = now ?? DateTime.now().toUtc();
    final uri = Uri.parse(baseUrl).replace(queryParameters: <String, String>{
      'latitude': lat.toStringAsFixed(4),
      'longitude': lng.toStringAsFixed(4),
      'domains': 'cams_global',
      'hourly': airHourlyVars.join(','),
      'past_days': '$pastDays',
      'forecast_days': '$forecastDays',
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw StateError('air quality: HTTP ${res.statusCode}');
    }
    return parseAirQuality(res.body, requestLat: lat, requestLng: lng, fetchedAtUtc: fetchedAt);
  }
}
