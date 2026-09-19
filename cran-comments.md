# Submission notes — rDeckgl 0.2.0

## Changes since 0.1.0

* Query results declared with `format = "arrow"` can be exported by DuckDB
  itself as an Arrow (or Parquet) file that ships with the widget as an html
  dependency attachment and is bound to deck.gl layers as binary attributes,
  so rows are no longer materialised in R (new arguments `data_transport` and
  `data_dir`).
* Faster JSON row export, multi-batch Polygon2D support and robustness fixes;
  see NEWS.md.

## Test environments

* local macOS 15.7.9 (aarch64-apple-darwin20), R 4.5.1 — 0 errors, 0 warnings,
  1 NOTE (`R CMD check --as-cran`)

## R CMD check results

0 errors | 0 warnings | 1 NOTE

The NOTE is local only: "Skipping checking HTML validation: 'tidy' doesn't look
like recent enough HTML Tidy".

There are no reverse dependencies on CRAN.

## Installed size

  > installed size is 8.6Mb
  > sub-directories of 1Mb or more:
  >   htmlwidgets   8.2Mb

The package bundles the pre-built JavaScript that renders deck.gl
visualisations inside an htmlwidget; the bundled libraries are unchanged since
0.1.0. See "Bundled JavaScript" below.

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
