import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/open_meteo.dart';
import '../state/compare_provider.dart';
import '../state/place_controller.dart';
import 'panel_frame.dart';

/// Wires the selected place's coordinates into the compare card. A palika
/// without coordinates fails closed: an honest explanation, no numbers.
class CompareSection extends ConsumerWidget {
  const CompareSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(placeProvider);
    final coords = coordinatesOf(place);
    if (coords == null) {
      return const PanelFrame(
        title: 'Weather compare',
        child: Text(
          'This palika has no coordinates yet. Weather lookups fail closed: '
          'nothing is shown rather than a forecast for a wrong place.',
        ),
      );
    }
    final async = ref.watch(compareProvider((lat: coords.lat, lng: coords.lng)));
    return async.when(
      loading: () => const PanelFrame(
        title: 'Weather compare',
        child: Text('Fetching model guidance…'),
      ),
      error: (e, _) => PanelFrame(
        title: 'Weather compare',
        child: Text('MISSING — model guidance could not be fetched ($e). '
            'Fail-closed; pull to retry by reopening the app.'),
      ),
      data: (forecasts) => CompareCard(forecasts: forecasts, now: ref.watch(clockProvider)),
    );
  }
}

/// The compare card (HYA-407): one column per model, one row per day, plus a
/// per-day spread. Models are never averaged into one number — the spread
/// makes disagreement visible, which is the product.
class CompareCard extends StatelessWidget {
  const CompareCard({super.key, required this.forecasts, required this.now});

  final List<ModelForecast> forecasts;
  final DateTime now;

  String _cell(ModelForecast f, int day) {
    if (f.isMissing || day >= f.days.length) return 'MISSING';
    final v = f.days[day].tMaxC;
    return v == null ? 'n/a' : '${v.toStringAsFixed(1)}°';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayCount = forecasts.fold<int>(0, (max, f) => f.days.length > max ? f.days.length : max);
    final allMissing = forecasts.every((f) => f.isMissing);
    final stale = forecasts.any((f) => !f.isMissing && now.difference(f.fetchedAt) > const Duration(hours: 6));
    final state = allMissing ? 'MISSING' : (stale ? 'STALE' : 'FRESH');

    final fetchedAt = forecasts.fold<DateTime?>(null, (min, f) {
      if (f.isMissing) return min;
      return min == null || f.fetchedAt.isBefore(min) ? f.fetchedAt : min;
    });

    final header = theme.textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.outline);
    final cell = theme.textTheme.bodyMedium;
    final highlight = theme.textTheme.bodyMedium
        ?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.tertiary);

    return PanelFrame(
      title: 'Weather compare — model guidance, never averaged',
      source: 'Open-Meteo · ${forecasts.map((f) => f.modelId).join(', ')}',
      age: fetchedAt == null ? 'no data' : humanAge(fetchedAt.toUtc(), now.toUtc()),
      tier: 'model guidance · $state · never "DHM said"',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
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
                  child: Text('Day', style: header),
                ),
                for (final f in forecasts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(f.shortLabel, textAlign: TextAlign.center, style: header),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('Spread', textAlign: TextAlign.right, style: header),
                ),
              ]),
              for (var i = 0; i < dayCount; i++)
                TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(forecasts.first.days.length > i ? forecasts.first.days[i].date.substring(5) : ''),
                  ),
                  for (final f in forecasts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(_cell(f, i), textAlign: TextAlign.center, style: cell),
                    ),
                  Builder(builder: (context) {
                    final s = spreadOf(forecasts, i);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        s == null ? '—' : '${s.toStringAsFixed(1)}°',
                        textAlign: TextAlign.right,
                        style: s != null && s >= 2.0 ? highlight : cell,
                      ),
                    );
                  }),
                ]),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'One column per model. nWeather never averages models into one '
            'number; a spread ≥ 2.0° is bolded so disagreement is visible.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
