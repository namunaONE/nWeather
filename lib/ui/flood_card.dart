import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/flood_glofas.dart';
import '../data/open_meteo.dart' show humanAge;
import '../state/compare_provider.dart';
import '../state/flood_provider.dart';
import '../state/place_controller.dart';
import 'panel_frame.dart';

/// Wires the selected place's coordinates into the flood panel. A palika
/// without coordinates fails closed: an honest explanation, no numbers.
class FloodSection extends ConsumerWidget {
  const FloodSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(placeProvider);
    final coords = coordinatesOf(place);
    if (coords == null) {
      return const PanelFrame(
        title: 'Flood',
        child: Text(
          'This palika has no coordinates yet. Model lookups fail closed: '
          'nothing is shown rather than a forecast for a wrong place.',
        ),
      );
    }
    final async = ref.watch(floodProvider((lat: coords.lat, lng: coords.lng)));
    return async.when(
      loading: () => const PanelFrame(
        title: 'Flood',
        child: Text('Fetching GloFAS river discharge…'),
      ),
      error: (e, _) => PanelFrame(
        title: 'Flood',
        child: Text('MISSING — GloFAS river discharge could not be fetched '
            '($e). Fail-closed; retry by reopening the app.'),
      ),
      data: (snapshot) =>
          FloodCard(snapshot: snapshot, now: ref.watch(clockProvider)),
    );
  }
}

/// HYA-409 — the flood panel: TWO layers, never merged into one flood risk %.
/// Layer 1 (model): GloFAS daily river discharge for the snapped 0.05° cell —
/// the LARGEST river inside the cell, which may not be the channel the user
/// meant; a small coordinate nudge can select a different channel. Layer 2
/// (official): the hydrology.gov.np bulletin, verbatim only, fail-closed
/// MISSING while its JavaScript app cannot be read (receipted 2026-11-14).
class FloodCard extends StatelessWidget {
  const FloodCard({super.key, required this.snapshot, required this.now});

  final FloodSnapshot snapshot;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stale = now.toUtc().difference(snapshot.fetchedAtUtc) >
        const Duration(hours: 30);
    final state = stale ? 'STALE' : 'FRESH';

    final header = theme.textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.outline);
    final cell = theme.textTheme.bodySmall;

    final rows = snapshot.days.take(7).toList();

    return PanelFrame(
      title: 'Flood — river discharge, two layers, never merged',
      source: 'Open-Meteo Flood API · GloFAS v4 · cell '
          '${snapshot.snappedLat.toStringAsFixed(4)}, '
          '${snapshot.snappedLng.toStringAsFixed(4)}',
      age: humanAge(snapshot.fetchedAtUtc, now.toUtc()),
      tier: 'model guidance · $state · largest river in a 0.05° cell — '
          'not a khola, not a street, not a warning',
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
            child: Text(
              'What this is: the largest river inside a 0.05° grid cell — '
                  'not your khola, not a street, not an official warning. '
                  'A small coordinate nudge can select a different channel. '
                  'The model layer and the official layer are shown apart, '
                  'never merged into a flood risk %.',
              style: cell,
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
            },
            children: [
              TableRow(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('Date', style: header),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('Median', style: header),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('Min–max', style: header),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('P25–P75', style: header),
                ),
              ]),
              for (final d in rows)
                TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(d.date.substring(5), style: cell),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('${d.median.toStringAsFixed(2)} m³/s',
                        style: cell),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                        '${d.min.toStringAsFixed(2)}–${d.max.toStringAsFixed(2)}',
                        style: cell),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                        '${d.p25.toStringAsFixed(2)}–${d.p75.toStringAsFixed(2)}',
                        style: cell),
                  ),
                ]),
            ],
          ),
          const SizedBox(height: 8),
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
                  'CHWRR flood bulletin: MISSING — hydrology.gov.np is a '
                      'JavaScript app whose bulletin nWeather cannot read '
                      'yet (probes 404/502, receipted 2026-11-14). nWeather '
                      'never paraphrases an official warning without a '
                      'receipt.',
                  style: cell,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
