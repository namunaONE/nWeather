import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nweather/data/flood_glofas.dart';

void main() {
  final fixture =
      File('test/fixtures/flood/glofas_karnali.json').readAsStringSync();
  final fetchedAt = DateTime.utc(2026, 11, 14, 1, 0);

  group('parseFloodSnapshot — receipted fixture', () {
    final snap = parseFloodSnapshot(fixture, fetchedAt);

    test('snapped cell coordinates + elevation are kept verbatim', () {
      expect(snap.snappedLat, 28.575005);
      expect(snap.snappedLng, 81.17502);
      expect(snap.elevation, 199.0);
    });

    test('full 92-day axis, 2026-11-14 .. 2027-02-13', () {
      expect(snap.days.length, 92);
      expect(snap.days.first.date, '2026-11-14');
      expect(snap.days.last.date, '2027-02-13');
    });

    test('all seven stats present on the first day', () {
      final d = snap.days.first;
      expect(d.discharge, 0.08);
      expect(d.mean, 0.08);
      expect(d.median, 0.08);
      expect(d.min, 0.08);
      expect(d.max, 0.08);
      expect(d.p25, 0.08);
      expect(d.p75, 0.08);
    });

    test('dry-season scale: ensemble max never exceeds the receipted 0.58', () {
      final maxOfMax =
          snap.days.map((d) => d.max).reduce((a, b) => a > b ? a : b);
      expect(maxOfMax, 0.58);
    });
  });

  group('parseFloodSnapshot — fail-closed', () {
    test('non-JSON body throws ArgumentError', () {
      expect(() => parseFloodSnapshot('<html>502</html>', fetchedAt),
          throwsArgumentError);
    });

    test('missing daily block throws ArgumentError', () {
      expect(() => parseFloodSnapshot('{"latitude":1}', fetchedAt),
          throwsArgumentError);
    });

    test('column length mismatch throws ArgumentError', () {
      final bad = fixture.replaceFirst(',0.08,', ',', );
      expect(() => parseFloodSnapshot(bad, fetchedAt), throwsArgumentError);
    });

    test('non-numeric stat entry throws ArgumentError', () {
      final bad = fixture.replaceFirst('"river_discharge":[0.08,', '"river_discharge":["x",');
      expect(() => parseFloodSnapshot(bad, fetchedAt), throwsArgumentError);
    });

    test('missing snapped coordinates throw ArgumentError', () {
      final bad = fixture.replaceFirst('"latitude":28.575005,', '');
      expect(() => parseFloodSnapshot(bad, fetchedAt), throwsArgumentError);
    });
  });

  group('FloodClient', () {
    test('default request sends the seven contract variables, no model param',
        () async {
      Uri? requested;
      final client = FloodClient(
        client: _FakeHttp((uri) async {
          requested = uri;
          return _Response(200, fixture);
        }),
      );
      final snap = await client.fetchDaily(
          lat: 28.6, lng: 81.2, now: fetchedAt);
      expect(requested!.host, 'flood-api.open-meteo.com');
      expect(requested!.queryParameters['daily'], floodDailyVars);
      expect(requested!.queryParameters.containsKey('model'), isFalse);
      expect(snap.days.length, 92);
    });

    test('non-200 raises StateError', () async {
      final client = FloodClient(
        client: _FakeHttp((uri) async => _Response(500, 'boom')),
      );
      expect(
        () => client.fetchDaily(lat: 28.6, lng: 81.2, now: fetchedAt),
        throwsStateError,
      );
    });
  });
}

class _Response implements http.Response {
  _Response(this.statusCode, this.body);

  @override
  final int statusCode;
  @override
  final String body;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttp implements http.Client {
  _FakeHttp(this.handler);

  final Future<_Response> Function(Uri uri) handler;

  @override
  Future<_Response> get(Uri url, {Map<String, String>? headers}) =>
      handler(url);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
