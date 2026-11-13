import 'dart:convert';

import 'package:http/http.dart' as http;

/// One day of one model's daily forecast. Null means the model has no value
/// for that cell — rendered as n/a, never as 0, never interpolated.
class CompareDay {
  final String date;
  final double? tMaxC;
  final double? tMinC;
  final double? precipMm;

  const CompareDay({
    required this.date,
    this.tMaxC,
    this.tMinC,
    this.precipMm,
  });
}

/// One model's forecast (or its explicit failure — fail-closed per model).
class ModelForecast {
  final String modelId;
  final String label;
  final List<CompareDay> days;
  final DateTime fetchedAt;

  /// Non-null when this model's fetch/parse failed. The card shows a MISSING
  /// column; it never hides or substitutes the model.
  final String? error;

  const ModelForecast({
    required this.modelId,
    this.label = '',
    required this.days,
    required this.fetchedAt,
    this.error,
  });

  bool get isMissing => error != null || days.isEmpty;

  String get shortLabel => label.isEmpty ? modelId : label;
}

/// The compare card's model lineup (docs/contracts/weather-compare.md).
/// icon_global is discontinued 2026-11-30 per the live docs page; the native
/// replacement id is pending a live CI receipt (HYA-456) and may show MISSING.
const List<({String id, String label})> compareModels = [
  (id: 'ecmwf_ifs025', label: 'IFS 0.25°'),
  (id: 'aifs025', label: 'AIFS 0.25°'),
  (id: 'icon_global_native', label: 'ICON Native'),
  (id: 'gfs_seamless', label: 'GFS'),
];

/// Parses one single-model daily response. Every malformed shape becomes an
/// explicit MISSING ModelForecast — never a throw, never a partial guess.
ModelForecast parseModelForecast(String modelId, String body, DateTime fetchedAt, {String label = ''}) {
  Map<String, dynamic> json;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return ModelForecast(modelId: modelId, label: label, days: const [], fetchedAt: fetchedAt, error: 'unparseable response');
    }
    json = decoded;
  } catch (_) {
    return ModelForecast(modelId: modelId, label: label, days: const [], fetchedAt: fetchedAt, error: 'unparseable response');
  }

  if (json['error'] == true) {
    final reason = json['reason'];
    return ModelForecast(
      modelId: modelId,
      label: label,
      days: const [],
      fetchedAt: fetchedAt,
      error: 'API error: ${reason is String ? reason : 'unknown'}',
    );
  }

  final daily = json['daily'];
  if (daily is! Map<String, dynamic>) {
    return ModelForecast(modelId: modelId, label: label, days: const [], fetchedAt: fetchedAt, error: 'missing daily block');
  }
  final times = daily['time'];
  if (times is! List || times.isEmpty) {
    return ModelForecast(modelId: modelId, label: label, days: const [], fetchedAt: fetchedAt, error: 'missing daily time axis');
  }

  List<double?> column(String key) {
    final raw = daily[key];
    if (raw is! List) return List<double?>.filled(times.length, null);
    return [
      for (var i = 0; i < times.length; i++)
        i < raw.length ? (raw[i] as num?)?.toDouble() : null,
    ];
  }

  final tMax = column('temperature_2m_max');
  final tMin = column('temperature_2m_min');
  final precip = column('precipitation_sum');

  final days = <CompareDay>[
    for (var i = 0; i < times.length; i++)
      CompareDay(
        date: times[i] as String,
        tMaxC: tMax[i],
        tMinC: tMin[i],
        precipMm: precip[i],
      ),
  ];
  return ModelForecast(modelId: modelId, label: label, days: days, fetchedAt: fetchedAt);
}

/// Per-day spread (max − min) of non-missing tMax across models. There is no
/// averaging function in this codebase: disagreement is displayed, not smoothed.
double? spreadOf(List<ModelForecast> forecasts, int day) {
  final values = <double>[];
  for (final f in forecasts) {
    if (day < f.days.length) {
      final v = f.days[day].tMaxC;
      if (v != null) values.add(v);
    }
  }
  if (values.length < 2) return null;
  final sorted = [...values]..sort();
  return sorted.last - sorted.first;
}

/// Honest client-side age for the honesty footer.
String humanAge(DateTime fetchedAtUtc, DateTime nowUtc) {
  final d = nowUtc.difference(fetchedAtUtc);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return 'fetched ${d.inMinutes} min ago';
  if (d.inHours < 24) return 'fetched ${d.inHours} h ago';
  return 'fetched ${d.inDays} d ago';
}

/// Minimal Open-Meteo forecast client — one request per model, fail-closed.
class OpenMeteoClient {
  OpenMeteoClient({http.Client? client, this.baseUrl = 'https://api.open-meteo.com/v1/forecast'})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<ModelForecast> fetchDaily({
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
      'daily': 'temperature_2m_max,temperature_2m_min,precipitation_sum',
      'timezone': 'Asia/Kathmandu',
      'forecast_days': '$forecastDays',
      'models': model,
    });
    try {
      final res = await _client.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        return ModelForecast(modelId: model, label: label, days: const [], fetchedAt: fetchedAt, error: 'HTTP ${res.statusCode}');
      }
      return parseModelForecast(model, res.body, fetchedAt, label: label);
    } catch (e) {
      return ModelForecast(modelId: model, label: label, days: const [], fetchedAt: fetchedAt, error: 'fetch failed: $e');
    }
  }
}
