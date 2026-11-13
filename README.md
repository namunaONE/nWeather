# nWeather

Nepal-only weather and hazard channel. Free data only — no paid APIs, no key-gated feeds.

nWeather is a Flutter web app (GitHub Pages first, Android later from the same codebase)
built on one principle: **the two-truth model**.

## The two-truth model

nWeather never mixes these, and never averages them:

1. **Official words** — warnings, bulletins and alerts from Nepali authorities
   (Nepal Meteorological Department / DHM, hydrology, BIPAD). These are
   **fail-closed**: if the source is unreachable, stale or fails quality gates,
   we say so or show nothing. We never paraphrase an official warning we cannot verify.
2. **Point numbers** — model guidance (Open-Meteo forecast/ensemble/flood/air-quality,
   USGS + EMSC earthquakes). Always attributed to the exact model, always shown with
   its data age, never captioned as "DHM said".

**Disagreement between the two is the product, not a bug.** We show both, labelled,
and let the reader see where the models and the officials differ.

## What it is not

- No single blended "one number" forecast.
- No opaque sourcing. Every value carries provenance, issued-at/run time, and age.
- No scraped super-app. nWeather is deliberately narrow: weather + hazards + honesty.

## Sibling projects

- [nGeo](https://github.com/namunaONE/nGeo) — places: provinces, districts, palikas,
  coordinates, codes. nWeather's place picker is built on it.
- [nMiti](https://github.com/namunaONE/nMiti) — Bikram Sambat dates and panchang.
  nWeather's BS date header is built on it.

## Architecture in one line

Scheduled GitHub Actions fetch fragile/official sources, run quality gates in CI,
and commit JSON snapshots that GitHub Pages serves same-origin from `/cache/*.json`;
the app calls CORS-enabled APIs (Open-Meteo, USGS, EMSC) directly from the browser.
The pipeline is: **ingest → verify → snapshot → deliver → label**. See
[docs/methodology.md](docs/methodology.md).

## Repo layout

- `docs/` — the durable spec: source research and methodology. Linear
  ([project P-HYA-15](https://linear.app/hyamuji/project/nweather)) stays the tracker;
  this repo carries the knowledge.
- `.github/workflows/` — CI scaffold (analyze / test / build), gate philosophy from day one.

## License

Code is MIT (see [LICENSE](LICENSE)). Third-party CC-BY data is attributed, never
relicensed — see [NOTICE](NOTICE).
