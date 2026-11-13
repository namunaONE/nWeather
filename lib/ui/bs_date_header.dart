import 'package:flutter/material.dart';
import 'package:nepali_date/nepali_date.dart';
import 'package:nepali_date_data/nepali_date_data.dart';

/// Today's Bikram Sambat date, bilingual, with its evidence tier shown
/// (honesty contract: a date carries its provenance like any other value).
///
/// Fail-closed: a date outside the declared table renders an explicit
/// MISSING state — nMiti never converts outside its range, and nWeather
/// never shows a guessed date.
class BsDateHeader extends StatelessWidget {
  const BsDateHeader({super.key, this.now});

  /// Injectable clock for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final DateTime today = now ?? DateTime.now();
    try {
      final BsDate bs = fullCalendar.fromGregorian(today);
      final bool verifiedCore = bs.year <= coreCalendar.lastYear;
      final String tier = verifiedCore
          ? 'verified table (BS 1975-${coreCalendar.lastYear})'
          : 'projection tail (BS ${coreCalendar.lastYear + 1}-${fullCalendar.lastYear})';

      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${bsMonthNameNp(bs.month)} ${toNepaliDigits('${bs.day}')}, '
                '${toNepaliDigits('${bs.year}')}',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                '${bsMonthNameEn(bs.month)} ${bs.day}, ${bs.year} · '
                '${weekdayNamesNp[today.weekday]} / ${weekdayNamesEn[today.weekday]}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'source: nMiti (nepali_date_data) · age: today · tier: $tier',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      );
    } on ArgumentError {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('BS date unavailable', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Today is outside the verified conversion table '
                '(BS ${fullCalendar.firstYear}-${fullCalendar.lastYear}). '
                'Showing nothing instead of guessing.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }
  }
}
