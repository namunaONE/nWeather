# Contract — flood panel (HYA-409): GloFAS discharge + official bulletin

Schema: `nweather/flood@1` (client-side parse of the Open-Meteo Flood API response).
Pinned to live receipt `receipts/hya-409/flood-default-karnali.json`
(captured 2026-11-14, HTTP 200; verbatim fixture `test/fixtures/flood/glofas_karnali.json`).

## Model layer — Open-Meteo Flood API (browser-direct)

    GET https://flood-api.open-meteo.com/v1/flood
        ?latitude={lat}&longitude={lng}
        &daily=river_discharge,river_discharge_mean,river_discharge_median,
               river_discharge_min,river_discharge_max,river_discharge_p25,river_discharge_p75

Receipted behavior (2026-11-14, Karnali cell):

- The response reports the SNAPPED cell center: request 28.60/81.20 answered
  `latitude: 28.575005, longitude: 81.17502`. The UI shows the snapped cell,
  never the requested point.
- `daily.time` = 91 days (2026-11-14 … 2027-02-13); all values m³/s.
- `model=forecast_v4` and `model=seamless_v4` are accepted (HTTP 200) but
  return `river_discharge` only. The default request returns all seven
  statistics, so nWeather pins the default (no model param).
- The payload carries no issued-at: the client stamps `fetchedAt` at download;
  staleness budget 30 h (GloFAS refreshes several times a day).

## Fail-closed parse (`nweather/flood@1`)

- Non-200, non-JSON body, missing `daily` block, missing arrays, unequal array
  lengths, missing snapped coordinates, or a non-numeric entry → `ArgumentError`;
  the UI shows MISSING with the reason. Never a partial panel.
- Values ≤ 0 are kept (dry-season discharge is genuinely tiny, e.g. 0.06 m³/s),
  but must be finite numbers.

## Honesty rules (UI)

- The value is the largest river in a 0.05° cell — not a khola, not a street,
  not an official warning level. A small coordinate nudge can select a
  different channel.
- Show the distribution (median + min–max + p25–p75) per day, never one number,
  never a "flood risk %", never averaged across days or models.
- The official layer is separate and verbatim-only; the two layers are never
  merged into one verdict.
- No inundation map in v1. No life-safety wording.

## Official layer — hydrology.gov.np (CHWRR) — receipted as NOT machine-readable yet

- Receipt 2026-11-14: `GET /` → HTTP 200 but the body is a 1.5 KB React SPA
  shell (no flood/bulletin links in the HTML; content lives in
  `/static/js/main.6853daa2.js`). `GET /flood-forecasting` → 404.
- Bundle grep (round 2, same branch, `receipts/hya-409/hydrology-bundle-*.txt`)
  hunts for the bulletin route; until a bulletin URL is receipted (or HYA-466
  re-verifies), the official zone renders fail-closed MISSING with that reason.
- Per the issue: fail closed when the bulletin cannot be read, including when
  the 24-hour service is suspended. Never paraphrase an official warning
  without a receipt.
