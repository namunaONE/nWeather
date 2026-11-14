# For developers — building on nWeather

nWeather is free and open on purpose: MIT code, attributed data, and reusable
siblings. This page is how other developers plug in.

## Reuse our building blocks directly

You don't need nWeather the app to use its foundations — both are standalone:

- **nGeo** (`nepal_admin_api` on GitHub
  [namunaONE/nGeo](https://github.com/namunaONE/nGeo)) — offline administrative
  divisions of Nepal: 7 provinces, 77 districts, 753 local bodies, 6,743 wards,
  bilingual names, CBS codes with evidence tiers, official HDX centroids,
  boundaries. Pure Dart, data ships in the box.
- **nMiti** ([namunaONE/nMiti](https://github.com/namunaONE/nMiti)) — verified
  Bikram Sambat conversion (BS 1975-2100: verified core + labeled projection
  tail), evidence-tagged, fail-closed outside the table.

In `pubspec.yaml`:

```yaml
dependencies:
  nepal_admin_api:
    git:
      url: https://github.com/namunaONE/nGeo.git
      ref: main
  nepali_date:
    git:
      url: https://github.com/namunaONE/nMiti.git
      path: packages/nepali_date
      ref: main
  nepali_date_data:
    git:
      url: https://github.com/namunaONE/nMiti.git
      path: packages/nepali_date_data
      ref: main
```

## The open snapshot API (planned — HYA-462)

Once the cache pipeline (HYA-412) is live, every verified snapshot the app
consumes will also be served at `https://namunaone.github.io/nWeather/cache/*.json`
— versioned, documented, and intentional. Design rules, fixed now:

- Every snapshot carries honesty fields: `source`, `issuedAt`/`runTime`,
  `dataAge`, `evidenceTier`. A snapshot without them is a bug.
- Official-source snapshots are verbatim (measurements or official text) with
  provenance — never our forecast, never blended.
- A snapshot that failed its quality gate is dropped, not published. Fail-closed.
- until HYA-412 ships, `/cache/` does not exist yet. Don't build against it
  before it's announced here.

## Attribution rules for anything you build from nWeather

- Open-Meteo-derived values: CC-BY-4.0 attribution is mandatory, non-commercial
  use only. Model values must stay attributed to the exact model — never
  captioned as an official (DHM/BIPAD) statement.
- USGS: public domain. EMSC: attribution required.
- Nepali official sources (NMD/DHM, CHWRR hydrology, BIPAD): government
  publications — keep them verbatim, provenance attached, fail-closed.
- nGeo data fields: see nGeo's NOTICE (CC-BY-4.0 / CC BY-IGO / MIT mix) —
  never relicense.

## Conventions if you contribute here

- Two-truth model is non-negotiable: official words fail-closed, model numbers
  attributed + aged, never averaged, never cross-captioned.
- Contract-first per panel: pin the data contract from live receipts before
  coding; hallucinated fields die at compile time.
- Tests assert receipts (fixture-backed, no assertion-less tests); fixtures are
  built from freshly verified source data only — nothing is "remembered into"
  a fixture.
- Lint/analyzer warnings are errors in CI.
- Small PRs; merge to main is a maintainer-approval gate even with CI green.
- Research lives in `docs/`, not only in Linear.
