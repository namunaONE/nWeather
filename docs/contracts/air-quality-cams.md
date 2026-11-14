# Contract: air, dust & UV — schema `nweather/air@1` + thunder line

Status: RECEIPTED (live captures 2026-11-14, receipts/hya-411/). One air
source (CAMS global); thunder is model guidance from the already-pinned
forecast lineup, never presented as lightning detection.

## Air quality — Open-Meteo Air Quality API (receipted)

- Request (Kathmandu probe, receipts/hya-411/aq-cams-global-kathmandu.json):
  `https://air-quality-api.open-meteo.com/v1/air-quality?latitude=27.7172&longitude=85.3240&domains=cams_global&hourly=pm10,pm2_5,carbon_monoxide,nitrogen_dioxide,sulphur_dioxide,ozone,aerosol_optical_depth,dust,uv_index,us_aqi&past_days=1&forecast_days=5`
  -> HTTP 200.
- Grid snap: request 27.7172/85.3240 -> response **27.700005 / 85.30002**
  (CAMS global ~0.4 deg grid, ~45 km). The tile shows the snapped
  coordinates next to the valley-scale banner, never the request coords.
- Elevation (grid cell): 1301.0 m. Timezone: GMT (default); the UI converts
  to NPT (+05:45) itself.
- `hourly` arrays (all receipted): `time` (iso8601, **hourly** steps, GMT,
  NO offset suffix — parse as UTC), `pm10`, `pm2_5`, `carbon_monoxide`,
  `nitrogen_dioxide`, `sulphur_dioxide`, `ozone`, `dust` (ug/m3),
  `aerosol_optical_depth` (dimensionless), `uv_index` (dimensionless),
  `us_aqi` (USAQI scale, integers).
- Window receipted: 144 h = past_days=1 + forecast_days=5
  (2026-11-13T00:00 -> 2026-11-18T23:00 GMT).
- **Trailing nulls are "not yet issued"**: the receipted run stops at
  2026-11-18T13:00 (11 trailing null hours). Rendered as "issued through
  <last non-null hour>", never as 0, never dropped silently.
- CAMS global is natively 3-hourly; Open-Meteo delivers it hourly. The
  `temporal_resolution=hourly_3hourly` parameter is receipted INVALID
  (HTTP 400: Cannot initialize ApiTemporalResolution from invalid String
  value hourly_3hourly) — never sent.
- **European domain receipted dead for Nepal**: `domains=cams_europe` at
  Kathmandu -> HTTP 400 "No data is available for this location". European
  pollen variables are never requested and never shown (HYA-411 issue).
- No official Nepal air-quality station feed exists in v1: this tile is
  MODEL GUIDANCE only, never captioned as a measurement.

## Thunder line — forecast weather codes 95-99 + CAPE (receipted)

- One request per model (same pinned lineup as the compare card):
  `https://api.open-meteo.com/v1/forecast?latitude=27.7172&longitude=85.3240&forecast_days=3&hourly=weathercode,cape&models=<id>`
  -> HTTP 200 for all four (receipts/hya-411/fc-thunder-*.json).
- Each model snaps to its own grid: IFS 27.75/85.25, AIFS 27.75/85.25,
  ICON 27.75/85.375, GFS 27.705826/85.3125. Shown per row, never hidden.
- `cape` unit J/kg; **negative CAPE is a real reading** (stable
  atmosphere) — kept when finite, like the flood rule for dry rivers.
- **`ecmwf_aifs025_single` issues NO CAPE**: receipted all-null array with
  unit literally "undefined". That row shows weathercode-derived thunder
  only and labels CAPE "not issued by this model". Never guessed, never
  substituted from another model.
- Receipted 2026-11-14 window has ZERO weathercodes 95-99 (code sets:
  0/1/2/3/45/51) — the honest default display is "no thunderstorm codes in
  the next 72 h" per model.
- WMO thunder codes counted: 95 (thunderstorm), 96 and 99 (with hail).

## Parse rules (fail-closed)

- Air: non-JSON, `error: true`, missing/non-list `hourly.time`, a
  requested variable missing or non-list, an axis length mismatch, a
  non-numeric value, or an unparseable time -> ArgumentError -> MISSING
  tile. Null VALUES are fine (not-issued hours); null STRUCTURE is not.
- Thunder: per-model fail-SOFT (a dead model is a MISSING row with its
  reason, like the compare card); the tile only dies if the provider itself
  fails.
- Times without an offset are GMT (receipted) — normalized to UTC before
  `DateTime.parse` (Dart would parse them as LOCAL time otherwise); a time
  that still fails throws.

## Honesty rules

- Permanent banner on air: **valley-scale (~45 km), not your ward or
  street**; CAMS global cannot see within-basin gradients.
- US AQI is the US EPA scale computed by Open-Meteo — attributed on the
  tile; Nepal has no receipted national AQI feed in v1, so no "Nepal AQI"
  is ever shown. UV bands are WHO labels; AQI bands are US EPA labels.
- Thunder banner: **not lightning detection, not a DHM warning**; official
  thunder words, when they exist, live only in the DHM strip.
- Freshness: client-stamped fetchedAtUtc; air tile STALE after **30 h**
  (CAMS global runs lag issuance), thunder tile after **24 h** (forecast
  runs update about 6-hourly).
- One air source means no model-spread display on the air tile; the tile
  says so. Thunder shows one row per model, never merged.
