# Data contract — weather compare card (HYA-407)

Pinned before coding, per the anti-slop conventions. Sources of truth, with
receipts:

1. **Open-Meteo OpenAPI spec** — `openapi/forecast.yml` in
   [open-meteo/open-meteo](https://github.com/open-meteo/open-meteo) at commit
   `b485547236a73d528b721f448d5d19a1b6bd15c5`, fetched 2026-11-13. This is the
   API's own machine-readable definition: the `models` query-parameter enum
   and the response schema are receipts, not folklore.
2. **Live docs page** — open-meteo.com/en/docs, re-read 2026-11-13 (model
   discontinuation notices).
3. Live JSON responses cannot be read from this workspace (known limitation) —
   the live receipts that replace the schema-derived fixture below are the job
   of the CI calibration/canary work (HYA-455 golden fixtures, HYA-456 feed
   drift canary). Until then this contract is docs-pinned, and every runtime
   failure is fail-closed per model.

## Endpoint (one request per model — never one blended request)

```
GET https://api.open-meteo.com/v1/forecast
    ?latitude=<lat>&longitude=<lng>
    &daily=temperature_2m_max,temperature_2m_min,precipitation_sum
    &timezone=Asia/Kathmandu
    &forecast_days=5
    &models=<model-id>
```

Why one request per model instead of the multi-model form: the OpenAPI spec
documents only the single-model response schema; per-model key suffixing in
multi-model responses is not pinned by a receipt. Separate requests give each
model an independent contract, independent attribution, and independent
failure (a dead model is one MISSING column, never a broken card).

## Models (columns of the compare card) — ids from the spec enum

| id | label | receipt status 2026-11-13 |
| --- | --- | --- |
| `ecmwf_ifs025` | ECMWF IFS 0.25° | in spec enum; active, covers Nepal |
| `ecmwf_aifs025_single` | ECMWF AIFS 0.25° (single) | in spec enum; active, covers Nepal |
| `icon_seamless` | DWD ICON Seamless | in spec enum. `icon_global` is discontinued 2026-11-30 per the live docs page, and `icon_global_native` is NOT in the spec enum — seamless follows DWD's native successor. |
| `ncep_gfs_seamless` | NCEP GFS Seamless | in spec enum; active, covers Nepal. (`gfs_seamless` is NOT an id.) |

Ids corrected against the spec on 2026-11-13: earlier drafts guessed
`aifs025`, `icon_global_native` and `gfs_seamless` — all three are
absent from the enum and would have 400'd forever as MISSING columns. Model
ids change only with a receipt, never a guess.

## Response schema consumed (single-model request, per the spec)

```json
{
  "latitude": 27.7172, "longitude": 85.324,
  "utc_offset_seconds": 20700,
  "timezone": "Asia/Kathmandu",
  "elevation": 1300.0,
  "daily_units": { "time": "iso8601", "temperature_2m_max": "°C",
                   "temperature_2m_min": "°C", "precipitation_sum": "mm" },
  "daily": {
    "time": ["2026-11-13", "..."],
    "temperature_2m_max": [24.1, "..."],
    "temperature_2m_min": [9.2, "..."],
    "precipitation_sum": [0.0, "..."]
  }
}
```

- Numeric values are typed `num?`: `null` means the model has no value for
  that cell — rendered as `n/a`, never as 0, never interpolated.
- Arrays shorter than `daily.time` yield nulls beyond their end (parser is
  length-tolerant, tested).
- `precipitation_sum` is fetched now (same contract) but displayed by the
  rainfall panel (HYA-408), not the compare card.

## Error schema (fail-closed, per the spec's 400 shape)

```json
{ "error": true, "reason": "..." }
```

Client failure mapping — every path lands in an explicit MISSING state:

| failure | result |
| --- | --- |
| HTTP != 200 | `ModelForecast(error: 'HTTP <code>')` |
| `error: true` payload | `ModelForecast(error: 'API error: <reason>')` |
| unparseable body | `ModelForecast(error: 'unparseable response')` |
| network/timeout throw | `ModelForecast(error: 'fetch failed: ...')` |

## Honesty mapping (docs/methodology.md)

- **source**: `Open-Meteo · <model id>` — the exact model, never a vague "API".
- **age**: `fetched Xm ago` from the client-side `fetchedAt` timestamp;
  card state is FRESH (< 6 h), STALE (>= 6 h), or MISSING (all models failed).
- **tier**: `model guidance` — never captioned as "DHM said", never blended
  with the official strip.
- **never averaged**: the card shows one column per model plus a per-day
  **spread** (max − min of non-missing tMax, bolded at >= 2.0°). There is no
  averaging function anywhere in the codebase; the spread makes disagreement
  visible — that is the product.

## Fixture provenance

`test/fixtures/open_meteo_ifs_sample.json` is **schema-derived** from this
contract (documented response shape), clearly labeled as such inside the file,
and exists to test the parser, not the network. It must be replaced by a
CI-crawled live receipt when HYA-455/456 land — nothing is remembered into a
fixture.
