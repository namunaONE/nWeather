import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nweather/data/air_quality.dart';

void main() {
  final receipt =
      File('receipts/hya-411/aq-cams-global-kathmandu.json').readAsStringSync();
  final fetchedAt = DateTime.utc(2026, 11, 14, 8, 0);

  AirSnapshot parse(String body) => parseAirQuality(
        body,
        requestLat: 27.7172,
        requestLng: 85.3240,
        fetchedAtUtc: fetchedAt,
      );

  final snapshot = parse(receipt);

  group('parseAirQuality — committed CAMS-global receipt, verbatim', () {
    test('grid snap, elevation and hour count match the receipt', () {
      expect(snapshot.requestLat, 27.7172);
      expect(snapshot.requestLng, 85.3240);
      expect(snapshot.snappedLat, 27.700005);
      expect(snapshot.snappedLng, 85.30002);
      expect(snapshot.elevationM, 1301.0);
      expect(snapshot.hours.length, 144);
    });

    test('first hour verbatim (2026-11-13T00:00 GMT, no offset suffix)', () {
      final h = snapshot.hours.first;
      expect(h.timeUtc, DateTime.utc(2026, 11, 13));
      expect(h.pm10, 69.6);
      expect(h.pm25, 67.5);
      expect(h.carbonMonoxide, 838.0);
      expect(h.nitrogenDioxide, 22.0);
      expect(h.sulphurDioxide, 12.8);
      expect(h.ozone, 64.0);
      expect(h.aerosolOpticalDepth, 0.28);
      expect(h.dust, 4.0);
      expect(h.uvIndex, 0.0);
      expect(h.usAqi, 143.0);
    });

    test(
        'last issued hour 2026-11-18T13:00 GMT — US AQI issued one hour '
        'beyond PM2.5, each variable keeps its own cutoff', () {
      // In the receipted run, US AQI is issued through 13:00 while PM2.5
      // stops at 12:00. lastIssued is the last hour with ANY value; its
      // PM2.5 is null and stays null — never back-filled from 12:00.
      final last = snapshot.lastIssued!;
      expect(last.timeUtc, DateTime.utc(2026, 11, 18, 13));
      expect(last.usAqi, 138.0);
      expect(last.pm25, isNull);
      // PM2.5's own last issued hour, verbatim.
      final lastPm25 = snapshot.hours[132];
      expect(lastPm25.timeUtc, DateTime.utc(2026, 11, 18, 12));
      expect(lastPm25.pm25, 37.3);
      expect(lastPm25.usAqi, 138.0);
      final trailing =
          snapshot.hours.reversed.takeWhile((h) => !h.hasAnyValue).length;
      expect(trailing, 10);
      expect(snapshot.hours.last.timeUtc, DateTime.utc(2026, 11, 18, 23));
      expect(snapshot.hours.last.hasAnyValue, isFalse);
    });

    test('STALE window: fresh at 30 h, stale after (CAMS runs lag)', () {
      expect(
          snapshot.isStale(fetchedAt.add(const Duration(hours: 30))), isFalse);
      expect(
          snapshot.isStale(
              fetchedAt.add(const Duration(hours: 30, minutes: 1))),
          isTrue);
    });
  });

  group('parseGmtHour — offset-less GMT times normalize to UTC', () {
    test('receipted 16-char shape parses as UTC, never local', () {
      expect(parseGmtHour('2026-11-13T00:00'), DateTime.utc(2026, 11, 13));
    });

    test('Z-suffixed and offset shapes stay UTC', () {
      expect(
          parseGmtHour('2026-11-13T00:00Z'), DateTime.utc(2026, 11, 13));
      expect(parseGmtHour('2026-11-13T05:45+05:45'),
          DateTime.utc(2026, 11, 13));
    });

    test('empty time throws ArgumentError', () {
      expect(() => parseGmtHour('   '), throwsArgumentError);
    });
  });

  group('dailyMaxFrom — NPT calendar days, forecast part only', () {
    test('the day boundary follows NPT (+05:45), not UTC', () {
      expect(nptDateLabel(DateTime.utc(2026, 11, 13, 18, 30)), '2026-11-14');
      expect(nptDateLabel(DateTime.utc(2026, 11, 13, 18, 14)), '2026-11-13');
    });

    test('groups by NPT day, filters hours before fromUtc, caps at maxDays',
        () {
      final hours = <AirHour>[
        AirHour(timeUtc: DateTime.utc(2026, 11, 13, 10), pm25: 10, usAqi: 40),
        AirHour(
            timeUtc: DateTime.utc(2026, 11, 13, 18, 30),
            pm25: 20,
            usAqi: 60),
        AirHour(timeUtc: DateTime.utc(2026, 11, 14, 2), pm25: 30, usAqi: 80),
        AirHour(timeUtc: DateTime.utc(2026, 11, 14, 6), usAqi: 50),
        AirHour(timeUtc: DateTime.utc(2026, 11, 15, 1), pm25: 5, usAqi: 20),
      ];
      final days = dailyMaxFrom(
        hours,
        DateTime.utc(2026, 11, 13, 18, 15),
        maxDays: 2,
      );
      expect(days.length, 2);
      expect(days[0].day, '2026-11-14');
      expect(days[0].maxPm25, 30.0);
      expect(days[0].maxUsAqi, 80.0);
      expect(days[1].day, '2026-11-15');
      expect(days[1].maxPm25, 5.0);
      expect(days[1].maxUsAqi, 20.0);
    });
  });

  group('bands', () {
    test('US EPA AQI bands at receipted and boundary values', () {
      expect(usAqiBand(37.3), 'Good');
      expect(usAqiBand(138.0), 'Unhealthy for sensitive groups');
      expect(usAqiBand(50.0), 'Good');
      expect(usAqiBand(50.1), 'Moderate');
      expect(usAqiBand(100.0), 'Moderate');
      expect(usAqiBand(100.1), 'Unhealthy for sensitive groups');
      expect(usAqiBand(150.0), 'Unhealthy for sensitive groups');
      expect(usAqiBand(150.1), 'Unhealthy');
      expect(usAqiBand(200.1), 'Very unhealthy');
      expect(usAqiBand(300.1), 'Hazardous');
    });

    test('WHO UV bands', () {
      expect(uvBand(0.0), 'Low');
      expect(uvBand(2.9), 'Low');
      expect(uvBand(3.0), 'Moderate');
      expect(uvBand(6.0), 'High');
      expect(uvBand(8.0), 'Very high');
      expect(uvBand(11.0), 'Extreme');
    });
  });

  group('fail-closed parsing — shape deviations throw, nulls pass through',
      () {
    test('non-JSON throws ArgumentError', () {
      expect(() => parse('<html>502</html>'), throwsArgumentError);
    });

    test('API error envelope throws ArgumentError', () {
      expect(
          () => parse(
              '{"error":true,"reason":"No data is available for this location"}'),
          throwsArgumentError);
    });

    test('missing hourly block throws ArgumentError', () {
      expect(() => parse('{"latitude":27.7,"longitude":85.3}'),
          throwsArgumentError);
    });

    test('variable axis length mismatch throws ArgumentError', () {
      const body = '{"latitude":27.7,"longitude":85.3,"hourly":{'
          '"time":["2026-11-13T00:00","2026-11-13T01:00"],'
          '"pm10":[1.0],"pm2_5":[1.0],"carbon_monoxide":[1.0],'
          '"nitrogen_dioxide":[1.0],"sulphur_dioxide":[1.0],"ozone":[1.0],'
          '"aerosol_optical_depth":[1.0],"dust":[1.0],"uv_index":[1.0],'
          '"us_aqi":[1.0]}}';
      expect(() => parse(body), throwsArgumentError);
    });

    test('non-numeric value throws ArgumentError', () {
      expect(() => parse(miniBody(const [
            '1.0',
            'high',
            '1.0',
            '1.0',
            '1.0',
            '1.0',
            '1.0',
            '1.0',
            '1.0',
            '1.0',
          ])), throwsArgumentError);
    });

    test('null VALUES pass through as not-issued, never coerced to 0', () {
      final s = parse(miniBody(List.filled(10, 'null')));
      final h = s.hours.single;
      expect(h.pm25, isNull);
      expect(h.usAqi, isNull);
      expect(h.hasAnyValue, isFalse);
      expect(s.lastIssued, isNull);
    });
  });

  group('forbidden domains — receipted HTTP 400 for Nepal, never parsed', () {
    test('cams_europe probe body fails closed', () {
      final europe =
          File('receipts/hya-411/aq-cams-europe-probe.json').readAsStringSync();
      expect(() => parse(europe), throwsArgumentError);
    });

    test('temporal_resolution=hourly_3hourly probe body fails closed', () {
      final threeHourly =
          File('receipts/hya-411/aq-cams-global-3hourly.json')
              .readAsStringSync();
      expect(() => parse(threeHourly), throwsArgumentError);
    });
  });

  group('AirQualityClient', () {
    test('sends the receipted cams_global query — no Europe, no 3-hourly',
        () async {
      final urls = <Uri>[];
      final client = AirQualityClient(
        client: _FakeHttp((uri) async {
          urls.add(uri);
          // The receipt carries μg/m³ — UTF-8 bytes, not Latin-1.
          return http.Response.bytes(utf8.encode(receipt), 200);
        }),
      );
      final s = await client.fetch(lat: 27.7172, lng: 85.3240, now: fetchedAt);
      expect(urls.single.host, 'air-quality-api.open-meteo.com');
      expect(urls.single.queryParameters['domains'], 'cams_global');
      expect(urls.single.queryParameters['latitude'], '27.7172');
      expect(urls.single.queryParameters['longitude'], '85.3240');
      expect(urls.single.queryParameters['past_days'], '1');
      expect(urls.single.queryParameters['forecast_days'], '5');
      final hourly = urls.single.queryParameters['hourly']!;
      expect(hourly, contains('pm2_5'));
      expect(hourly, contains('us_aqi'));
      expect(hourly.contains('pollen'), isFalse);
      expect(urls.single.queryParameters.containsKey('temporal_resolution'),
          isFalse);
      expect(s.snappedLat, 27.700005);
      expect(s.fetchedAtUtc, fetchedAt);
    });

    test('non-200 raises — fail-closed single source, no fallback', () async {
      final client = AirQualityClient(
        client: _FakeHttp((uri) async => http.Response('boom', 500)),
      );
      expect(
        () => client.fetch(lat: 27.7172, lng: 85.3240, now: fetchedAt),
        throwsStateError,
      );
    });
  });
}

/// One-hour body carrying every receipted variable (the parser requires the
/// full receipted hourly set).
String miniBody(List<String> values) {
  final parts = <String>[
    for (var i = 0; i < airHourlyVars.length; i++)
      '"${airHourlyVars[i]}":[${values[i]}]',
  ];
  return '{"latitude":27.7,"longitude":85.3,'
      '"hourly":{"time":["2026-11-13T00:00"],${parts.join(",")}}}';
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
