# Shiny output for Deck.gl widget

## Usage

``` r
deckglOutput(outputId, width = "100%", height = "400px")
```

## Arguments

- outputId:

  output variable name

- width, height:

  CSS dimensions (e.g. '100

A Shiny output binding for use in the UI. Use this in the UI to create a
placeholder for the Deck.gl visualization. if (interactive())
library(shiny) library(rDeckgl) ui \<- fluidPage(
deckglOutput("myDeckgl", width = "100%", height = "600px") ) server \<-
function(input, output, session) output\$myDeckgl \<- renderDeckgl(
deckgl(spec = my_spec, data = my_data) ) shinyApp(ui, server)
