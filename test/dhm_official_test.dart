import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:nweather/data/dhm_official.dart';
import '../tool/fetch_dhm.dart' as fetcher;

void main() {
  group('normalizeCountryForecast (gates vs live fixture)', () {
    final fixture = jsonDecode(
        File('test/fixtures/dhm/country-forecast.json').readAsStringSync())
        as Map<String, dynamic>;

    test('accepts the live receipt', () {
      final f = fetcher.normalizeCountryForecast(fixture);
      expect(f.id, '1474');
      expect(f.issuedAt, DateTime.utc(2026, 11, 13, 12, 15));
      expect(f.dayEn, contains('Partly cloudy'));
      expect(f.nightNe, contains('कोशी'));
    });

    test('empty text field fails the gate (fail-closed)', () {
      final bad = {...fixture}..['en_text_1'] = '   ';
      expect(() => fetcher.normalizeCountryForecast(bad), throwsArgumentError);
    });

    test('missing field fails the gate', () {
      final bad = {...fixture}..remove('analysis_np');
      expect(() => fetcher.normalizeCountryForecast(bad), throwsArgumentError);
    });

    test('unparseable issue_date fails the gate', () {
      final bad = {...fixture}..['issue_date'] = 'not-a-date';
      expect(() => fetcher.normalizeCountryForecast(bad), throwsArgumentError);
    });
  });

  group('normalizeThreeDays', () {
    final rows = jsonDecode(
            File('test/fixtures/dhm/three-days-forecast-latest.json').readAsStringSync())
        as List<dynamic>;

    test('takes the newest usable row, verbatim title', () {
      final b = fetcher.normalizeThreeDays(rows);
      expect(b, isNotNull);
      expect(b!.id, '1663');
      expect(b.title, contains('पाँच दिनको'));
      expect(b.issuedAt, DateTime.utc(2026, 11, 13, 12, 15));
    });

    test('no usable row -> null (app shows MISSING)', () {
      expect(fetcher.normalizeThreeDays([]), isNull);
      expect(fetcher.normalizeThreeDays([{'id': ''}]), isNull);
    });
  });

  group('parseDhmOfficialSnapshot (fail-closed)', () {
    final f = fetcher.normalizeCountryForecast(jsonDecode(
        File('test/fixtures/dhm/country-forecast.json').readAsStringSync())
        as Map<String, dynamic>);

    Map<String, dynamic> snapshot({Map<String, dynamic>? forecast, dynamic bulletin}) => {
          'schema': dhmOfficialSchema,
          'fetchedAt': '2026-11-14T00:00:00.000Z',
          'forecast24': forecast ?? {
              'id': f.id,
              'issuedAt': f.issuedAt.toIso8601String(),
              'analysisNe': f.analysisNe,
              'analysisEn': f.analysisEn,
              'dayNe': f.dayNe,
              'dayEn': f.dayEn,
              'nightNe': f.nightNe,
              'nightEn': f.nightEn,
            },
          'bulletin': bulletin,
        };

    test('accepts a well-formed snapshot', () {
      final s = parseDhmOfficialSnapshot(jsonEncode(snapshot(bulletin: null)));
      expect(s.forecast24, isNotNull);
      expect(s.bulletin, isNull);
      expect(s.fetchedAt, DateTime.utc(2026, 11, 14));
    });

    test('unknown schema version throws', () {
      final bad = snapshot(bulletin: null)..['schema'] = 'nweather/dhm-official@999';
      expect(() => parseDhmOfficialSnapshot(jsonEncode(bad)), throwsArgumentError);
    });

    test('missing fetchedAt throws', () {
      final bad = snapshot(bulletin: null)..remove('fetchedAt');
      expect(() => parseDhmOfficialSnapshot(jsonEncode(bad)), throwsArgumentError);
    });

    test('incomplete forecast24 throws (never a partial official strip)', () {
      final partial = {...snapshot(bulletin: null)['forecast24'] as Map<String, dynamic>}..remove('nightEn');
      final bad = snapshot(bulletin: null)..['forecast24'] = partial;
      expect(() => parseDhmOfficialSnapshot(jsonEncode(bad)), throwsArgumentError);
    });
  });

  group('province matching + sentences', () {
    const en = 'Partly cloudy over Koshi Province. Mainly fair elsewhere.';
    test('marks the mentioned province only', () {
      expect(mentionsProvince(en, 'Koshi'), isTrue);
      expect(mentionsProvince(en, 'Karnali'), isFalse);
    });

    test('matches Devanagari province names', () {
      expect(mentionsProvince('कोशी प्रदेशको हिमाली भू-भागमा', 'Koshi'), isTrue);
      expect(mentionsProvince('सुदूरपश्चिम प्रदेश', 'Sudurpashchim'), isTrue);
    });

    test('splits Nepali danda and Latin stops', () {
      final s = splitSentences('पहिलो वाक्य। दोस्रो वाक्य। Partly cloudy. Then fair.');
      expect(s.length, 4);
    });
  });

  group('stamps + staleness', () {
    test('NPT stamp is +05:45', () {
      expect(nptStamp(DateTime.utc(2026, 11, 13, 12, 15)),
          '2026-11-13 18:00 NPT');
    });

    test('staleness budget is 30 h', () {
      final now = DateTime.utc(2026, 11, 14);
      expect(isStaleOfficial(now.subtract(const Duration(hours: 29)), now), isFalse);
      expect(isStaleOfficial(now.subtract(const Duration(hours: 31)), now), isTrue);
    });
  });
}
