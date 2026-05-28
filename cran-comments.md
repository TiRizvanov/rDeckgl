# Submission notes — rDeckgl 0.1.0

## Test environments

* local macOS 15.7.3 (aarch64-apple-darwin20), R 4.5.1 — 0 errors, 0 warnings,
  0 notes (`--as-cran --no-manual`)
* win-builder R-devel (2026-05-27 r90083 ucrt, x86_64-w64-mingw32) — 0 errors,
  0 warnings, 1 NOTE (CRAN incoming feasibility / New submission; spell-check
  on software names — addressed by quoting in DESCRIPTION; invalid file URI
  to LICENSE.md — fixed in README)
* R-hub v2 (Linux, macOS, Windows) — all green
  https://github.com/TiRizvanov/rDeckgl/actions

## R CMD check results

0 errors | 0 warnings | 1 NOTE in the local check.

The NOTE is the standard "CRAN incoming feasibility" — first submission. All
sub-checks (mis-spellings, invalid URI, dead URL) have been addressed in this
version of the tarball.

## Installed size

  > installed size is 8.5Mb
  > sub-directories of 1Mb or more:
  >   htmlwidgets   8.2Mb

The package bundles the pre-built JavaScript that renders deck.gl
visualisations inside an htmlwidget. See "Bundled JavaScript" below.

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
