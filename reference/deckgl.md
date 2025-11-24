# Render a Deck.gl visualization

## Usage

``` r
deckgl(
  spec,
  specType = c("auto", "json", "yaml"),
  data = NULL,
  width = NULL,
  height = NULL
)
```

## Arguments

- spec:

  Deck.gl specification as an R list, JSON text, JSON file path, YAML
  text, or YAML file path.

- specType:

  One of "auto" (default), "json", or "yaml". Auto-detection attempts to
  infer the format from the input.

- data:

  Named list of data.frames to register in DuckDB. These tables can be
  referenced in the spec using \`type = "duckdb"\` data nodes.

- width:

  CSS or pixel width (e.g. "100

  heightCSS or pixel height (e.g. "100 An htmlwidget that renders the
  Deck.gl visualization. Creates an interactive deck.gl visualization
  from a JSON or YAML specification. Supports server-side data hydration
  via DuckDB for efficient data handling. if (interactive()) \# Simple
  scatterplot with inline data spec \<- list( \`@type\` = "DeckGL",
  initialViewState = list( longitude = -122.4, latitude = 37.76, zoom =
  12, pitch = 0, bearing = 0 ), layers = list( list( \`@type\` =
  "ScatterplotLayer", id = "scatterplot", data = list( type = "duckdb",
  query = "SELECT lon, lat, radius FROM points" ), getPosition =
  "@=\[lon, lat\]", getRadius = "@=radius", getFillColor = c(255, 0, 0)
  ) ) ) data \<- list( points = data.frame( lon = c(-122.4, -122.45,
  -122.35), lat = c(37.76, 37.78, 37.74), radius = c(100, 150, 200) ) )
  deckgl(spec = spec, data = data)
