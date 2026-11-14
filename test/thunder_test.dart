import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nweather/data/thunder.dart';

void main() {
  final fetchedAt = DateTime.utc(2026, 11, 14, 8, 0);

  final ifs =
      File('receipts/hya-411/fc-thunder-ecmwf_ifs025.json').readAsStringSync();
  final aifs = File('receipts/hya-411/fc-thunder-ecmwf_aifs025_single.json')
      .readAsStringSync();
  final icon = File('receipts/hya-411/fc-thunder-icon_seamless.json')
      .readAsStringSync();
  final gfs = File('receipts/hya-411/fc-thunder-ncep_gfs_seamless.json')
      .readAsStringSync();

  group('parseThunderForecast — committed per-model receipts, verbatim', () {
    test('ecmwf_ifs025: 72 h, no thunder codes, max CAPE 170, negatives kept',
        () {
      final r = parseThunderForecast('ecmwf_ifs025', ifs, fetchedAt);
      expect(r.isMissing, isFalse);
      expect(r.snappedLat, 27.75);
      expect(r.snappedLng, 85.25);
      expect(r.hoursCovered, 72);
      expect(r.thunderHours, 0);
      expect(r.firstThunderUtc, isNull);
      expect(r.capeIssued, isTrue);
      expect(r.maxCape, 170.0);
    });

    test('ecmwf_aifs025_single receipts NO cape — not issued, never substituted',
        () {
      final r = parseThunderForecast('ecmwf_aifs025_single', aifs, fetchedAt);
      expect(r.isMissing, isFalse);
      expect(r.hoursCovered, 72);
      expect(r.capeIssued, isFalse);
      expect(r.maxCape, isNull);
      expect(r.thunderHours, 0);
    });

    test('icon_seamless: max CAPE 290 at its own grid cell', () {
      final r = parseThunderForecast('icon_seamless', icon, fetchedAt);
      expect(r.isMissing, isFalse);
      expect(r.snappedLat, 27.75);
      expect(r.snappedLng, 85.375);
      expect(r.capeIssued, isTrue);
      expect(r.maxCape, 290.0);
      expect(r.thunderHours, 0);
    });

    test('ncep_gfs_seamless: max CAPE 110 at its own grid cell', () {
      final r = parseThunderForecast('ncep_gfs_seamless', gfs, fetchedAt);
      expect(r.isMissing, isFalse);
      expect(r.snappedLat, 27.705826);
      expect(r.snappedLng, 85.3125);
      expect(r.capeIssued, isTrue);
      expect(r.maxCape, 110.0);
      expect(r.thunderHours, 0);
    });

    test('negative CAPE is a real reading — kept, never clamped or averaged',
        () {
      // The IFS receipt contains -10.0 hours; the max stays the receipted 170.
      final r = parseThunderForecast('ecmwf_ifs025', ifs, fetchedAt);
      expect(r.maxCape, 170.0);
      const synthetic = '{"latitude":27.75,"longitude":85.25,"hourly":{'
          '"time":["2026-11-14T00:00","2026-11-14T01:00"],'
          '"weathercode":[0,0],"cape":[-10.0,-5.0]}}';
      final s = parseThunderForecast('x', synthetic, fetchedAt);
      expect(s.capeIssued, isTrue);
      expect(s.maxCape, -5.0);
    });
  });

  group('isThunderCode — WMO 95-99 only', () {
    test('94 and 100 are not thunder; 95, 96 and 99 are', () {
      expect(isThunderCode(94), isFalse);
      expect(isThunderCode(95), isTrue);
      expect(isThunderCode(96), isTrue);
      expect(isThunderCode(99), isTrue);
      expect(isThunderCode(100), isFalse);
    });
  });

  group('thunder-hour counting — receipted response shapes', () {
    test('codes 95/96/99 count; the first thunder hour is recorded', () {
      const body = '{"latitude":27.75,"longitude":85.25,"hourly":{'
          '"time":["2026-11-14T00:00","2026-11-14T01:00","2026-11-14T02:00",'
          '"2026-11-14T03:00","2026-11-14T04:00"],'
          '"weathercode":[1,95,96,99,94],'
          '"cape":[0.0,10.0,20.0,30.0,0.0]}}';
      final r = parseThunderForecast('m', body, fetchedAt);
      expect(r.thunderHours, 3);
      expect(r.firstThunderUtc, DateTime.utc(2026, 11, 14, 1));
      expect(r.maxCape, 30.0);
    });

    test('null weathercode hours are skipped, not counted', () {
      const body = '{"latitude":27.75,"longitude":85.25,"hourly":{'
          '"time":["2026-11-14T00:00","2026-11-14T01:00"],'
          '"weathercode":[null,95],"cape":[null,null]}}';
      final r = parseThunderForecast('m', body, fetchedAt);
      expect(r.thunderHours, 1);
      expect(r.capeIssued, isFalse);
    });
  });

  group('fail-SOFT per model — every malformed shape becomes MISSING', () {
    test('unparseable body', () {
      final r = parseThunderForecast('m', '<html>502</html>', fetchedAt);
      expect(r.isMissing, isTrue);
      expect(r.error, contains('unparseable'));
    });

    test('API error envelope carries the reason', () {
      final r = parseThunderForecast(
          'm', '{"error":true,"reason":"Invalid model"}', fetchedAt);
      expect(r.isMissing, isTrue);
      expect(r.error, 'API error: Invalid model');
    });

    test('missing hourly block', () {
      final r = parseThunderForecast(
          'm', '{"latitude":27.75,"longitude":85.25}', fetchedAt);
      expect(r.isMissing, isTrue);
    });

    test('axis length mismatch', () {
      const body = '{"latitude":27.75,"longitude":85.25,"hourly":{'
          '"time":["2026-11-14T00:00","2026-11-14T01:00"],'
          '"weathercode":[0],"cape":[0.0,0.0]}}';
      expect(parseThunderForecast('m', body, fetchedAt).isMissing, isTrue);
    });

    test('non-numeric weathercode', () {
      const body = '{"latitude":27.75,"longitude":85.25,"hourly":{'
          '"time":["2026-11-14T00:00"],"weathercode":["storm"],"cape":[0.0]}}';
      expect(parseThunderForecast('m', body, fetchedAt).isMissing, isTrue);
    });

    test('a missing model stays a row — never dropped, never merged', () {
      final reports = <ThunderReport>[
        parseThunderForecast('ecmwf_ifs025', ifs, fetchedAt),
        parseThunderForecast('dead_model', 'garbage', fetchedAt),
      ];
      expect(reports.length, 2);
      expect(reports[0].isMissing, isFalse);
      expect(reports[1].isMissing, isTrue);
      expect(reports[1].maxCape, isNull);
    });
  });

  group('ThunderClient', () {
    test('sends the receipted single-model query', () async {
      final urls = <Uri>[];
      final client = ThunderClient(
        client: _FakeHttp((uri) async {
          urls.add(uri);
          return http.Response(ifs, 200);
        }),
      );
      final r = await client.fetch(
          model: 'ecmwf_ifs025', lat: 27.7172, lng: 85.3240, now: fetchedAt);
      expect(urls.single.host, 'api.open-meteo.com');
      expect(urls.single.queryParameters['models'], 'ecmwf_ifs025');
      expect(urls.single.queryParameters['hourly'], 'weathercode,cape');
      expect(urls.single.queryParameters['forecast_days'], '3');
      expect(urls.single.queryParameters['latitude'], '27.7172');
      expect(r.maxCape, 170.0);
    });

    test('HTTP 500 degrades to a MISSING row (fail-soft)', () async {
      final client = ThunderClient(
        client: _FakeHttp((uri) async => http.Response('boom', 500)),
      );
      final r = await client.fetch(
          model: 'ecmwf_ifs025', lat: 27.7172, lng: 85.3240, now: fetchedAt);
      expect(r.isMissing, isTrue);
      expect(r.error, 'HTTP 500');
    });

    test('a dead socket degrades to a MISSING row too', () async {
      final client = ThunderClient(
        client: _FakeHttp((uri) async => throw Exception('offline')),
      );
      final r = await client.fetch(
          model: 'ecmwf_ifs025', lat: 27.7172, lng: 85.3240, now: fetchedAt);
      expect(r.isMissing, isTrue);
      expect(r.error, contains('fetch failed'));
    });
  });
}

class _FakeHttp implements http.Client {
  _FakeHttp(this.handler);

  final Future<http.Response> Function(Uri uri) handler;

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      handler(url);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
