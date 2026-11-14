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
  Link-out only. Never scraped. (EMSC rows with `auth: "NSC"` do reach the
  catalogue — receipted 20261025_0000238.)

## Parse rules (fail-closed)

- Non-JSON, wrong `type`, missing/non-list `features`, non-numeric
  coordinates, or an unparseable time → `ArgumentError`; the panel shows
  MISSING for that catalogue. One dead catalogue degrades to single-source
  rows (recorded in the bundle); both dead → MISSING panel.
- A feature with a null magnitude is SKIPPED, never guessed: a
  magnitudeless event cannot be shown honestly, and one odd feature must
  not blank the whole catalogue.
- Times: USGS epoch-ms → UTC; EMSC ISO string → `DateTime.parse` → UTC.

## Matching (the disagreement is the product)

- Same quake across catalogues iff `|Δt| ≤ 60 s` AND haversine `≤ 30 km`.
- Greedy nearest match over USGS rows in time order; each EMSC event
  matches at most one USGS event. Unmatched events stay single-source rows.
- **Both magnitudes are shown, never averaged.** Receipted pairs from the
  2026-11-14 capture: us7000txpk ↔ 20261111_0000303 (Δt 0.07 s, 5.7 km,
  4.6 mb vs 4.6 mb) · us6000u4p1 ↔ 20261024_0000355 (Δt 4.7 s, 3.2 km,
  4.3 mb vs 4.4 m) · us6000u45b ↔ 20261022_0000283 (Δt 1.3 s, 18.8 km,
  4.5 mb vs 4.4 ml) · us6000u4em ↔ 20261016_0000259 (Δt 2.3 s, 18.8 km,
  **4.2 mb vs 3.5 m** — the disagreement case that justifies the rule).
- Receipted rejection: us7000tvzm ↔ 20261025_0000100 is 6.1 s apart but
  **49.2 km** — time alone never matches.
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
