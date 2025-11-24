# Getting Started with rDeckgl

## Introduction

**rDeckgl** provides R bindings for [deck.gl](https://deck.gl) 9.2.2, a
WebGL-powered framework for visualizing large datasets. This vignette
demonstrates the basic usage of rDeckgl with working examples.

## Installation

``` r
# Install from GitHub
remotes::install_github("TiRizvanov/rDeckgl")
```

## Example 1: Basic Scatterplot

This example demonstrates deck.gl rendering performance with ~10,000
points using a viridis color palette:

``` r
library(rDeckgl)
library(scales)

# Generate a spaced-out grid of ~10K points around San Francisco
set.seed(42)
grid_size <- 100L

lon_seq <- seq(-122.515, -122.355, length.out = grid_size)
lat_seq <- seq(37.70, 37.82, length.out = grid_size)
grid <- expand.grid(lon = lon_seq, lat = lat_seq)
grid$value <- rnorm(nrow(grid), mean = 0, sd = 1)

# Add light jitter
jitter_strength <- 0.0007
grid$lon <- grid$lon + runif(nrow(grid), -jitter_strength, jitter_strength)
grid$lat <- grid$lat + runif(nrow(grid), -jitter_strength, jitter_strength)
grid$radius <- runif(nrow(grid), 25, 80)

points_data <- grid

# Map 'value' to viridis color palette
domain_range <- range(points_data$value)
palette_fun <- col_numeric(viridis_pal(option = "B")(256), domain_range)
rgba <- col2rgb(palette_fun(points_data$value))
points_data$color_r <- rgba[1, ]
points_data$color_g <- rgba[2, ]
points_data$color_b <- rgba[3, ]

spec <- list(
  `@@type` = "DeckGL",
  initialViewState = list(
    longitude = mean(range(points_data$lon)),
    latitude = mean(range(points_data$lat)),
    zoom = 11.5,
    pitch = 20,
    bearing = 0
  ),
  tooltip = list(
    html = "<div><strong>Value:</strong> {value}<br/><strong>Radius:</strong> {radius} m</div>",
    style = list(
      backgroundColor = "#0e1119",
      color = "#FFFFFF",
      fontSize = "12px"
    )
  ),
  views = list(
    list(
      `@@type` = "MapView",
      controller = TRUE,
      mapStyle = "https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json"
    )
  ),
  layers = list(
    list(
      `@@type` = "ScatterplotLayer",
      id = "scatterplot",
      data = list(
        type = "duckdb",
        query = "SELECT lon, lat, radius, value, color_r, color_g, color_b FROM points"
      ),
      getPosition = "@@=[lon, lat]",
      getRadius = "@@=radius",
      getFillColor = "@@=[color_r, color_g, color_b, 200]",
      pickable = TRUE,
      autoHighlight = TRUE,
      radiusUnits = "meters"
    )
  )
)

deckgl(
  spec = spec,
  data = list(points = points_data),
  width = "100%",
  height = "600px"
)
```

## Example 2: Hexagon Heatmap

This example uses remote data from the deck.gl website to create a 3D
hexagon heatmap:

``` r
library(rDeckgl)

hexagon_spec <- list(
  initialViewState = list(
    longitude = -1.4157267858730052,
    latitude = 52.232395363869415,
    zoom = 6.6,
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
      elevationRange = c(0, 3000),
      elevationScale = 50,
      extruded = TRUE,
      getPosition = "@@=[lng,lat]",
      radius = 1000,
      colorRange = list(
        c(1, 152, 189),
        c(73, 227, 206),
        c(216, 254, 181),
        c(254, 237, 177),
        c(254, 173, 84),
        c(209, 55, 78)
      )
    )
  )
)

deckgl(
  spec = hexagon_spec,
  width = "100%",
  height = "600px"
)
```

## Example 3: Polygon Layer with Centroids

This example demonstrates rendering polygons with centroids, useful for
spatial data visualization like cell segmentation:

``` r
library(rDeckgl)

# Create synthetic cell polygon data
set.seed(42)
n_cells <- 150

# Generate random cell centroids
cell_centroids <- data.frame(
  cell_ID = sprintf("CELL_%03d", seq_len(n_cells)),
  x = as.integer(runif(n_cells, 0, 10000)),
  y = as.integer(runif(n_cells, -8000, 2000)),
  expression = runif(n_cells, 0.2, 1)
)

# Build hexagon polygons around each centroid
angle_offsets <- seq(0, by = 2 * pi / 6, length.out = 6)
poly_list <- lapply(seq_len(n_cells), function(i) {
  cx <- cell_centroids$x[i]
  cy <- cell_centroids$y[i]
  radius <- runif(1, 120, 260)
  jitter <- runif(6, 0.85, 1.15)
  coords <- data.frame(
    x = as.integer(cx + radius * jitter * cos(angle_offsets)),
    y = as.integer(cy + radius * jitter * sin(angle_offsets))
  )
  coords <- rbind(coords, coords[1, , drop = FALSE])
  c(
    stats::setNames(as.list(coords$x), paste0("p", 0:6, "_x")),
    stats::setNames(as.list(coords$y), paste0("p", 0:6, "_y"))
  )
})

cell_polygons <- data.frame(
  cell_ID = cell_centroids$cell_ID,
  do.call(rbind, poly_list)
)

# DuckDB query to construct polygon coordinates
poly_query <- "SELECT
  cell_ID,
  list_value(
    list_value(p0_x, p0_y),
    list_value(p1_x, p1_y),
    list_value(p2_x, p2_y),
    list_value(p3_x, p3_y),
    list_value(p4_x, p4_y),
    list_value(p5_x, p5_y),
    list_value(p6_x, p6_y)
  ) AS polygon
FROM cell_polygons"

spec <- list(
  initialViewState = list(
    target = c(4895.5, -4035, 0),
    zoom = -1.3,
    minZoom = -10,
    maxZoom = 6
  ),
  views = list(
    list(
      `@@type` = "OrthographicView",
      controller = TRUE,
      flipY = TRUE
    )
  ),
  layers = list(
    # Polygon layer for cell boundaries
    list(
      `@@type` = "PolygonLayer",
      id = "cell-polygons",
      data = list(
        type = "duckdb",
        query = poly_query
      ),
      getPolygon = "@@=polygon",
      positionFormat = "XY",
      filled = TRUE,
      stroked = TRUE,
      getFillColor = c(66, 135, 245, 120),
      getLineColor = c(25, 64, 155, 200),
      lineWidthMinPixels = 1,
      pickable = TRUE,
      coordinateSystem = "@@#COORDINATE_SYSTEM.CARTESIAN",
      coordinateOrigin = c(0, 0, 0)
    ),
    # Scatterplot layer for cell centroids
    list(
      `@@type` = "ScatterplotLayer",
      id = "cell-centroids",
      data = list(
        type = "duckdb",
        query = "SELECT cell_ID, x, y, expression FROM cell_centroids"
      ),
      getPosition = "@@=[x, y]",
      positionFormat = "XY",
      getRadius = "@@=[expression * 120]",
      radiusUnits = "common",
      radiusMinPixels = 1,
      radiusMaxPixels = 3,
      getFillColor = "@@=[50, 205, 50, 200]",
      pickable = TRUE,
      coordinateSystem = "@@#COORDINATE_SYSTEM.CARTESIAN",
      coordinateOrigin = c(0, 0, 0)
    )
  )
)

deckgl(
  spec = spec,
  data = list(
    cell_polygons = cell_polygons,
    cell_centroids = cell_centroids
  ),
  width = "100%",
  height = "600px"
)
```

## Data Hydration with DuckDB

rDeckgl automatically creates an in-memory DuckDB database for efficient
data handling:

1.  Pass a named list of data.frames via the `data` argument
2.  Each entry becomes a DuckDB table
3.  Reference tables using `type = "duckdb"` and SQL queries in your
    spec
4.  Use DuckDB’s powerful SQL features for data transformation

## Shiny Integration

Use rDeckgl in Shiny applications with reactive bindings. Here’s a
complete working example:

``` r
library(shiny)
library(rDeckgl)
library(scales)

ui <- fluidPage(
  titlePanel("Deck.gl in Shiny"),
  deckglOutput("myDeckgl", width = "100%", height = "600px")
)

server <- function(input, output, session) {
  output$myDeckgl <- renderDeckgl({
    # Generate sample data
    set.seed(42)
    n_points <- 500

    points_data <- data.frame(
      lon = runif(n_points, -122.5, -122.3),
      lat = runif(n_points, 37.7, 37.85),
      value = rnorm(n_points),
      radius = runif(n_points, 50, 150)
    )

    # Add colors
    palette_fun <- col_numeric(viridis_pal(option = "B")(256), range(points_data$value))
    rgba <- col2rgb(palette_fun(points_data$value))
    points_data$color_r <- rgba[1, ]
    points_data$color_g <- rgba[2, ]
    points_data$color_b <- rgba[3, ]

    # Create spec
    spec <- list(
      `@@type` = "DeckGL",
      initialViewState = list(
        longitude = -122.4,
        latitude = 37.78,
        zoom = 11,
        pitch = 0,
        bearing = 0
      ),
      views = list(
        list(
          `@@type` = "MapView",
          controller = TRUE,
          mapStyle = "https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json"
        )
      ),
      layers = list(
        list(
          `@@type` = "ScatterplotLayer",
          id = "points",
          data = list(
            type = "duckdb",
            query = "SELECT lon, lat, radius, color_r, color_g, color_b FROM points"
          ),
          getPosition = "@@=[lon, lat]",
          getRadius = "@@=radius",
          getFillColor = "@@=[color_r, color_g, color_b, 180]",
          pickable = TRUE,
          radiusUnits = "meters"
        )
      )
    )

    deckgl(spec = spec, data = list(points = points_data))
  })
}

shinyApp(ui, server)
```

**Note:** This example generates data within the server function. For
reactive/dynamic visualizations, wrap your data generation in
[`reactive()`](https://rdrr.io/pkg/shiny/man/reactive.html) and use
[`observe()`](https://rdrr.io/pkg/shiny/man/observe.html) or
[`observeEvent()`](https://rdrr.io/pkg/shiny/man/observeEvent.html) to
update the visualization based on user input.

## Next Steps

- Explore the `examples/` directory for more advanced use cases:
  - `basic_scatterplot.R` - High-density point visualization
  - `hexagon_heatmap.R` - 3D hexagon aggregation
  - `polygon_layer.R` - Cell segmentation visualization
  - `giotto_geometries.R` - Giotto spatial data integration
  - `giotto_wkb_polygons.R` - WKB polygon rendering
- Read the [deck.gl documentation](https://deck.gl/docs) for all layer
  types
- Check the [rDeckgl GitHub](https://github.com/TiRizvanov/rDeckgl) for
  updates
