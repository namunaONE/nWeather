import 'package:flutter_test/flutter_test.dart';
import 'package:nepal_admin_api/nepal_admin_api.dart';
import 'package:nepali_date/nepali_date.dart';
import 'package:nepali_date_data/nepali_date_data.dart';

void main() {
  group('place data (nGeo / nepal_admin_api)', () {
    test('national totals match the official federal structure', () {
      expect(NepalAdminApi.getAllProvinces().length, 7);
      expect(NepalAdminApi.getAllDistricts().length, 77);
      expect(NepalAdminApi.getAllLocalBodies().length, 753);
    });

    test('bilingual search finds Bharatpur by Devanagari', () {
      final r = NepalAdminApi.search('भारतपुर');
      expect(r.localBodies.any((b) => b.name == 'Bharatpur'), isTrue);
    });

    test('default place resolves (Kathmandu, Kathmandu)', () {
      final ktm = NepalAdminApi.getLocalBodiesByName('Kathmandu', 'Kathmandu');
      expect(ktm, isNotEmpty);
      expect(ktm.first.type, LocalBodyType.metropolitan);
    });
  });

  group('BS date (nMiti / nepali_date_data)', () {
    test('calendar spans the declared BS 1975-2100 range', () {
      expect(fullCalendar.firstYear, 1975);
      expect(fullCalendar.lastYear, 2100);
    });

    test('AD -> BS -> AD round-trips inside the table', () {
      const samples = [
        (2020, 5, 1),
        (2026, 11, 13),
        (2080, 1, 15),
      ];
      for (final (y, m, d) in samples) {
        final g = DateTime.utc(y, m, d);
        final bs = fullCalendar.fromGregorian(g);
        expect(fullCalendar.toGregorian(bs), g);
      }
    });

    test('refuses dates outside the table (fail-closed, never guesses)', () {
      expect(
        () => fullCalendar.fromGregorian(DateTime.utc(1970, 1, 1)),
        throwsArgumentError,
      );
    });
  });
}
