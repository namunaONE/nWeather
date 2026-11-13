import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nweather/data/open_meteo.dart';

void main() {
  final fixture =
      File('test/fixtures/open_meteo_ifs_sample.json').readAsStringSync();

  group('parser (fixture-backed, schema per docs/contracts/weather-compare.md)', () {
    test('parses the documented daily schema', () {
      final f = parseModelForecast('ecmwf_ifs025', fixture, DateTime.utc(2026, 11, 13, 6));
      expect(f.isMissing, isFalse);
      expect(f.error, isNull);
      expect(f.days.length, 3);
      expect(f.days[0].date, '2026-11-13');
      expect(f.days[0].tMaxC, 24.1);
      expect(f.days[0].tMinC, 9.2);
      expect(f.days[0].precipMm, 0.0);
      // A null model value stays missing — never 0, never interpolated.
      expect(f.days[2].tMaxC, isNull);
    });

    test('API error payload -> fail-closed MISSING with reason', () {
      final f = parseModelForecast(
        'does_not_exist',
        '{"error":true,"reason":"Invalid model id"}',
        DateTime.utc(2026, 11, 13),
      );
      expect(f.isMissing, isTrue);
      expect(f.days, isEmpty);
      expect(f.error, contains('Invalid model id'));
    });

    test('garbage body -> fail-closed MISSING', () {
      final f = parseModelForecast('x', '<html>oops</html>', DateTime.utc(2026, 11, 13));
      expect(f.isMissing, isTrue);
      expect(f.error, contains('unparseable'));
    });

    test('daily block missing -> fail-closed MISSING', () {
      final f = parseModelForecast('x', '{"latitude": 27.7}', DateTime.utc(2026, 11, 13));
      expect(f.isMissing, isTrue);
      expect(f.error, contains('daily'));
    });
  });

  group('client (MockClient, fail-closed per model)', () {
    test('HTTP 500 -> explicit error, not a throw', () async {
      final client = OpenMeteoClient(
        client: MockClient((_) async => http.Response('server error', 500)),
      );
      final f = await client.fetchDaily(model: 'ecmwf_ifs025', lat: 27.7172, lng: 85.324);
      expect(f.isMissing, isTrue);
      expect(f.error, contains('500'));
    });

    test('network failure -> explicit error, not a throw', () async {
      final client = OpenMeteoClient(
        client: MockClient((_) async => throw Exception('offline')),
      );
      final f = await client.fetchDaily(model: 'gfs_seamless', lat: 27.7172, lng: 85.324);
      expect(f.isMissing, isTrue);
      expect(f.error, contains('fetch failed'));
    });

    test('request carries model, coords, Kathmandu tz, daily vars', () async {
      Uri? captured;
      final client = OpenMeteoClient(
        client: MockClient((req) async {
          captured = req.url;
          return http.Response(fixture, 200);
        }),
      );
      final f = await client.fetchDaily(model: 'ecmwf_ifs025', lat: 27.7172, lng: 85.324);
      expect(f.isMissing, isFalse);
      expect(captured!.queryParameters['models'], 'ecmwf_ifs025');
      expect(captured!.queryParameters['timezone'], 'Asia/Kathmandu');
      expect(captured!.queryParameters['latitude'], '27.7172');
      expect(
        captured!.queryParameters['daily'],
        'temperature_2m_max,temperature_2m_min,precipitation_sum',
      );
    });

    test('valid response parses through the client', () async {
      final client = OpenMeteoClient(
        client: MockClient((_) async => http.Response(fixture, 200)),
      );
      final f = await client.fetchDaily(model: 'ecmwf_ifs025', lat: 27.7172, lng: 85.324);
      expect(f.days.length, 3);
      expect(f.days[0].tMaxC, 24.1);
    });
  });

  group('compare math — never averaged', () {
    final t = DateTime.utc(2026, 11, 13, 6);

    ModelForecast f(String id, List<double?> tMax) => ModelForecast(
          modelId: id,
          days: [
            for (var i = 0; i < tMax.length; i++)
              CompareDay(date: '2026-11-${13 + i}', tMaxC: tMax[i]),
          ],
          fetchedAt: t,
        );

    test('spread is max-min across models, ignoring missing values', () {
      final forecasts = [
        f('a', [20.0, 22.0]),
        f('b', [24.0, null]),
        f('c', [], ), // MISSING model contributes nothing
      ];
      expect(spreadOf(forecasts, 0), 4.0);
      expect(spreadOf(forecasts, 1), isNull); // one value only
      expect(spreadOf(forecasts, 2), isNull); // no values
    });

    test('per-model values are never merged into one list', () {
      final forecasts = [f('a', [20.0]), f('b', [26.0])];
      // Each model keeps its own value; no averaged 23.0 exists anywhere.
      expect(forecasts[0].days[0].tMaxC, 20.0);
      expect(forecasts[1].days[0].tMaxC, 26.0);
      expect(spreadOf(forecasts, 0), 6.0);
    });

    test('humanAge buckets honestly', () {
      final now = DateTime.utc(2026, 11, 13, 12);
      expect(humanAge(now, now), 'just now');
      expect(humanAge(now.subtract(const Duration(minutes: 5)), now),
          'fetched 5 min ago');
      expect(humanAge(now.subtract(const Duration(hours: 3)), now),
          'fetched 3 h ago');
      expect(humanAge(now.subtract(const Duration(days: 2)), now),
          'fetched 2 d ago');
    });
  });
}
