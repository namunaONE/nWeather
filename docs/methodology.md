# Methodology — the honesty contract

The quality contract, one line: **a number you can trace, in your palika, in your
language, with an honest age, that tells you what to do — or honestly says nothing.**

## The pipeline (five stages — nWeather computes no weather)

1. **Ingest** — scheduled GitHub Actions fetchers pull fragile/official sources
   (DHM mfd bulletin HTML, DHM getAPIData 3/4, BIPAD /alert /rain /river).
   Raw payloads are archived under `receipts/raw/`.
2. **Verify** — sentinel/band/jump/chain/freshness gates run in CI.
   A gate failure means a red run plus an alert issue — never a silently bad snapshot.
3. **Snapshot** — normalized JSON is committed to `/cache/`; git history is the audit
   log; GitHub Pages serves it same-origin.
4. **Deliver** — snapshot-first for official/fragile sources; direct from the browser
   for CORS-enabled APIs (Open-Meteo, USGS, EMSC). UI states are FRESH / STALE /
   MISSING and fail-closed.
5. **Label** — every value travels with: source, issued-at/run time, data age,
   evidence tier.

## Two-truth rules

- Official words are fail-closed: unreachable, stale or gate-failed = say so or show nothing.
- Model numbers are always attributed to the exact model and always aged.
- Never average models into one number; never caption a model value as "DHM said".
- Disagreement between sources is displayed, not smoothed away.

## Quality gates are golden fixtures, not prose

The nMiti lesson, carried over: nothing is remembered into a fixture. Fixtures are
built from freshly verified source data only, and tests assert receipts
(fixture-backed, no assertion-less tests). Lint/analyzer roll out
warnings → errors → CI gate.

## Benchmark loop

Crawled source receipts vs generated snapshots (HYA-459, `nweather-receipts/1` schema).
Three classes: parser fidelity (independent second parser — never import the pipeline
parser), cross-source divergence (gauge vs GloFAS, USGS vs EMSC), temporal drift.
**Comparator scope: DHM + BIPAD only.**

## Honesty limits we state up front

- GloFAS cell != the khola next to you.
- CAMS ~45 km = valley-scale, not your street.
- Everything was verified in the dry season (Nov 2026); the monsoon-window
  verification (HYA-457) gates v1 trust.
- BIPAD flood alerts expire <1 h and must be polled, not day-cached.

## Merge & ship rules (from nMiti)

- Merge to main is a user-approval gate, never automatic, even with CI green.
- Verify CI + live deploy after every push/merge.
- Small PRs; contract-first per panel: pin data contracts from live receipts before coding.
