import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/open_meteo.dart' show humanAge;
import '../data/thunder.dart';
import '../state/compare_provider.dart' show clockProvider;
import '../state/place_controller.dart';
import '../state/thunder_provider.dart';
import 'panel_frame.dart';

/// Wires the selected place into the thunder tile. A palika without
/// coordinates fails closed: an honest explanation, no numbers.
class ThunderSection extends ConsumerWidget {
  const ThunderSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(placeProvider);
    final coords = coordinatesOf(place);
    if (coords == null) {
      return const PanelFrame(
        title: 'Thunder outlook',
        child: Text(
          'This palika has no coordinates yet. Thunder guidance fails '
          'closed: nothing is shown rather than a forecast for a wrong place.',
        ),
      );
    }
    final async =
        ref.watch(thunderProvider((lat: coords.lat, lng: coords.lng)));
    return async.when(
      loading: () => const PanelFrame(
        title: 'Thunder outlook',
        child: Text('Fetching model guidance…'),
      ),
      error: (e, _) => PanelFrame(
        title: 'Thunder outlook',
        child: Text('MISSING — model guidance could not be fetched ($e). '
            'Fail-closed; retry by reopening the app.'),
      ),
      data: (reports) =>
          ThunderCard(reports: reports, now: ref.watch(clockProvider)),
    );
  }
}

String _pad2(int n) => n.toString().padLeft(2, '0');

String _nptLabel(DateTime utc) {
  final npt = utc.toUtc().add(const Duration(hours: 5, minutes: 45));
  return '${npt.year}-${_pad2(npt.month)}-${_pad2(npt.day)} '
      '${_pad2(npt.hour)}:${_pad2(npt.minute)} NPT';
}

/// HYA-411 — the thunder line. Derived from WMO weather codes 95–99 and
/// CAPE per model. NOT lightning detection, NOT a DHM warning.
class ThunderCard extends StatelessWidget {
  const ThunderCard({super.key, required this.reports, required this.now});

  final List<ThunderReport> reports;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cell = theme.textTheme.bodySmall;
    final header = theme.textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.outline);

    final valid = reports.where((r) => !r.isMissing).toList();
    final stale = valid.any((r) =>
        now.toUtc().difference(r.fetchedAtUtc) > const Duration(hours: 24));
    final state = valid.isEmpty ? 'MISSING' : (stale ? 'STALE' : 'FRESH');

    DateTime? minFetch;
    for (final r in valid) {
      if (minFetch == null || r.fetchedAtUtc.isBefore(minFetch)) {
        minFetch = r.fetchedAtUtc;
      }
    }

    String capeCell(ThunderReport r) {
      if (!r.capeIssued) return 'not issued';
      final m = r.maxCape;
      return m == null ? '—' : '${m.toStringAsFixed(0)} J/kg';
    }

    return PanelFrame(
      title: 'Thunder outlook — model guidance, not lightning detection',
      source: 'Open-Meteo forecast · weathercode 95–99 + CAPE · '
          '${reports.map((r) => r.modelId).join(', ')}',
      age: minFetch == null ? 'no data' : humanAge(minFetch.toUtc(), now.toUtc()),
      tier: 'model guidance · $state · never a DHM warning',
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
              'What this is: hours each model flags with WMO thunderstorm '
                  'codes 95–99, plus CAPE (J/kg) as context. NOT lightning '
                  'detection and NOT a DHM warning — official thunder words, '
                  'when issued, live only in the DHM strip.',
              style: cell,
            ),
          ),
          const SizedBox(height: 8),
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const <int, TableColumnWidth>{
              0: FlexColumnWidth(1.3),
              1: FlexColumnWidth(1.2),
              2: FlexColumnWidth(1.2),
              3: FlexColumnWidth(1.4),
              4: FlexColumnWidth(1),
            },
            children: [
              TableRow(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('Model', style: header),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('Grid cell', style: header),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('Thunder hours', style: header),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('First (NPT)', style: header),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('Max CAPE', style: header),
                ),
              ]),
              for (final r in reports)
                TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(r.isMissing ? 'MISSING' : r.shortLabel,
                        style: cell),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      r.isMissing
                          ? '—'
                          : '${r.snappedLat.toStringAsFixed(4)}, '
                              '${r.snappedLng.toStringAsFixed(4)}',
                      style: cell,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      r.isMissing
                          ? '—'
                          : '${r.thunderHours} of ${r.hoursCovered} h',
                      style: cell,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      r.firstThunderUtc == null
                          ? '—'
                          : _nptLabel(r.firstThunderUtc!),
                      style: cell,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(r.isMissing ? '—' : capeCell(r), style: cell),
                  ),
                ]),
            ],
          ),
          for (final r in reports)
            if (r.isMissing)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${r.modelId}: MISSING — ${r.error}', style: cell),
              ),
          const SizedBox(height: 8),
          Text(
            'One row per model, never merged. ecmwf_aifs025_single receipts '
                'no CAPE at all — its row says so instead of borrowing a '
                'number from another model.',
            style: cell,
          ),
        ],
      ),
    );
  }
}
