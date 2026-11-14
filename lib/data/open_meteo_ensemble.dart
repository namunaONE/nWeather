import 'dart:convert';

import 'package:http/http.dart' as http;

/// One day of one ensemble model's rainfall: one value per member. Null means
/// that member has no value — n/a, never 0, never interpolated.
class EnsembleDay {
  final String date;
  final List<double?> memberMm;

  const EnsembleDay({required this.date, required this.memberMm});

  bool get hasData => memberMm.any((v) => v != null);

  int get memberCount => memberMm.length;
}

/// One ensemble model's rainfall (or its explicit failure — fail-closed).
class EnsembleForecast {
  final String modelId;
  final String label;
  final List<EnsembleDay> days;
  final DateTime fetchedAt;

  /// Non-null when this model's fetch/parse failed. The card shows a MISSING
  /// row; it never hides or substitutes the model.
  final String? error;

  const EnsembleForecast({
    required this.modelId,
    this.label = '',
    required this.days,
    required this.fetchedAt,
    this.error,
  });

  bool get isMissing => error != null || days.isEmpty;

  String get shortLabel => label.isEmpty ? modelId : label;
}

/// The rainfall card's ensemble lineup (docs/contracts/rainfall-ensemble.md).
/// Ids are from the ensemble API's own `models` enum
/// (openapi/ensemble.yml, open-meteo/open-meteo@b485547, fetched 2026-11-13);
/// they differ from the forecast API's enum. Ids change only with a receipt.
const List<({String id, String label})> ensembleModels = [
  (id: 'ecmwf_ifs025_ensemble', label: 'ECMWF EPS'),
  (id: 'ecmwf_aifs025_ensemble', label: 'ECMWF AIFS EPS'),
  (id: 'dwd_icon_seamless_eps', label: 'ICON EPS'),
  (id: 'ncep_gefs_seamless', label: 'GEFS'),
];

/// Member values at or above this daily total count as "wet" in the
/// agreement line (`k/N members ≥ 10 mm`).
const double rainThresholdMm = 10.0;

/// Distribution stats for one day, from non-null member values only.
/// Returns null when no member has a value. No mean, no median — the range
/// and the member count are the honest product.
({double minMm, double maxMm, int atLeast, int members})? dayStats(
    EnsembleDay day, double thresholdMm) {
  final values = day.memberMm.whereType<double>().toList()..sort();
  if (values.isEmpty) return null;
  return (
    minMm: values.first,
    maxMm: values.last,
    atLeast: values.where((v) => v >= thresholdMm).length,
    members: values.length,
  );
}

/// Parses one single-model ensemble response. Member count is DERIVED from
/// the response (raw length / day count) because the spec does not document
/// it — a non-divisible layout fails the whole model closed. See
/// docs/contracts/rainfall-ensemble.md.
EnsembleForecast parseEnsemblePrecipitation(
    String modelId, String body, DateTime fetchedAt,
    {String label = ''}) {
  Map<String, dynamic> json;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return EnsembleForecast(modelId: modelId, label: label, days: const [], fetchedAt: fetchedAt, error: 'unparseable response');
    }
    json = decoded;
  } catch (_) {
    return EnsembleForecast(modelId: modelId, label: label, days: const [], fetchedAt: fetchedAt, error: 'unparseable response');
  }

  if (json['error'] == true) {
    final reason = json['reason'];
    return EnsembleForecast(
      modelId: modelId,
      label: label,
      days: const [],
      fetchedAt: fetchedAt,
      error: 'API error: ${reason is String ? reason : 'unknown'}',
    );
  }

  final daily = json['daily'];
  if (daily is! Map<String, dynamic>) {
    return EnsembleForecast(modelId: modelId, label: label, days: const [], fetchedAt: fetchedAt, error: 'missing daily block');
  }
  final times = daily['time'];
  if (times is! List || times.isEmpty) {
    return EnsembleForecast(modelId: modelId, label: label, days: const [], fetchedAt: fetchedAt, error: 'missing daily time axis');
  }
  final raw = daily['precipitation_sum'];
  if (raw is! List || raw.isEmpty) {
    return EnsembleForecast(modelId: modelId, label: label, days: const [], fetchedAt: fetchedAt, error: 'missing precipitation_sum');
  }

  final dayCount = times.length;
  if (raw.length % dayCount != 0) {
    return EnsembleForecast(modelId: modelId, label: label, days: const [], fetchedAt: fetchedAt, error: 'member/days mismatch');
  }
  final memberCount = raw.length ~/ dayCount;
  if (memberCount < 1) {
    return EnsembleForecast(modelId: modelId, label: label, days: const [], fetchedAt: fetchedAt, error: 'member/days mismatch');
  }

  double? valueAt(int flat) => (raw[flat] as num?)?.toDouble();

  final days = <EnsembleDay>[
    for (var d = 0; d < dayCount; d++)
      EnsembleDay(
        date: times[d] as String,
        memberMm: [
          for (var m = 0; m < memberCount; m++) valueAt(m * dayCount + d),
        ],
      ),
  ];
  return EnsembleForecast(modelId: modelId, label: label, days: days, fetchedAt: fetchedAt);
}

/// Ensemble client — one request per model, fail-closed. NOTE: the ensemble
/// API lives on its own host (ensemble-api.open-meteo.com per the spec's
/// servers block), not api.open-meteo.com.
class EnsembleClient {
  EnsembleClient({http.Client? client, this.baseUrl = 'https://ensemble-api.open-meteo.com/v1/ensemble'})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<EnsembleForecast> fetchPrecipitation({
    required String model,
    required double lat,
    required double lng,
    String label = '',
    int forecastDays = 5,
    DateTime? now,
  }) async {
    final fetchedAt = now ?? DateTime.now().toUtc();
    final uri = Uri.parse(baseUrl).replace(queryParameters: <String, String>{
      'latitude': lat.toStringAsFixed(4),
      'longitude': lng.toStringAsFixed(4),
      'daily': 'precipitation_sum',
      'timezone': 'Asia/Kathmandu',
      'forecast_days': '$forecastDays',
      'models': model,
    });
    try {
      final res = await _client.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        return EnsembleForecast(modelId: model, label: label, days: const [], fetchedAt: fetchedAt, error: 'HTTP ${res.statusCode}');
      }
      return parseEnsemblePrecipitation(model, res.body, fetchedAt, label: label);
    } catch (e) {
      return EnsembleForecast(modelId: model, label: label, days: const [], fetchedAt: fetchedAt, error: 'fetch failed: $e');
    }
  }
}
