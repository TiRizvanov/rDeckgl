# Hexagon Heatmap Example
# This example demonstrates deck.gl's HexagonLayer with remote data

library(rDeckgl)

# Define the hexagon layer spec (sourced from deck.gl website)
hexagon_spec <- list(
  meta = list(
    title = "Hexagon Layer Example",
    description = "The deck.gl website hexagonlayer example",
    websiteUrl = "https://deck.gl/#/examples/core-layers/hexagon-layer"
  ),
  initialViewState = list(
    longitude = -1.4157267858730052,
    latitude = 52.232395363869415,
    zoom = 6.6,
    minZoom = 5,
    maxZoom = 15,
    pitch = 40.5,
    bearing = -27.396674584323023
  ),
  views = list(
    list(
      `@@type` = "MapView",
      controller = TRUE,
      mapStyle = "https://basemaps.cartocdn.com/gl/dark-matter-nolabels-gl-style/style.json"
    )
  ),
  layers = list(
    list(
      `@@type` = "HexagonLayer",
      id = "heatmap",
      data = "https://raw.githubusercontent.com/visgl/deck.gl-data/master/examples/3d-heatmap/heatmap-data.csv",
      coverage = 1,
      pickable = TRUE,
      autoHighlight = TRUE,
      elevationRange = c(0, 3000),
      elevationScale = 50,
      extruded = TRUE,
      getPosition = "@@=[lng,lat]",
      radius = 1000,
      upperPercentile = 100,
      colorRange = list(
        c(1, 152, 189),
        c(73, 227, 206),
        c(216, 254, 181),
        c(254, 237, 177),
        c(254, 173, 84),
        c(209, 55, 78)
      )
    )
  ),
  widgets = list(
    list(`@@type` = "ZoomWidget"),
    list(`@@type` = "CompassWidget")
  )
)

# Render the visualization (no local data needed - uses remote CSV)
deckgl(
  spec = hexagon_spec,
  specType = "json",
  width = "100%",
  height = "600px"
)
