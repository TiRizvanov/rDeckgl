# Shiny render function for Deck.gl

Use this in the server to render the Deck.gl visualization to the
output.

## Usage

``` r
renderDeckgl(expr, env = parent.frame(), quoted = FALSE)
```

## Arguments

- expr:

  An expression that generates a call to
  [`deckgl()`](https://tirizvanov.github.io/rDeckgl/reference/deckgl.md).

- env:

  The environment in which to evaluate `expr`.

- quoted:

  Is `expr` a quoted expression (with
  [`quote()`](https://rdrr.io/r/base/substitute.html))? This is useful
  if you want to save an expression in a variable.

## Value

A Shiny render function for use in the server.

## Examples

``` r
if (interactive()) {
  library(shiny)
  library(rDeckgl)

  ui <- fluidPage(
    deckglOutput("myDeckgl")
  )

  server <- function(input, output, session) {
    output$myDeckgl <- renderDeckgl({
      spec <- list(
        `@type` = "DeckGL",
        initialViewState = list(longitude = -122.4, latitude = 37.76, zoom = 12),
        layers = list(
          list(
            `@type` = "ScatterplotLayer",
            id = "points",
            data = list(type = "duckdb", query = "SELECT * FROM points"),
            getPosition = "@=[lon, lat]",
            getRadius = 100,
            getFillColor = c(255, 0, 0)
          )
        )
      )
      deckgl(spec = spec, data = list(points = data.frame(lon = -122.4, lat = 37.76)))
    })
  }

  shinyApp(ui, server)
}
```
