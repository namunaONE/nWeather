import 'package:flutter/material.dart';

/// The honesty footer that travels with every value: source, age, tier.
/// This is the UI contract from docs/methodology.md — every panel embeds one.
/// A tile without provenance is a bug, not a style choice.
class HonestyFooter extends StatelessWidget {
  const HonestyFooter({
    super.key,
    required this.source,
    required this.age,
    required this.tier,
  });

  /// Where the value came from (exact source/model, never a vague "API").
  final String source;

  /// How old the value is, in honest terms (e.g. 'static dataset',
  /// 'fetched 5 min ago', 'MISSING — stale beyond budget').
  final String age;

  /// Evidence tier (e.g. 'official fail-closed', 'model guidance',
  /// 'verified table', 'projection').
  final String tier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    return Text(
      'source: $source · age: $age · tier: $tier',
      style: style,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
