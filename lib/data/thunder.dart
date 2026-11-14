import 'dart:convert';

import 'package:http/http.dart' as http;

import 'air_quality.dart' show parseGmtHour;

/// Thunder outlook for ONE model (docs/contracts/air-quality-cams.md):
/// WMO weather codes 95-99 plus CAPE. Model guidance — NOT lightning
/// detection, NOT an official warning.
class ThunderReport {
  final String modelId;
  final String label;
  final double snappedLat;
  final double snappedLng;
  final int hoursCovered;
  final int thunderHours;
  final DateTime? firstThunderUtc;

  /// Null when the model issues no CAPE at all (receipted:
  /// ecmwf_aifs025_single returns an all-null array with unit "undefined").
  /// The row then says not issued — never substituted from another model.
  final double? maxCape;

  /// False when the model receipts NO cape values at all.
  final bool capeIssued;
  final DateTime fetchedAtUtc;
  final String? error;

  const ThunderReport({
    required this.modelId,
    this.label = '',
    this.snappedLat = 0,
    this.snappedLng = 0,
    this.hoursCovered = 0,
    this.thunderHours = 0,
    this.firstThunderUtc,
    this.maxCape,
    this.capeIssued = false,
    required this.fetchedAtUtc,
    this.error,
  });

  bool get isMissing => error != null;
  String get shortLabel => label.isEmpty ? modelId : label;
}

/// WMO thunder codes: 95 thunderstorm, 96 and 99 thunderstorm with hail.
bool isThunderCode(num code) => code >= 95 && code <= 99;

ThunderReport _missing(String modelId, String label, DateTime fetchedAtUtc, String error) {
  return ThunderReport(
    modelId: modelId,
    label: label,
    fetchedAtUtc: fetchedAtUtc,
    error: error,
  );
}

/// Parses one single-model hourly response. Fail-SOFT per model (compare-card
/// pattern): every malformed shape becomes an explicit MISSING row — never a
/// throw, never a partial guess.
ThunderReport parseThunderForecast(
  String modelId,
  String body,
  DateTime fetchedAtUtc, {
  String label = '',
}) {
  Map<String, dynamic> json;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw ArgumentError('not a JSON object');
    }
    json = decoded;
  } catch (e) {
    return _missing(modelId, label, fetchedAtUtc, 'unparseable response ($e)');
  }
  if (json['error'] == true) {
    final reason = json['reason'];
    return _missing(modelId, label, fetchedAtUtc,
        'API error: ${reason is String ? reason : 'unknown'}');
  }
  final lat = json['latitude'];
  final lng = json['longitude'];
  if (lat is! num || lng is! num) {
    return _missing(modelId, label, fetchedAtUtc, 'missing snapped coordinates');
  }
  final hourly = json['hourly'];
  if (hourly is! Map<String, dynamic>) {
    return _missing(modelId, label, fetchedAtUtc, 'missing hourly block');
  }
  final times = hourly['time'];
  final codes = hourly['weathercode'];
  final cape = hourly['cape'];
  if (times is! List || codes is! List || cape is! List) {
    return _missing(modelId, label, fetchedAtUtc, 'missing hourly axes');
  }
  if (codes.length != times.length || cape.length != times.length) {
    return _missing(modelId, label, fetchedAtUtc, 'axis length mismatch');
  }
  var thunderHours = 0;
  DateTime? firstThunder;
  var capeIssued = false;
  double? maxCape;
  for (var i = 0; i < times.length; i++) {
    final c = codes[i];
    if (c != null) {
      if (c is! num) {
        return _missing(modelId, label, fetchedAtUtc, 'non-numeric weathercode');
      }
      if (isThunderCode(c)) {
        thunderHours++;
        final t = times[i];
        if (t is! String) {
          return _missing(modelId, label, fetchedAtUtc, 'non-string time');
        }
        try {
          firstThunder ??= parseGmtHour(t);
        } catch (e) {
          return _missing(modelId, label, fetchedAtUtc, '$e');
        }
      }
    }
    final cv = cape[i];
    if (cv == null) continue;
    if (cv is! num) {
      return _missing(modelId, label, fetchedAtUtc, 'non-numeric cape');
    }
    capeIssued = true;
    final v = cv.toDouble();
    if (maxCape == null || v > maxCape) maxCape = v;
  }
  return ThunderReport(
    modelId: modelId,
    label: label,
    snappedLat: lat.toDouble(),
    snappedLng: lng.toDouble(),
    hoursCovered: times.length,
    thunderHours: thunderHours,
    firstThunderUtc: firstThunder,
    maxCape: maxCape,
    capeIssued: capeIssued,
    fetchedAtUtc: fetchedAtUtc,
  );
}

/// Thunder client — one request per model, fail-closed per model. The
/// multi-model key-suffixing response shape is unreceipted; independent
/// requests keep attribution and failure separate (HYA-408 rule).
class ThunderClient {
  ThunderClient({http.Client? client, this.baseUrl = 'https://api.open-meteo.com/v1/forecast'})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<ThunderReport> fetch({
    required String model,
    required double lat,
    required double lng,
    String label = '',
    int forecastDays = 3,
    DateTime? now,
  }) async {
    final fetchedAt = now ?? DateTime.now().toUtc();
    final uri = Uri.parse(baseUrl).replace(queryParameters: <String, String>{
      'latitude': lat.toStringAsFixed(4),
      'longitude': lng.toStringAsFixed(4),
      'forecast_days': '$forecastDays',
      'hourly': 'weathercode,cape',
      'models': model,
    });
    try {
      final res = await _client.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        return _missing(model, label, fetchedAt, 'HTTP ${res.statusCode}');
      }
      return parseThunderForecast(model, res.body, fetchedAt, label: label);
    } catch (e) {
      return _missing(model, label, fetchedAt, 'fetch failed: $e');
    }
  }
}
