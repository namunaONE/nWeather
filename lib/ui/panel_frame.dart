import 'package:flutter/material.dart';

import 'honesty_label.dart';

/// One bento tile (HYA-460 anatomy). Tile size = truth priority; every tile
/// is standalone with its own provenance footer. Pass [source], [age] and
/// [tier] to attach the honesty footer; a measured panel never omits them.
class PanelFrame extends StatelessWidget {
  const PanelFrame({
    super.key,
    required this.title,
    required this.child,
    this.source,
    this.age,
    this.tier,
  });

  final String title;
  final Widget child;
  final String? source;
  final String? age;
  final String? tier;

  @override
  Widget build(BuildContext context) {
    final hasFooter = source != null && age != null && tier != null;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
            if (hasFooter) ...[
              const SizedBox(height: 12),
              HonestyFooter(source: source!, age: age!, tier: tier!),
            ],
          ],
        ),
      ),
    );
  }
}
