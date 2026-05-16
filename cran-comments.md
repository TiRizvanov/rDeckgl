# Submission notes — rDeckgl 0.1.0

## Test environments

* local macOS 15 (aarch64-apple-darwin20), R 4.5.1 — 0 errors, 0 warnings, 1 NOTE
* (please re-run on win-builder + R-hub before submission)

## R CMD check results

0 errors | 0 warnings | 1 NOTE (new submission)

  > New submission
  > installed size is 8.5Mb
  >   sub-directories of 1Mb or more:
  >     htmlwidgets   8.2Mb

This is the first CRAN submission of rDeckgl. The size NOTE is expected — the
package bundles the pre-built JavaScript that renders deck.gl visualisations
inside an htmlwidget (see below).

## Bundled JavaScript

`inst/htmlwidgets/lib/` contains pre-built JS / WASM dependencies required to
render deck.gl spec specifications without network access:

| Component        | Size  | Purpose                                      |
| ---------------- | ----- | -------------------------------------------- |
| `deckgl/`        | 2.0 M | deck.gl 9.1.15 IIFE bundle + React 18 + CSS  |
| `parquet-wasm/`  | 5.3 M | `parquet_wasm_bg.wasm` (Parquet decoding)    |
| `maplibre/`      | 812 K | MapLibre GL JS 4.0 (base-map provider)       |

These libraries are all MIT-licensed upstream. They are shipped with the
package so that users can render visualisations and decode Parquet data
offline; the htmlwidget falls back to CDN URLs only if the local copies are
unavailable at runtime.

If CRAN prefers a leaner footprint we are happy to externalize
`parquet-wasm/parquet_wasm_bg.wasm` (the largest single file) and load it
exclusively from a CDN at runtime. Please advise.

## URLs

`URL` and `BugReports` in DESCRIPTION reference
`https://github.com/TiRizvanov/rDeckgl`. The repository will be public before
this submission is sent.
