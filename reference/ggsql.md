# Render a ggsql query as a Deck.gl visualization

\`ggsql()\` lets you describe a Deck.gl visualization using the ggsql
dialect (VISUALIZE / DRAW / PLACE / SCALE / LABEL / SETTING) instead of
the native Deck.gl spec. The parser is shared with rMosaic; this entry
point compiles for the Deck.gl rendering path, which is the right choice
for spatial layers (polygons, hex grids, big point clouds, GeoArrow
data).

## Usage

``` r
ggsql(sql, data = NULL, con = NULL, width = NULL, height = NULL, ...)
```

## Arguments

- sql:

  A character scalar containing ggsql.

- data:

  Optional named list of data.frames to register in the widget's DuckDB
  before rendering. Use this when the FROM source in the SQL is not
  already a table the widget's DuckDB can see.

- con:

  Optional DuckDB connection. If supplied it is reused instead of a
  fresh one (mirrors the \`deckgl()\` argument). Useful for GiottoDB /
  dbProject workflows.

- width, height:

  Optional widget dimensions.

- ...:

  Reserved for forward compatibility.

## Value

An htmlwidget produced by \[deckgl()\].

## See also

\[deckgl()\].
