import 'package:material_ui/material_ui.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dhm_official.dart';
import '../data/open_meteo.dart' show humanAge;
import '../state/dhm_provider.dart';
import '../state/place_controller.dart';
import 'panel_frame.dart';

/// The official DHM strip (HYA-454): verbatim bilingual forecast text
/// from the CI snapshot, province sentences highlighted, staleness
/// honest. Fail-closed: any snapshot problem renders MISSING with the
/// reason — official text is never paraphrased, never silently stale.
class OfficialStrip extends ConsumerWidget {
  const OfficialStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dhmOfficialProvider);
    return async.when(
      loading: () => const PanelFrame(
        title: 'Official words — DHM',
        child: Text('Reading the DHM snapshot…'),
      ),
      error: (e, _) => PanelFrame(
        title: 'Official words — DHM',
        source: 'DHM MFD · dhm.gov.np/mfd/api',
        age: 'unavailable',
        tier: 'MISSING — fail-closed',
        child: Text('MISSING — the official snapshot could not be read ($e). '
            'nWeather shows nothing rather than stale text presented as current.'),
      ),
      data: (snap) => _OfficialStripData(snapshot: snap),
    );
  }
}

class _OfficialStripData extends ConsumerWidget {
  const _OfficialStripData({required this.snapshot});

  final DhmOfficialSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(placeProvider);
    final now = DateTime.now().toUtc();
    final f = snapshot.forecast24;
    final bulletin = snapshot.bulletin;

    if (f == null) {
      return const PanelFrame(
        title: 'Official words — DHM',
        source: 'DHM MFD · dhm.gov.np/mfd/api',
        age: 'unavailable',
        tier: 'MISSING — fail-closed',
        child: Text('MISSING — the snapshot carries no 24 h forecast. '
            'nWeather never shows official text without a receipt.'),
      );
    }

    final stale = isStaleOfficial(f.issuedAt, now);
    final badge = stale ? 'STALE' : 'FRESH';
    final label = stale ? 'STALE — issued more than 30 h ago' : 'FRESH';

    return PanelFrame(
      title: 'Official words — DHM ($badge)',
      source: 'DHM MFD · dhm.gov.np/mfd/api (snapshot ${snapshot.schema})',
      age: 'issued ${nptStamp(f.issuedAt)} · snapshot ${humanAge(snapshot.fetchedAt, now)}',
      tier: 'official — verbatim, never paraphrased · $label',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Section(label: 'Analysis', en: f.analysisEn, ne: f.analysisNe, province: place.provinceName),
          const SizedBox(height: 12),
          _Section(label: 'Day', en: f.dayEn, ne: f.dayNe, province: place.provinceName),
          const SizedBox(height: 12),
          _Section(label: 'Night', en: f.nightEn, ne: f.nightNe, province: place.provinceName),
          const SizedBox(height: 12),
          bulletin == null
              ? const Text('DHM bulletin: MISSING — the official snapshot has no '
                  'bulletin right now. nWeather never paraphrases an official '
                  'warning without a receipt.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('DHM bulletin (verbatim): ${bulletin.title}'),
                    const SizedBox(height: 4),
                    Text('issued ${nptStamp(bulletin.issuedAt)}'),
                  ],
                ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.en,
    required this.ne,
    required this.province,
  });

  final String label;
  final String en;
  final String ne;
  final String province;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label — official', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Text.rich(TextSpan(children: _highlight(context, en, base))),
        const SizedBox(height: 4),
        Text.rich(TextSpan(children: _highlight(context, ne, base))),
      ],
    );
  }

  /// Province-mention sentences are marked, never hidden: bold + primary
  /// color. Everything DHM wrote stays on screen, verbatim.
  List<InlineSpan> _highlight(BuildContext context, String text, TextStyle base) {
    final theme = Theme.of(context);
    final hot =
        base.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.primary);
    return [
      for (final s in splitSentences(text))
        TextSpan(text: '$s ', style: mentionsProvince(s, province) ? hot : base),
    ];
  }
}
