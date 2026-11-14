# Data contract — rainfall ensemble + DHM sentence (HYA-408)

Pinned before coding, per the anti-slop conventions. Source of truth: the
Open-Meteo Ensemble API OpenAPI spec — `openapi/ensemble.yml` in
[open-meteo/open-meteo](https://github.com/open-meteo/open-meteo) at commit
`b485547236a73d528b721f448d5d19a1b6bd15c5`, fetched 2026-11-13. Live JSON
cannot be read from this workspace (known limitation); live receipts that
replace the schema-derived fixture are HYA-455/456 work.

## Endpoint (one request per ensemble model — same pattern as HYA-407)

```
GET https://ensemble-api.open-meteo.com/v1/ensemble
    ?latitude=<lat>&longitude=<lng>
    &daily=precipitation_sum
    &timezone=Asia/Kathmandu
    &forecast_days=5
    &models=<model-id>
```

Receipts from the spec:

- **Different host than the forecast API**: `ensemble-api.open-meteo.com`
  (`servers` block). A wrong host would 404 forever.
- `daily` enum includes `precipitation_sum` (and `rain_sum`,
  `precipitation_hours` — not consumed yet).
- `models` enum (ensemble-specific ids, different from the forecast API):
  `ecmwf_ifs025_ensemble`, `ecmwf_aifs025_ensemble`, `dwd_icon_seamless_eps`,
  `ncep_gefs_seamless`, `cmc_gem_geps`, … — the four Nepal-relevant ones are
  pinned in the table below.
- Response schema: `daily.time` is the day axis; every other `daily` key is
  `additionalProperties: array of number`. The spec does NOT document member
  counts or the member layout — so the contract derives them (next section)
  instead of hardcoding folklore.

## Member layout — derived from the response, never hardcoded

Ensemble values arrive flattened, member-major: for `M` members and `D` days,
`daily.precipitation_sum` has `M × D` entries where entry `m × D + d` is
member `m`, day `d`. Since `M` is not in the schema, the parser:

1. reads `M = raw.length / D`;
2. requires `raw.length % D == 0` and `M >= 1` — otherwise the whole model
   fails closed as MISSING (`'member/days mismatch'`), never a partial guess;
3. treats `null` entries as absent values (n/a — never 0, never interpolated).

## Models (rows of the rainfall card)

| id | label | receipt status 2026-11-13 |
| --- | --- | --- |
| `ecmwf_ifs025_ensemble` | ECMWF EPS | in spec enum; active, covers Nepal |
| `ecmwf_aifs025_ensemble` | ECMWF AIFS EPS | in spec enum; active, covers Nepal |
| `dwd_icon_seamless_eps` | ICON EPS | in spec enum; active, covers Nepal |
| `ncep_gefs_seamless` | GEFS | in spec enum; active, covers Nepal |

## What the card shows — distribution, never a single number

Per model per day, computed only from non-null member values:

- **range**: `min–max mm` across members;
- **agreement**: `k/N members ≥ 10 mm` (threshold constant `rainThresholdMm = 10`).

There is no mean, no median, no single blended number anywhere: the honest
product is the spread and the member count, matching the two-truth rule and
the HYA-407 precedent. A model with no non-null values for a day renders
`n/a`; a failed model renders a MISSING row; the card itself goes MISSING
only when every model fails.

## The DHM sentence zone (official words, fail-closed)

The card carries a dedicated **official words** zone above the ensemble rows.
Its only permitted contents are verbatim official text from a verified DHM
bulletin snapshot. Until the fail-closed CI parser lands (HYA-454) and a
verified snapshot exists (HYA-412), the zone renders its explicit MISSING
state: *"DHM bulletin sentence: MISSING — verified parser not landed yet;
nWeather never paraphrases an official warning without a receipt."* It is
never filled from model output, never summarized, never guessed.

## Error schema (fail-closed, per the spec's 400 shape)

```json
{ "error": true, "reason": "..." }
```

| failure | result |
| --- | --- |
| HTTP != 200 | `EnsembleForecast(error: 'HTTP <code>')` |
| `error: true` payload | `EnsembleForecast(error: 'API error: <reason>')` |
| unparseable body | `EnsembleForecast(error: 'unparseable response')` |
| member/days mismatch | `EnsembleForecast(error: 'member/days mismatch')` |
| network/timeout throw | `EnsembleForecast(error: 'fetch failed: ...')` |

## Honesty mapping (docs/methodology.md)

- **source**: `Open-Meteo Ensemble API · <model ids>`.
- **age**: `fetched Xm ago` from `fetchedAt`; card state FRESH (< 6 h),
  STALE (>= 6 h), MISSING (all models failed).
- **tier**: `ensemble guidance · distribution shown, never one number` —
  never captioned as "DHM said"; the DHM zone is the only official tier here.

## Fixture provenance

`test/fixtures/open_meteo_ensemble_ecmwf.json` is **SCHEMA-DERIVED** (labeled
inside the file): a 2-member × 3-day synthetic body exercising the member
derivation, null gaps, and stats. It tests the parser, not the network;
HYA-455/456 replace it with a CI-crawled live receipt — nothing is remembered
into a fixture.
