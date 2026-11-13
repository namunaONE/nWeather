# Data contract — weather compare card (HYA-407)

Pinned before coding, per the anti-slop conventions. Source of truth: the
Open-Meteo Forecast API docs (open-meteo.com/en/docs, re-read 2026-11-13) and
the live-checked model list from the Linear project description (2026-11-04).
Live JSON responses cannot be read from this workspace (known limitation) —
the live receipt that replaces the schema-derived fixture below is the job of
the CI calibration/canary work (HYA-455 golden fixtures, HYA-456 feed drift
canary). Until then, this contract is docs-pinned, and every runtime failure
is fail-closed per model.

## Endpoint (one request per model — never one blended request)

```
GET https://api.open-meteo.com/v1/forecast
    ?latitude=<lat>&longitude=<lng>
    &daily=temperature_2m_max,temperature_2m_min,precipitation_sum
    &timezone=Asia/Kathmandu
    &forecast_days=5
    &models=<model-id>
```

Why one request per model instead of the multi-model form: per-model keys in
multi-model responses are suffixed and the suffix behavior is not pinned by a
live receipt yet. Separate requests give each model an independent contract,
independent attribution, and independent failure (a dead model is one MISSING
column, never a broken card).

## Models (columns of the compare card)

| id | label | status 2026-11-13 |
| --- | --- | --- |
| `ecmwf_ifs025` | ECMWF IFS 0.25° | active, covers Nepal |
| `aifs025` | ECMWF AIFS 0.25° (single) | active, covers Nepal |
| `icon_global_native` | DWD ICON Global Native | candidate — **`icon_global` is discontinued 2026-11-30** per the live docs page; the native replacement id must be confirmed by a live CI receipt (HYA-456) before it is trusted. Until then this column may show MISSING, which is acceptable and honest. |
| `gfs_seamless` | NCEP GFS Seamless | active, covers Nepal |

A model id that turns out to be invalid yields the API error payload below,
which the client converts to a MISSING column. No model is ever silently
dropped or silently averaged away.

## Response schema consumed (single-model request)

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
- `precipitation_sum` is fetched now (same contract) but displayed by the
  rainfall panel (HYA-408), not the compare card.

## Error schema (fail-closed)

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
  **spread** (max − min of non-missing tMax). There is no averaging function
  anywhere in the codebase; the spread makes disagreement visible — that is
  the product.

## Fixture provenance

`test/fixtures/open_meteo_ifs_sample.json` is **schema-derived** from this
contract (documented response shape), clearly labeled as such, and exists to
test the parser, not the network. It must be replaced by a CI-crawled live
receipt when HYA-455/456 land — nothing is remembered into a fixture.
