import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nweather/data/quake_catalogue.dart';
import 'package:nweather/data/quake_geo.dart';

void main() {
  final usgsFixture =
      File('test/fixtures/quake/usgs_nepal_30d.json').readAsStringSync();
  final emscFixture =
      File('test/fixtures/quake/emsc_nepal_30d.json').readAsStringSync();

  group('parseUsgsQuakes — receipted fixture', () {
    final events = parseUsgsQuakes(usgsFixture);

    test('5 events, newest first, receipted values verbatim', () {
      expect(events.length, 5);
      expect(events.first.id, 'us7000txpk');
      expect(events.first.mag, 4.6);
      expect(events.first.magType, 'mb');
      expect(events.first.timeUtc, DateTime.utc(2026, 11, 11, 23, 0, 22, 433));
      expect(events.first.lat, 27.8692);
      expect(events.first.lng, 87.8857);
      expect(events.first.depthKm, 10.0);
      expect(
          events.first.url,
          'https://earthquake.usgs.gov/earthquakes/eventpage/us7000txpk');
      expect(events.first.sourceName, 'USGS');
    });
  });

  group('parseEmscQuakes — receipted fixture', () {
    final events = parseEmscQuakes(emscFixture);

    test('32 events, newest first, receipted values verbatim', () {
      expect(events.length, 32);
      expect(events.first.id, '20261113_0000240');
      expect(events.first.mag, 3.2);
      expect(events.first.magType, 'm');
      expect(events.first.timeUtc, DateTime.utc(2026, 11, 13, 18, 48, 9));
      expect(events.first.place, 'WESTERN XIZANG');
      expect(events.first.sourceName, 'EMSC');
    });

    test('the receipted NSC-authored event survives the round trip', () {
      final nsc = events.where((e) => e.id == '20261025_0000238').single;
      expect(nsc.mag, 4.4);
      expect(nsc.magType, 'ml');
    });
  });

  group('matchQuakes — receipted cross-catalogue pairs', () {
    final usgs = parseUsgsQuakes(usgsFixture);
    final emsc = parseEmscQuakes(emscFixture);
    final matches = matchQuakes(usgs, emsc);

    test('exactly the four receipted pairs match (<=60 s, <=30 km)', () {
      final matched = matches.where((m) => m.isMatched).toList();
      expect(matched.length, 4);
      final ids = matched
          .map((m) => '${m.usgs!.id}|${m.emsc!.id}')
          .toSet();
      expect(ids, {
        'us7000txpk|20261111_0000303',
        'us6000u4p1|20261024_0000355',
        'us6000u45b|20261022_0000283',
        'us6000u4em|20261016_0000259',
      });
      for (final m in matched) {
        expect(m.distanceKm!, lessThanOrEqualTo(30.0));
      }
    });

    test('both magnitudes travel with a matched row — never averaged', () {
      final m =
          matches.where((m) => m.usgs?.id == 'us6000u4em').single;
      expect(m.usgs!.mag, 4.2);
      expect(m.usgs!.magType, 'mb');
      expect(m.emsc!.mag, 3.5);
      expect(m.emsc!.magType, 'm');
    });

    test('us7000tvzm stays single-source: 6 s apart but 49 km away', () {
      final m = matches.where((m) => m.usgs?.id == 'us7000tvzm').single;
      expect(m.isMatched, isFalse);
      expect(m.emsc, isNull);
    });

    test('every unmatched EMSC event keeps its own row', () {
      final emscRows = matches.where((m) => m.emsc != null).length;
      // All 32 EMSC events appear in exactly one row: the 4 matched pairs
      // plus 28 single-source rows — none dropped, none duplicated.
      expect(emscRows, 4 + 28);
    });
  });

  group('fail-closed parsing', () {
    test('non-JSON throws ArgumentError', () {
      expect(() => parseUsgsQuakes('<html>502</html>'), throwsArgumentError);
      expect(() => parseEmscQuakes('not json'), throwsArgumentError);
    });

    test('missing features list throws ArgumentError', () {
      expect(() => parseUsgsQuakes('{"type":"FeatureCollection"}'),
          throwsArgumentError);
      expect(() => parseEmscQuakes('{}'), throwsArgumentError);
    });

    test('null magnitude skips the feature, keeps the rest', () {
      const body = '{"type":"FeatureCollection","features":['
          '{"type":"Feature","id":"x","properties":{"mag":null,'
          '"place":"p","time":1794438022433,"magType":"mb"},'
          '"geometry":{"coordinates":[87.0,27.0,10]}},'
          '{"type":"Feature","id":"y","properties":{"mag":3.1,'
          '"place":"p","time":1794438022000,"magType":"mb"},'
          '"geometry":{"coordinates":[87.1,27.1,10]}}]}';
      final events = parseUsgsQuakes(body);
      expect(events.length, 1);
      expect(events.single.id, 'y');
    });

    test('non-numeric event time throws ArgumentError', () {
      const body = '{"type":"FeatureCollection","features":['
          '{"type":"Feature","id":"x","properties":{"mag":3.1,'
          '"place":"p","time":"not-a-number","magType":"mb"},'
          '"geometry":{"coordinates":[87.0,27.0,10]}}]}';
      expect(() => parseUsgsQuakes(body), throwsArgumentError);
    });

    test('unparseable EMSC time string throws ArgumentError', () {
      const body = '{"features":[{"properties":{"mag":3.1,'
          '"time":"not-a-date","lat":27.0,"lon":87.0,"depth":10},'
          '"geometry":{"coordinates":[87.0,27.0,10]}}]}';
      expect(() => parseEmscQuakes(body), throwsArgumentError);
    });
  });

  group('nearestPalikaTo — nGeo centroids', () {
    test('a Kathmandu Valley point resolves to a nearby palika', () {
      final n = nearestPalikaTo(27.7172, 85.3240);
      expect(n, isNotNull);
      expect(n!.distanceKm, lessThan(30.0));
      expect(n.body.districtName, isNotEmpty);
      expect(n.body.provinceName, isNotEmpty);
    });

    test('a Himal epicentre still resolves (nearest-centroid, labelled)', () {
      final n = nearestPalikaTo(28.0314, 87.3256);
      expect(n, isNotNull);
      expect(n!.body.name, isNotEmpty);
    });
  });

  group('QuakeClient', () {
    test('sends the receipted Nepal-box queries and matches the pair set',
        () async {
      final urls = <Uri>[];
      final client = QuakeClient(
        client: _FakeHttp((uri) async {
          urls.add(uri);
          if (uri.host.contains('usgs')) {
            return http.Response(usgsFixture, 200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          }
          return http.Response(emscFixture, 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );
      final bundle = await client.fetchAll(
          now: DateTime.utc(2026, 11, 14, 2, 30));
      expect(urls.length, 2);
      final usgsUrl = urls.firstWhere((u) => u.host.contains('usgs'));
      expect(usgsUrl.queryParameters['minmagnitude'], '2.5');
      expect(usgsUrl.queryParameters['orderby'], 'time');
      expect(usgsUrl.queryParameters['starttime'], '2026-10-15');
      final emscUrl = urls.firstWhere((u) => u.host.contains('seismicportal'));
      expect(emscUrl.queryParameters['format'], 'json');
      expect(bundle.usgs.length, 5);
      expect(bundle.emsc.length, 32);
      expect(bundle.matches.where((m) => m.isMatched).length, 4);
      expect(bundle.usgsError, isNull);
      expect(bundle.emscError, isNull);
    });

    test('one dead catalogue degrades to single-source rows', () async {
      final client = QuakeClient(
        client: _FakeHttp((uri) async {
          if (uri.host.contains('usgs')) {
            return http.Response('boom', 500);
          }
          return http.Response(emscFixture, 200);
        }),
      );
      final bundle = await client.fetchAll(
          now: DateTime.utc(2026, 11, 14, 2, 30));
      expect(bundle.usgs, isEmpty);
      expect(bundle.usgsError, isNotNull);
      expect(bundle.emsc.length, 32);
      expect(bundle.matches.every((m) => m.usgs == null), isTrue);
    });

    test('both dead raises StateError', () async {
      final client = QuakeClient(
        client: _FakeHttp((uri) async => http.Response('boom', 500)),
      );
      expect(() => client.fetchAll(now: DateTime.utc(2026, 11, 14)),
          throwsStateError);
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
