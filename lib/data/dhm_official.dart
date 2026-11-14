import 'dart:convert';

/// Official DHM strip — models + fail-closed snapshot parser (HYA-454).
/// Contract: docs/contracts/dhm-official-strip.md.
///
/// The text carried here is verbatim official wording. The parser never
/// rewrites it; it only validates shape and timestamps. Anything that
/// does not match the pinned schema throws — the UI turns that into a
/// visible MISSING state, never stale text presented as current.

const String dhmOfficialSchema = 'nweather/dhm-official@1';

/// DHM 24 h national forecast: analysis + day + night, bilingual.
class DhmForecast24 {
  const DhmForecast24({
    required this.id,
    required this.issuedAt,
    required this.analysisNe,
    required this.analysisEn,
    required this.dayNe,
    required this.dayEn,
    required this.nightNe,
    required this.nightEn,
  });

  final String id;
  final DateTime issuedAt; // UTC
  final String analysisNe;
  final String analysisEn;
  final String dayNe;
  final String dayEn;
  final String nightNe;
  final String nightEn;
}

/// The latest multi-day bulletin (three-days-forecast-latest row 0).
/// [title] is the DHM sentence, verbatim, including issue time.
class DhmBulletin {
  const DhmBulletin({
    required this.id,
    required this.issuedAt,
    required this.title,
    this.url,
  });

  final String id;
  final DateTime issuedAt; // UTC
  final String title;
  final String? url;
}

/// One CI-produced snapshot (cache/dhm-official.json).
class DhmOfficialSnapshot {
  const DhmOfficialSnapshot({
    required this.schema,
    required this.fetchedAt,
    this.forecast24,
    this.bulletin,
  });

  final String schema;
  final DateTime fetchedAt; // UTC — when CI read DHM
  final DhmForecast24? forecast24;
  final DhmBulletin? bulletin;
}

DateTime _parseUtc(String raw, String what) {
  final t = DateTime.tryParse(raw);
  if (t == null) {
    throw ArgumentError('dhm-official: $what is not an ISO timestamp: "$raw"');
  }
  return t.toUtc();
}

String _reqText(dynamic v, String what) {
  final s = (v ?? '').toString().trim();
  if (s.isEmpty) throw ArgumentError('dhm-official: $what is empty');
  return s;
}

/// Parses the CI snapshot. Fail-closed: unknown schema version, missing
/// fetchedAt, or an incomplete section throws ArgumentError.
DhmOfficialSnapshot parseDhmOfficialSnapshot(String raw) {
  final dynamic doc = jsonDecode(raw);
  if (doc is! Map<String, dynamic>) {
    throw ArgumentError('dhm-official: snapshot is not a JSON object');
  }
  final schema = (doc['schema'] ?? '').toString();
  if (schema != dhmOfficialSchema) {
    throw ArgumentError('dhm-official: unknown schema "$schema", expected "$dhmOfficialSchema"');
  }
  final fetchedAt = _parseUtc(_reqText(doc['fetchedAt'], 'fetchedAt'), 'fetchedAt');

  DhmForecast24? forecast24;
  final dynamic f = doc['forecast24'];
  if (f != null) {
    if (f is! Map<String, dynamic>) {
      throw ArgumentError('dhm-official: forecast24 is not an object');
    }
    forecast24 = DhmForecast24(
      id: _reqText(f['id'], 'forecast24.id'),
      issuedAt: _parseUtc(_reqText(f['issuedAt'], 'forecast24.issuedAt'), 'forecast24.issuedAt'),
      analysisNe: _reqText(f['analysisNe'], 'forecast24.analysisNe'),
      analysisEn: _reqText(f['analysisEn'], 'forecast24.analysisEn'),
      dayNe: _reqText(f['dayNe'], 'forecast24.dayNe'),
      dayEn: _reqText(f['dayEn'], 'forecast24.dayEn'),
      nightNe: _reqText(f['nightNe'], 'forecast24.nightNe'),
      nightEn: _reqText(f['nightEn'], 'forecast24.nightEn'),
    );
  }

  DhmBulletin? bulletin;
  final dynamic b = doc['bulletin'];
  if (b != null) {
    if (b is! Map<String, dynamic>) {
      throw ArgumentError('dhm-official: bulletin is not an object');
    }
    bulletin = DhmBulletin(
      id: _reqText(b['id'], 'bulletin.id'),
      issuedAt: _parseUtc(_reqText(b['issuedAt'], 'bulletin.issuedAt'), 'bulletin.issuedAt'),
      title: _reqText(b['title'], 'bulletin.title'),
      url: (b['url'] ?? '').toString().trim().isEmpty ? null : b['url'].toString(),
    );
  }

  return DhmOfficialSnapshot(schema: schema, fetchedAt: fetchedAt, forecast24: forecast24, bulletin: bulletin);
}

/// Splits text into sentences across both scripts: Nepali danda (।)
/// and the Latin full stop followed by whitespace.
List<String> splitSentences(String text) {
  final parts = text.split(RegExp(r'(?<=[।.])\s+'));
  return [
    for (final p in parts)
      if (p.trim().isNotEmpty) p.trim(),
  ];
}

/// Province name aliases (English spellings + Devanagari) for matching
/// DHM sentences. Matching is honest: it only marks, never hides.
const Map<String, List<String>> _provinceAliases = {
  'Koshi': ['koshi', 'कोशी'],
  'Madhesh': ['madhesh', 'madhes', 'मधेश'],
  'Bagmati': ['bagmati', 'बागमती'],
  'Gandaki': ['gandaki', 'गण्डकी'],
  'Lumbini': ['lumbini', 'लुम्बिनी'],
  'Karnali': ['karnali', 'कर्णाली'],
  'Sudurpashchim': ['sudurpashchim', 'sudurpaschim', 'sudur paschim', 'सुदूरपश्चिम'],
};

String _fold(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\-]'), '');

/// Whether [text] mentions the province named [provinceName] (an nGeo
/// provinceName, e.g. "Bagmati"). Unknown provinces match nothing.
bool mentionsProvince(String text, String provinceName) {
  final aliases = _provinceAliases[provinceName];
  if (aliases == null) return false;
  final folded = _fold(text);
  for (final a in aliases) {
    if (RegExp(r"[ऀ-ॿ]").hasMatch(a)) {
      if (text.contains(a)) return true;
    } else if (folded.contains(_fold(a))) {
      return true;
    }
  }
  return false;
}

/// Formats a UTC instant in Nepal time (NPT, +05:45) for issued-at stamps.
String nptStamp(DateTime utc) {
  final npt = utc.toUtc().add(const Duration(hours: 5, minutes: 45));
  String p2(int v) => v.toString().padLeft(2, '0');
  return '${npt.year}-${p2(npt.month)}-${p2(npt.day)} ${p2(npt.hour)}:${p2(npt.minute)} NPT';
}

/// Staleness budget for official text: issued > 30 h is STALE (DHM
/// issues the 24 h forecast twice daily; warnings are ad hoc).
bool isStaleOfficial(DateTime issuedAtUtc, DateTime nowUtc) =>
    nowUtc.toUtc().difference(issuedAtUtc.toUtc()) > const Duration(hours: 30);
