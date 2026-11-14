import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nweather/data/open_meteo_ensemble.dart';

void main() {
  final fixture =
      File('test/fixtures/open_meteo_ensemble_ecmwf.json').readAsStringSync();

  group('parser (fixture-backed, schema per docs/contracts/rainfall-ensemble.md)', () {
    test('derives member count from the response (2 members x 3 days)', () {
      final f = parseEnsemblePrecipitation(
          'ecmwf_ifs025_ensemble', fixture, DateTime.utc(2026, 11, 13, 6));
      expect(f.isMissing, isFalse);
      expect(f.error, isNull);
      expect(f.days, hasLength(3));
      expect(f.days[0].memberCount, 2);
      expect(f.days[0].memberMm, [0.0, 0.6]);
      expect(f.days[2].memberMm, [8.4, 22.1]);
    });

    test('non-divisible member/days layout -> fail-closed MISSING', () {
      final f = parseEnsemblePrecipitation(
        'x',
        '{"daily":{"time":["2026-11-13","2026-11-14"],"precipitation_sum":[1.0,2.0,3.0]}}',
        DateTime.utc(2026, 11, 13),
      );
      expect(f.isMissing, isTrue);
      expect(f.error, contains('member/days mismatch'));
    });

    test('API error payload -> fail-closed MISSING with reason', () {
      final f = parseEnsemblePrecipitation(
        'does_not_exist',
        '{"error":true,"reason":"Invalid model id"}',
        DateTime.utc(2026, 11, 13),
      );
      expect(f.isMissing, isTrue);
      expect(f.days, isEmpty);
      expect(f.error, contains('Invalid model id'));
    });

    test('garbage body -> fail-closed MISSING', () {
      final f = parseEnsemblePrecipitation(
          'x', '<html>oops</html>', DateTime.utc(2026, 11, 13));
      expect(f.isMissing, isTrue);
      expect(f.error, contains('unparseable'));
    });

    test('missing precipitation_sum -> fail-closed MISSING', () {
      final f = parseEnsemblePrecipitation(
        'x',
        '{"daily":{"time":["2026-11-13"]}}',
        DateTime.utc(2026, 11, 13),
      );
      expect(f.isMissing, isTrue);
      expect(f.error, contains('precipitation_sum'));
    });
  });

  group('distribution math — never a single number', () {
    test('dayStats: min/max from non-null members, agreement counts >= 10 mm', () {
      const day = EnsembleDay(date: '2026-11-13', memberMm: [0.0, 4.0, 22.1, null]);
      final s = dayStats(day, 10.0);
      expect(s, isNotNull);
      expect(s!.minMm, 0.0);
      expect(s.maxMm, 22.1);
      expect(s.atLeast, 1);
      expect(s.members, 3); // null member excluded
    });

    test('dayStats: all-null day -> null (n/a, never 0)', () {
      const day = EnsembleDay(date: '2026-11-13', memberMm: [null, null]);
      expect(dayStats(day, 10.0), isNull);
    });

    test('no averaging helper exists for members — stats stay a range', () {
      const day = EnsembleDay(date: '2026-11-13', memberMm: [2.0, 8.0]);
      final s = dayStats(day, 10.0)!;
      // The mean (5.0) must never appear; only the range endpoints do.
      expect(s.minMm, 2.0);
      expect(s.maxMm, 8.0);
    });
  });

  group('client (MockClient, fail-closed per model)', () {
    test('uses the ensemble host and pinned query shape', () async {
      Uri? captured;
      final client = EnsembleClient(
        client: MockClient((req) async {
          captured = req.url;
          return http.Response(fixture, 200);
        }),
      );
      final f = await client.fetchPrecipitation(
          model: 'ecmwf_ifs025_ensemble', lat: 27.7172, lng: 85.324);
      expect(f.isMissing, isFalse);
      expect(captured!.host, 'ensemble-api.open-meteo.com');
      expect(captured!.path, '/v1/ensemble');
      expect(captured!.queryParameters['models'], 'ecmwf_ifs025_ensemble');
      expect(captured!.queryParameters['daily'], 'precipitation_sum');
      expect(captured!.queryParameters['timezone'], 'Asia/Kathmandu');
    });

    test('HTTP 500 -> explicit error, not a throw', () async {
      final client = EnsembleClient(
        client: MockClient((_) async => http.Response('server error', 500)),
      );
      final f = await client.fetchPrecipitation(
          model: 'ncep_gefs_seamless', lat: 27.7172, lng: 85.324);
      expect(f.isMissing, isTrue);
      expect(f.error, contains('500'));
    });

    test('network failure -> explicit error, not a throw', () async {
      final client = EnsembleClient(
        client: MockClient((_) async => throw Exception('offline')),
      );
      final f = await client.fetchPrecipitation(
          model: 'dwd_icon_seamless_eps', lat: 27.7172, lng: 85.324);
      expect(f.isMissing, isTrue);
      expect(f.error, contains('fetch failed'));
    });
  });
}
