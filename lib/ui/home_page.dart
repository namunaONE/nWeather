import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nepal_admin_api/nepal_admin_api.dart';

import '../state/place_controller.dart';
import 'bs_date_header.dart';
import 'compare_card.dart';
import 'flood_card.dart';
import 'official_strip.dart';
import 'panel_frame.dart';
import 'place_picker.dart';
import 'quake_card.dart';
import 'rainfall_card.dart';

/// The bento-grid home. Mobile stacks in strict priority order
/// (hazard -> official -> now/48h -> rest, HYA-460); today: date, official
/// DHM strip, place, compare card, rainfall card, flood panel, earthquake
/// panel, roadmap.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final LocalBody place = ref.watch(placeProvider);
    final coords = coordinatesOf(place);

    return Scaffold(
      appBar: AppBar(
        title: const Text('nWeather'),
        actions: [
          TextButton.icon(
            onPressed: () => showPlacePicker(context),
            icon: const Icon(Icons.place_outlined),
            label: Text(place.name),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BsDateHeader(),
                const SizedBox(height: 12),
                const OfficialStrip(),
                const SizedBox(height: 12),
                PanelFrame(
                  title: 'Place',
                  source: 'nGeo (nepal_admin_api)',
                  age: 'static dataset, committed',
                  tier: coords == null
                      ? 'no coordinates — lookups fail-closed'
                      : coords.source,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(place.displayBoth,
                          style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text('${place.type.fullName} · ${place.fullPath}'),
                      const SizedBox(height: 4),
                      Text(coords == null
                          ? 'No coordinates for this palika yet.'
                          : '${coords.lat.toStringAsFixed(4)}, '
                              '${coords.lng.toStringAsFixed(4)}'),
                      const SizedBox(height: 4),
                      Text(place.cbsCode == null
                          ? 'CBS code: none attested (never guessed)'
                          : 'CBS code: ${place.cbsCodeString} '
                              '(${place.cbsCodeConfidence.wireName})'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const CompareSection(),
                const SizedBox(height: 12),
                const RainfallSection(),
                const SizedBox(height: 12),
                const FloodSection(),
                const SizedBox(height: 12),
                const QuakeSection(),
                const SizedBox(height: 12),
                const PanelFrame(
                  title: 'Coming next — contract-first, no fake data',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('• Air quality panel (HYA-411)'),
                      Text('• /cache/*.json snapshots served same-origin by '
                          'Pages (HYA-412)'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
