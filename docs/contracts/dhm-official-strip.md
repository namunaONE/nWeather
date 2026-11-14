# Contract — Official DHM strip (HYA-454)

Pinned 2026-11-14 from live receipts. The DHM MFD site (dhm.gov.np/mfd) is
now a JavaScript SPA; its bulletins are served by a no-login JSON API under
`https://dhm.gov.np/mfd/api/`. We parse the API, never the SPA HTML — the
parser lives in CI (tool/fetch_dhm.dart), not on-device, per the
cache-architecture decision (HYA-453/HYA-412).

## Receipted endpoints (live-verified 2026-11-14)

- `GET /mfd/api/country-forecast` — 24 h national forecast, bilingual.
  Live receipt: id `1474`, `issue_date: 2026-11-13T12:15:00.000Z`,
  fields `analysis_np`, `analysis_en`, `np_text_1`, `en_text_1` (day),
  `np_text_2`, `en_text_2` (night). Timestamps are UTC ISO.
- `GET /mfd/api/three-days-forecast-latest` — array of bulletin rows,
  newest first. Live receipt: row id `1663`, Nepali title carries the BS
  date range and issue time verbatim, `images[]` are relative map paths.
  (The endpoint name says three days; DHM titles currently say five —
  we show the title verbatim, never paraphrased.)
- Also known (receipted from independent consumers gati-alerts and
  lacspace/datacards, not used in v1): `/mfd/api/page/tag?tag_id=8`
  (warning pages) + `/mfd/api/page/{id}`, `/mfd/api/weather`,
  `/mfd/api/manual-observation`, `/mfd/api/forecast?lat&lng`.

## Snapshot schema `nweather/dhm-official@1` (cache/dhm-official.json)

```json
{
  "schema": "nweather/dhm-official@1",
  "source": "DHM Meteorological Forecasting Division (dhm.gov.np/mfd)",
  "sourceUrl": "https://dhm.gov.np/mfd/#/weather/country",
  "evidenceTier": "official — verbatim, never paraphrased",
  "fetchedAt": "<UTC ISO — when CI read DHM>",
  "forecast24": {
    "id": "<DHM id>", "issuedAt": "<UTC ISO>",
    "analysisNe": "", "analysisEn": "",
    "dayNe": "", "dayEn": "", "nightNe": "", "nightEn": ""
  },
  "bulletin": { "id": "", "issuedAt": "", "title": "", "url": "" } | null
}
```

## Gates (CI, tool/fetch_dhm.dart)

- HTTP 200 from both endpoints; JSON shape as receipted.
- `forecast24` REQUIRED: id non-empty, issue_date parses, and all six
  text fields non-empty after whitespace trimming. Any miss = red run,
  no snapshot written (previous snapshot stays).
- `bulletin` OPTIONAL: unreadable or malformed → `null` + warning line;
  the app shows its own MISSING state for that section.
- Staleness budget: issued > 30 h → UI shows STALE (never silently old).

## UI rules (lib/ui/official_strip.dart)

- Verbatim text in both languages, never rewritten, never summarized.
- Issued-at stamp in Nepal time (NPT, +05:45) on the strip and the bulletin.
- Sentences mentioning the selected province are highlighted; the full
  text always stays visible (highlighting never hides).
- Fail-closed: unreadable snapshot → visible MISSING state with the reason,
  never stale text presented as current.
- Provenance footer via PanelFrame: source · age · tier.

## Fixtures

`test/fixtures/dhm/*.json` are verbatim live receipts (whitespace-rejoined
where the reading proxy hard-wrapped a line). Tests assert the parser
against them; drift breaks CI (HYA-456 canary generalizes this).
