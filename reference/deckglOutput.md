# Shiny output for Deck.gl widget

Use this in the UI to create a placeholder for the Deck.gl
visualization.

## Usage

``` r
deckglOutput(outputId, width = "100%", height = "400px")
```

## Arguments

- outputId:

  output variable name

- width, height:

  CSS dimensions (e.g. '100%', '400px') for the container.

## Value

A Shiny output binding for use in the UI.

## Examples

``` r
if (interactive()) {
  library(shiny)
  library(rDeckgl)

  ui <- fluidPage(
    deckglOutput("myDeckgl", height = "600px")
  )

  server <- function(input, output, session) {
    output$myDeckgl <- renderDeckgl({
      deckgl(spec = my_spec, data = my_data)
    })
  }

  shinyApp(ui, server)
}
```
