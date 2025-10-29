# High-Density Scatterplot Example
# Demonstrates deck.gl rendering performance with ~10K points.

library(rDeckgl)
library(scales)

# Generate a spaced-out grid of ~10K points around San Francisco
set.seed(42)
grid_size <- 100L

lon_seq <- seq(-122.515, -122.355, length.out = grid_size)
lat_seq <- seq(37.70, 37.82, length.out = grid_size)
grid <- expand.grid(lon = lon_seq, lat = lat_seq)
grid$value <- rnorm(nrow(grid), mean = 0, sd = 1)

# Add a light jitter so points do not lie perfectly on a grid but still avoid overlap
jitter_strength <- 0.0007
grid$lon <- grid$lon + runif(nrow(grid), -jitter_strength, jitter_strength)
grid$lat <- grid$lat + runif(nrow(grid), -jitter_strength, jitter_strength)
grid$radius <- runif(nrow(grid), 25, 80)

points_data <- grid

# Map 'value' to a viridis colour palette and expose RGBA columns for deck.gl
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
      fontSize = "12px",
      padding = "6px 8px",
      borderRadius = "4px"
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
