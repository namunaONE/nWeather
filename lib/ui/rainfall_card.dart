import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/open_meteo.dart' show humanAge;
import '../data/open_meteo_ensemble.dart';
import '../state/compare_provider.dart';
import '../state/ensemble_provider.dart';
import '../state/place_controller.dart';
import 'panel_frame.dart';

/// Wires the selected place's coordinates into the rainfall card. A palika
/// without coordinates fails closed: an honest explanation, no numbers.
class RainfallSection extends ConsumerWidget {
  const RainfallSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(placeProvider);
    final coords = coordinatesOf(place);
    if (coords == null) {
      return const PanelFrame(
        title: 'Rainfall',
        child: Text(
          'This palika has no coordinates yet. Model lookups fail closed: '
          'nothing is shown rather than a forecast for a wrong place.',
        ),
      );
    }
    final async = ref.watch(ensembleProvider((lat: coords.lat, lng: coords.lng)));
    return async.when(
      loading: () => const PanelFrame(
        title: 'Rainfall',
        child: Text('Fetching ensemble guidance…'),
      ),
      error: (e, _) => PanelFrame(
        title: 'Rainfall',
        child: Text('MISSING — ensemble guidance could not be fetched ($e). '
            'Fail-closed; retry by reopening the app.'),
      ),
      data: (forecasts) =>
          RainfallCard(forecasts: forecasts, now: ref.watch(clockProvider)),
    );
  }
}

/// HYA-408 — the rainfall card: ensemble DISTRIBUTIONS per model per day
/// (min–max and member agreement), never a single number, never averaged.
/// Above the rows sits the official-words zone: verbatim DHM text only,
/// fail-closed MISSING until the verified CI parser (HYA-454) lands.
class RainfallCard extends StatelessWidget {
  const RainfallCard({super.key, required this.forecasts, required this.now});

  final List<EnsembleForecast> forecasts;
  final DateTime now;

  String _cell(EnsembleForecast f, int day) {
    if (f.isMissing || day >= f.days.length) return 'MISSING';
    final stats = dayStats(f.days[day], rainThresholdMm);
    if (stats == null) return 'n/a';
    final range =
        '${stats.minMm.toStringAsFixed(1)}–${stats.maxMm.toStringAsFixed(1)} mm';
    return '$range\n${stats.atLeast}/${stats.members} ≥ 10 mm';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayCount =
        forecasts.fold<int>(0, (max, f) => f.days.length > max ? f.days.length : max);
    final allMissing = forecasts.every((f) => f.isMissing);
    final stale = forecasts.any((f) =>
        !f.isMissing && now.difference(f.fetchedAt) > const Duration(hours: 6));
    final state = allMissing ? 'MISSING' : (stale ? 'STALE' : 'FRESH');

    final fetchedAt = forecasts.fold<DateTime?>(null, (min, f) {
      if (f.isMissing) return min;
      return min == null || f.fetchedAt.isBefore(min) ? f.fetchedAt : min;
    });

    final header = theme.textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.outline);
    final cell = theme.textTheme.bodySmall;
    final label = theme.textTheme.bodySmall
        ?.copyWith(fontWeight: FontWeight.w700);

    return PanelFrame(
      title: 'Rainfall — ensemble spread, never one number',
      source:
          'Open-Meteo Ensemble API · ${forecasts.map((f) => f.modelId).join(', ')}',
      age: fetchedAt == null ? 'no data' : humanAge(fetchedAt.toUtc(), now.toUtc()),
      tier: 'ensemble guidance · $state · distribution shown, never "DHM said"',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Official words — fail-closed', style: header),
                const SizedBox(height: 4),
                Text(
                  'DHM bulletin sentence: MISSING — the verified CI parser '
                  '(HYA-454) has not landed yet. nWeather never paraphrases '
                  'an official warning without a receipt.',
                  style: cell,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const <int, TableColumnWidth>{
              0: FlexColumnWidth(1.2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
              4: FlexColumnWidth(1),
              5: FlexColumnWidth(1),
            },
            children: [
              TableRow(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('', style: header),
                ),
                for (var d = 0; d < dayCount; d++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      forecasts.fold<String>(
                        '',
                        (out, f) =>
                            out.isNotEmpty || f.isMissing || d >= f.days.length
                                ? out
                                : f.days[d].date.substring(5),
                      ),
                      style: header,
                    ),
                  ),
              ]),
              for (final f in forecasts)
                TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(f.shortLabel, style: label),
                  ),
                  for (var d = 0; d < dayCount; d++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(_cell(f, d), style: cell),
                    ),
                ]),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Each cell is the members\' range and how many members reach '
            '10 mm — the spread is the information, so it is shown, never '
            'averaged away.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
