# Sources — feed research (ported from Linear, live-checked 2026-11-04)

Linear stays the tracker ([project P-HYA-15](https://linear.app/hyamuji/project/nweather));
this file is the durable spec. Every claim below was live-checked before it became an
engineering decision. Re-verify before contracts harden (planned HYA-466 institutional
re-verification; HYA-456 is the ongoing feed-drift canary).

## DHM / NMD (official, fail-closed)

- `https://www.dhm.gov.np/home/getAPIData/3` = **335 river + 456 rain stations**
  (the primary gauge source; BIPAD `/river/` and `/rain/` are a mirror).
- `getAPIData/4` = **169 weather stations**.
- Types 2/6/7 return HTTP 500; type 5 returns null; type 1 is stale.
  Only types 3 and 4 are trusted today.
- mfd bulletins are **HTML**, not structured data. Parse fail-closed: never trust a
  pixel, WMS layer or screenshot as a station reading.
- Institutional note (2025-2026 split): meteorology is now the Nepal Meteorological
  Department (dhm.gov.np); hydrology moved to CHWRR under WECS (hydrology.gov.np,
  which blocks automated reads — CI-canary target only).

## BIPAD (official alerts + gauge mirror, no key)

- Base: `https://bipadportal.gov.np/api/v1/`
- `ordering=-id` works; `count` is fake (can be a max-64-bit-int sentinel — ignore it);
  date filters are ignored. Sort by id client-side.
- Flood alerts expire in under an hour — **poll, never day-cache**.
- Known defect: verified alerts with impossible levels exist (alert 46473: 100013.7 m
  vs warning 9.0; Duduwa −9999990). Quality gates must drop sentinel values and
  band-check readings against each station's warning/danger levels.
- `/earthquake/` is **more than a year stale** — do not use. USGS + EMSC instead.

## Earthquakes

- USGS FDSN + EMSC fdsnws-event, Nepal bounding box.
- Match rule: same event if **<=60 s apart and <=30 km apart**; when both report,
  show both magnitudes with attribution.
- NSC has no public API.

## Open-Meteo (model numbers, always attributed + aged)

- No key, non-commercial use; attribution mandatory on every tile.
- Models covering Nepal: `ecmwf_ifs025`, `aifs025`, `icon_global`, `gfs_seamless`
  (+ comparators). **Never average models into one number** — the compare card
  (HYA-407) shows them side by side.
- Flood API = GloFAS v4, 0.05-degree cell: it represents the **largest river in the
  cell**, not a khola, street or official warning level.
- Air quality = CAMS global, ~45 km resolution: valley-scale only. Hide the European
  pollen product.
- ERA5 = climate context only, never a forecast.
- Historical-forecast API (previous runs) powers the model skill scoreboard (HYA-465).

## Post-v1 candidates (researched, not consumed yet)

- NASA POWER (free, no key, MERRA-2): climatology/bias context, ~55 km honesty —
  context, never point forecast.
- ECMWF Open Data (CC-BY-4.0, redistribution allowed): only if Open-Meteo lacks a field.
- ICIMOD SERVIR-HKH streamflow + flash-flood tools: map products, third flood anchor
  for divergence receipts (link-out later).
- Google Flood Forecasting API: waitlist/pilot-only as of Nov 2026 — applied for;
  never ship until a key exists (tracked on HYA-409).
- Citizen science channels (S4W-Nepal, REAMO): labeled community-observation tier,
  partnership-first, never blended into model numbers (planned HYA-467 spike).
