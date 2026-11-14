import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/open_meteo.dart' show humanAge;
import '../data/quake_catalogue.dart';
import '../data/quake_geo.dart';
import '../state/compare_provider.dart';
import '../state/quake_provider.dart';
import 'panel_frame.dart';

/// HYA-410 — the earthquake panel. Nepal-box events from TWO independent
/// catalogues (USGS, EMSC), matched only when |dt| <= 60 s AND <= 30 km,
/// with BOTH magnitudes shown side by side — never merged, never averaged.
/// Permanent banner: not early warning, not a drop-cover-hold trigger.
class QuakeSection extends ConsumerWidget {
  const QuakeSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(quakeProvider);
    return async.when(
      loading: () => const PanelFrame(
        title: 'Earthquakes',
        child: Text('Fetching USGS and EMSC catalogues…'),
      ),
      error: (e, _) => PanelFrame(
        title: 'Earthquakes',
        child: Text('MISSING — both quake catalogues could not be fetched '
            '($e). Fail-closed; retry by reopening the app.'),
      ),
      data: (bundle) =>
          QuakeCard(bundle: bundle, now: ref.watch(clockProvider)),
    );
  }
}

String _pad2(int n) => n.toString().padLeft(2, '0');

String _nptLabel(DateTime utc) {
  final npt = utc.toUtc().add(const Duration(hours: 5, minutes: 45));
  return '${npt.year}-${_pad2(npt.month)}-${_pad2(npt.day)} '
      '${_pad2(npt.hour)}:${_pad2(npt.minute)} NPT';
}

class QuakeCard extends StatelessWidget {
  const QuakeCard({super.key, required this.bundle, required this.now});

  final QuakeBundle bundle;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stale = now.toUtc().difference(bundle.fetchedAtUtc) >
        const Duration(hours: 12);
    final state = stale ? 'STALE' : 'FRESH';

    final header = theme.textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.outline);
    final cell = theme.textTheme.bodySmall;

    const maxRows = 15;
    final rows = bundle.matches.take(maxRows).toList();

    String magCell(QuakeEvent? e) {
      if (e == null) return '—';
      final m = e.mag.toStringAsFixed(1);
      return e.magType.isEmpty ? m : '$m ${e.magType}';
    }

    return PanelFrame(
      title: 'Earthquakes — two catalogues, both magnitudes, never merged',
      source: 'USGS FDSN · EMSC fdsnws · Nepal box 26–30.5 N, 80–88.5 E',
      age: humanAge(bundle.fetchedAtUtc, now.toUtc()),
      tier: 'catalogue reports · $state · revised data · never early warning',
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
              'What this is: reports from two independent earthquake '
                  'catalogues, matched only when time and place agree. BOTH '
                  'magnitudes are shown — they use different scales and '
                  'often disagree; nWeather never averages them. This is '
                  'NOT early warning and NOT a drop-cover-hold trigger. '
                  'Magnitudes and locations are revised by the networks.',
              style: cell,
            ),
          ),
          const SizedBox(height: 8),
          if (bundle.usgsError != null)
            Text('USGS: MISSING — ${bundle.usgsError} (EMSC rows shown '
                'single-source).', style: cell),
          if (bundle.emscError != null)
            Text('EMSC: MISSING — ${bundle.emscError} (USGS rows shown '
                'single-source).', style: cell),
          if (bundle.matches.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  'No events in the last 30 days inside the Nepal box at the '
                  'receipted query floor.',
                  style: cell),
            )
          else ...[
            const SizedBox(height: 8),
            Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(1.4),
                1: FlexColumnWidth(1.6),
                2: FlexColumnWidth(0.9),
                3: FlexColumnWidth(0.9),
                4: FlexColumnWidth(0.7),
              },
              children: [
                TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('When (NPT)', style: header),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('Nearest palika', style: header),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('USGS', style: header),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('EMSC', style: header),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('Δ km', style: header),
                  ),
                ]),
                for (final m in rows)
                  TableRow(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(_nptLabel(m.timeUtc), style: cell),
                    ),
                    Builder(builder: (_) {
                      final n = nearestPalikaTo(m.lat, m.lng);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          n == null
                              ? '—'
                              : '${n.body.name} (${n.body.districtName}) · '
                                  '${n.distanceKm.toStringAsFixed(0)} km',
                          style: cell,
                        ),
                      );
                    }),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(magCell(m.usgs), style: cell),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(magCell(m.emsc), style: cell),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                          m.distanceKm?.toStringAsFixed(1) ?? '·',
                          style: cell),
                    ),
                  ]),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              bundle.matches.length > maxRows
                  ? 'Showing the latest $maxRows of ${bundle.matches.length} '
                      'events (30-day window).'
                  : '${bundle.matches.length} events in the last 30 days.',
              style: cell,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            "Nepal's own network — the National Seismological Centre "
                "(seismonepal.gov.np) — has no public query API, so nWeather "
                "links out instead of scraping it.",
            style: cell,
          ),
        ],
      ),
    );
  }
}
