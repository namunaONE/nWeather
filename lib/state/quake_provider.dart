import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/quake_catalogue.dart';
import 'compare_provider.dart' show clockProvider;

final quakeClientProvider = Provider<QuakeClient>((ref) => QuakeClient());

/// One fail-closed fetch of both quake catalogues for the Nepal box. Any
/// total failure surfaces as the provider's error — the panel shows MISSING;
/// a single dead catalogue degrades to single-source rows inside the bundle.
final quakeProvider = FutureProvider.autoDispose<QuakeBundle>((ref) async {
  final client = ref.watch(quakeClientProvider);
  final now = ref.watch(clockProvider);
  return client.fetchAll(now: now);
});
