# Contract: earthquake catalogue — schema `nweather/quake@1`

Status: RECEIPTED (live captures 2026-11-14, receipts/hya-410/). Sources are
two independent catalogues; they are never merged into one number.

## Sources (receipted)

- **USGS FDSN** `https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&starttime=<UTC date>&minlatitude=26.0&maxlatitude=30.5&minlongitude=80.0&maxlongitude=88.5&minmagnitude=2.5&orderby=time`
  — HTTP 200, api 2.8.4, 5 features / 30 days, all `status: "reviewed"`.
  Feature: `properties.mag` (num), `magType` (string), `place` (string),
  `time` (epoch **ms**, num), `updated` (epoch ms), `url` (string),
  `title`; `geometry.coordinates` = [lon, lat, depthKm].
- **EMSC** `https://www.seismicportal.eu/fdsnws/event/1/query?format=json&starttime=<UTC date>&minlatitude=26.0&maxlatitude=30.5&minlongitude=80.0&maxlongitude=88.5&orderby=time`
  — HTTP 200, 32 features / 30 days (no magnitude floor in query; RTS
  realtime catalogue, `auth` NDI/EMSC/NSC). Feature: `properties.time`
  (ISO-8601 string), `lat`, `lon`, `depth`, `mag`, `magtype`,
  `flynn_region`, `source_id`, `unid`; `geometry.coordinates` = [lon, lat, depth].
- **BIPAD** `https://bipadportal.gov.np/api/v1/earthquake/` — HTTP 200 but
  receipted **not a live feed**: fake count 9223372036854775807, results are
  historical NSC records (latest rows 2015–2022 era). NOT used in v1;
  HYA-414 re-evaluates.
- **NSC (seismonepal.gov.np)** — national network, no public query API.
  Link-out only. Never scraped.

## Parse rules (fail-closed)

- Non-JSON, wrong `type`, missing/non-list `features`, non-num `mag`,
  non-num coordinates, or an unparseable time → `ArgumentError`; the panel
  shows MISSING for that catalogue. One dead catalogue degrades to
  single-source rows; both dead → MISSING.
- USGS `mag: null` (known USGS possibility) fails closed per event? No:
  a null-mag feature is SKIPPED (kept out of the list), not fatal — the
  receipted 30-day window has none, but a null magnitude cannot be shown
  honestly, and one odd feature must not blank the whole catalogue.
- Times: USGS epoch-ms → UTC; EMSC ISO string → `DateTime.parse` (must be UTC).

## Matching (the disagreement is the product)

- Same quake across catalogues iff `|Δt| ≤ 60 s` AND haversine `≤ 30 km`.
- Greedy nearest match, USGS rows in time order; each EMSC event matches at
  most one USGS event. Unmatched events stay single-source.
- **Both magnitudes are shown, never averaged** (receipted real pair:
  USGS us6000u45b M4.5 mb ↔ EMSC 20261022_0000283 M4.4 ml, Δt ≈ 1.3 s,
  ≈ 19 km).
- Epicentre → place: nearest palika by centroid (nGeo `latHdx/lngHdx`
  official centroid, fallback `lat/lng`), distance shown. It is a
  nearest-centroid approximation, labelled as such — not point-in-polygon,
  and epicentres outside Nepal still get a nearest Nepali palika.

## Honesty rules

- Permanent banner: **not early warning, not a drop-cover-hold trigger;
  magnitudes and locations are revised** by the networks.
- No life-safety wording. No "next quake" predictions, ever.
- Freshness: client-stamped `fetchedAtUtc`; STALE after **12 h** (event
  lists update continuously; they are not a forecast with an issue time).
- NSC link-out rendered verbatim: seismonepal.gov.np.
