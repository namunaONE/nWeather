import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nepal_admin_api/nepal_admin_api.dart';

import '../state/place_controller.dart';

/// Panel 1 place picker (HYA-458): bilingual search over all 753 palikas,
/// 77 districts and 7 provinces, powered by nGeo. Local-body names are not
/// unique nationwide, so every result shows its full path for disambiguation.
Future<void> showPlacePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _PlacePickerSheet(),
  );
}

class _PlacePickerSheet extends ConsumerStatefulWidget {
  const _PlacePickerSheet();

  @override
  ConsumerState<_PlacePickerSheet> createState() => _PlacePickerSheetState();
}

class _PlacePickerSheetState extends ConsumerState<_PlacePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final SearchResult results = _query.trim().isEmpty
        ? const SearchResult()
        : NepalAdminApi.search(_query);
    final List<LocalBody> bodies = results.localBodies.take(30).toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search palika, district, province — English or देवनागरी',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final b in bodies)
                  ListTile(
                    title: Text(b.displayBoth),
                    subtitle: Text(b.fullPath),
                    trailing: Text(b.type.shortName),
                    onTap: () {
                      ref.read(placeProvider.notifier).state = b;
                      Navigator.of(context).pop();
                    },
                  ),
                if (_query.trim().isNotEmpty && results.isEmpty)
                  const ListTile(
                    title: Text('No match. Search works in both scripts.'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
