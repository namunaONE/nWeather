import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:nweather/data/dhm_official.dart';

/// HYA-454 — the CI-side DHM parser. Fetches the receipted MFD API
/// endpoints, validates the gates (contract:
/// docs/contracts/dhm-official-strip.md), and writes the normalized
/// snapshot to cache/dhm-official.json.
///
/// Gate failure = non-zero exit = red run = the owner is alerted, and no
/// snapshot is written (the previous one stays). Fail-closed.

const String _countryUrl = 'https://dhm.gov.np/mfd/api/country-forecast';
const String _threeDaysUrl = 'https://dhm.gov.np/mfd/api/three-days-forecast-latest';
const String _bulletinUrl = 'https://dhm.gov.np/mfd/#/weather/three-days-bulletin';
const Map<String, String> _ua = {
  'User-Agent': 'nWeather CI fetcher (github.com/namunaONE/nWeather)',
  'Accept': 'application/json',
};

/// Validates + normalizes the country-forecast document. Throws
/// ArgumentError on any gate miss (tested against the live fixture).
DhmForecast24 normalizeCountryForecast(Map<String, dynamic> j) {
  final id = (j['id'] ?? '').toString().trim();
  if (id.isEmpty) throw ArgumentError('country-forecast: id is empty');
  final issuedAt = DateTime.tryParse((j['issue_date'] ?? '').toString());
  if (issuedAt == null) throw ArgumentError('country-forecast: issue_date unparseable');
  return DhmForecast24(
    id: id,
    issuedAt: issuedAt.toUtc(),
    analysisNe: _tidy(j['analysis_np'], 'analysis_np'),
    analysisEn: _tidy(j['analysis_en'], 'analysis_en'),
    dayNe: _tidy(j['np_text_1'], 'np_text_1'),
    dayEn: _tidy(j['en_text_1'], 'en_text_1'),
    nightNe: _tidy(j['np_text_2'], 'np_text_2'),
    nightEn: _tidy(j['en_text_2'], 'en_text_2'),
  );
}

/// Validates + normalizes the three-days bulletin rows (newest first).
/// Returns null when nothing usable is present — the bulletin section is
/// optional; the app renders its own MISSING state.
DhmBulletin? normalizeThreeDays(List<dynamic> rows) {
  for (final dynamic row in rows) {
    if (row is! Map<String, dynamic>) continue;
    final id = (row['id'] ?? '').toString().trim();
    final title = (row['title'] ?? '').toString().trim();
    final issuedAt = DateTime.tryParse((row['issue_date'] ?? '').toString());
    if (id.isEmpty || title.isEmpty || issuedAt == null) continue;
    return DhmBulletin(id: id, issuedAt: issuedAt.toUtc(), title: title, url: _bulletinUrl);
  }
  return null;
}

String _tidy(dynamic v, String what) {
  final s = (v ?? '').toString().trim();
  if (s.isEmpty) throw ArgumentError('country-forecast: $what is empty');
  return s;
}

Future<dynamic> _getJson(http.Client client, String url, String what) async {
  final res = await client.get(Uri.parse(url), headers: _ua);
  if (res.statusCode != 200) throw StateError('$what: HTTP ${res.statusCode}');
  return jsonDecode(utf8.decode(res.bodyBytes));
}

Future<void> main() async {
  final client = http.Client();
  final dynamic country = await _getJson(client, _countryUrl, 'country-forecast');
  if (country is! Map<String, dynamic>) {
    stderr.writeln('GATE FAIL: country-forecast is not a JSON object');
    exitCode = 1;
    return;
  }
  final DhmForecast24 forecast24;
  try {
    forecast24 = normalizeCountryForecast(country);
  } on ArgumentError catch (e) {
    stderr.writeln('GATE FAIL: ${e.message}');
    exitCode = 1;
    return;
  }

  DhmBulletin? bulletin;
  try {
    final dynamic rows = await _getJson(client, _threeDaysUrl, 'three-days-forecast-latest');
    if (rows is List) bulletin = normalizeThreeDays(rows);
    if (bulletin == null) stdout.writeln('WARN: no usable bulletin row — snapshot will carry bulletin: null');
  } catch (e) {
    stdout.writeln('WARN: bulletin unreadable ($e) — snapshot will carry bulletin: null');
  }

  final snapshot = {
    'schema': dhmOfficialSchema,
    'source': 'DHM Meteorological Forecasting Division (dhm.gov.np/mfd)',
    'sourceUrl': 'https://dhm.gov.np/mfd/#/weather/country',
    'evidenceTier': 'official — verbatim, never paraphrased',
    'fetchedAt': DateTime.now().toUtc().toIso8601String(),
    'forecast24': {
      'id': forecast24.id,
      'issuedAt': forecast24.issuedAt.toIso8601String(),
      'analysisNe': forecast24.analysisNe,
      'analysisEn': forecast24.analysisEn,
      'dayNe': forecast24.dayNe,
      'dayEn': forecast24.dayEn,
      'nightNe': forecast24.nightNe,
      'nightEn': forecast24.nightEn,
    },
    'bulletin': bulletin == null
        ? null
        : {
            'id': bulletin.id,
            'issuedAt': bulletin.issuedAt.toIso8601String(),
            'title': bulletin.title,
            'url': bulletin.url,
          },
  };

  final dir = Directory('cache');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final pretty = const JsonEncoder.withIndent('  ').convert(snapshot);
  File('cache/dhm-official.json').writeAsStringSync('$pretty\n');
  stdout.writeln('OK: forecast24 id ${forecast24.id} issued ${forecast24.issuedAt.toIso8601String()}'
      ' | bulletin ${bulletin?.id ?? 'null'}');
}
