import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/dhm_official.dart';

/// The CI-produced official snapshot, served same-origin by Pages at
/// cache/dhm-official.json. Fail-closed: any failure becomes an error
/// state the UI renders as MISSING with the reason.
final dhmOfficialProvider = FutureProvider.autoDispose<DhmOfficialSnapshot>((ref) async {
  final res = await http.get(Uri.parse('cache/dhm-official.json'));
  if (res.statusCode != 200) {
    throw StateError('snapshot unavailable (HTTP ${res.statusCode})');
  }
  return parseDhmOfficialSnapshot(utf8.decode(res.bodyBytes));
});
