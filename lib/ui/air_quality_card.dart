import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/air_quality.dart';
import '../data/open_meteo.dart' show humanAge;
import '../state/air_quality_provider.dart';
import '../state/compare_provider.dart' show clockProvider;
import '../state/place_controller.dart';
import 'panel_frame.dart';

/// Wires the selected place into the air tile. A palika without coordinates
/// fails closed: an honest explanation, no numbers.
class AirSection extends ConsumerWidget {
  const AirSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(placeProvider);
    final coords = coordinatesOf(place);
    if (coords == null) {
      return const PanelFrame(
        title: 'Air, dust & UV',
        child: Text(
          'This palika has no coordinates yet. Air guidance fails closed: '
          'nothing is shown rather than air for a wrong place.',
        ),
      );
    }
    final async =
        ref.watch(airQualityProvider((lat: coords.lat, lng: coords.lng)));
    return async.when(
      loading: () => const PanelFrame(
        title: 'Air, dust & UV',
        child: Text('Fetching CAMS global guidance…'),
      ),
      error: (e, _) => PanelFrame(
        title: 'Air, dust & UV',
        child: Text('MISSING — CAMS global guidance could not be fetched '
            '($e). Fail-closed; retry by reopening the app.'),
      ),
      data: (snapshot) =>
          AirQualityCard(snapshot: snapshot, now: ref.watch(clockProvider)),
    );
  }
}

String _pad2(int n) => n.toString().padLeft(2, '0');

String _nptLabel(DateTime utc) {
  final npt = utc.toUtc().add(const Duration(hours: 5, minutes: 45));
  return '${npt.year}-${_pad2(npt.month)}-${_pad2(npt.day)} '
      '${_pad2(npt.hour)}:${_pad2(npt.minute)} NPT';
}

/// HYA-411 — the air tile. CAMS global is ONE source at ~45 km: valley-scale
/// guidance for the whole basin, never a ward number, never a Nepal AQI.
class AirQualityCard extends StatelessWidget {
  const AirQualityCard({super.key, required this.snapshot, required this.now});

  final AirSnapshot snapshot;
  final DateTime now;

  TableRow _row(TextStyle? style, String label, String value, String band) {
    return TableRow(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(label, style: style),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(value, style: style),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(band, style: style),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = snapshot.isStale(now.toUtc()) ? 'STALE' : 'FRESH';
    final cell = theme.textTheme.bodySmall;
    final header = theme.textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.outline);

    final latest = snapshot.lastIssued;
    final days = dailyMaxFrom(snapshot.hours, snapshot.fetchedAtUtc);

    String fmt(double? v, int digits) =>
        v == null ? 'not issued' : v.toStringAsFixed(digits);

    return PanelFrame(
      title: 'Air, dust & UV — CAMS global, valley-scale',
      source: 'Open-Meteo Air Quality · CAMS global ~45 km · one source, '
          'no model spread',
      age: humanAge(snapshot.fetchedAtUtc, now.toUtc()),
      tier: 'model guidance · $state · US EPA AQI scale · no European pollen '
          '(domain does not cover Nepal)',
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
              'What this is: model guidance for a ~45 km grid cell — one '
                  'value for the whole basin, not your ward or street. Grid '
                  'cell ${snapshot.snappedLat.toStringAsFixed(4)}, '
                  '${snapshot.snappedLng.toStringAsFixed(4)} (requested '
                  '${snapshot.requestLat.toStringAsFixed(4)}, '
                  '${snapshot.requestLng.toStringAsFixed(4)}). The AQI here '
                  'is the US EPA scale computed by Open-Meteo; Nepal has no '
                  'receipted national AQI feed, so none is shown.',
              style: cell,
            ),
          ),
          const SizedBox(height: 8),
          if (latest == null)
            Text('The model run has issued no values for this cell yet.',
                style: cell)
          else ...[
            Text(
              'Latest issued hour: ${_nptLabel(latest.timeUtc)} — later '
                  'hours are not yet issued by the model run (blank, never '
                  'zero).',
              style: cell,
            ),
            const SizedBox(height: 8),
            Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(1.2),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1.8),
              },
              children: [
                TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('Measure (latest hour)', style: header),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('Value', style: header),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('Scale / band', style: header),
                  ),
                ]),
                _row(cell, 'PM2.5', fmt(latest.pm25, 1), 'μg/m³'),
                _row(cell, 'PM10', fmt(latest.pm10, 1), 'μg/m³'),
                _row(cell, 'Dust', fmt(latest.dust, 1), 'μg/m³'),
                _row(cell, 'Ozone', fmt(latest.ozone, 1), 'μg/m³'),
                _row(cell, 'UV index', fmt(latest.uvIndex, 1),
                    latest.uvIndex == null ? '—' : uvBand(latest.uvIndex!)),
                _row(cell, 'US AQI', fmt(latest.usAqi, 0),
                    latest.usAqi == null ? '—' : usAqiBand(latest.usAqi!)),
              ],
            ),
          ],
          const SizedBox(height: 8),
          if (days.isNotEmpty) ...[
            Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(1.2),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
              },
              children: [
                TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('Day (NPT)', style: header),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('Max PM2.5', style: header),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('Max US AQI', style: header),
                  ),
                ]),
                for (final d in days)
                  TableRow(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(d.day, style: cell),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(fmt(d.maxPm25, 1), style: cell),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(fmt(d.maxUsAqi, 0), style: cell),
                    ),
                  ]),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Text(
            'CAMS global is natively 3-hourly; Open-Meteo delivers it '
                'hourly. European pollen variables are never shown: that '
                'domain does not cover Nepal.',
            style: cell,
          ),
        ],
      ),
    );
  }
}
