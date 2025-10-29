# Polygon Layer Example
# This example demonstrates rendering polygons with deck.gl using DuckDB queries
# Useful for spatial data visualization (e.g., cell segmentation, geographic regions)

library(rDeckgl)

# Create synthetic cell polygon and centroid data
set.seed(42)
n_cells <- 150

# Generate random cell centroids
cell_centroids <- data.frame(
  cell_ID = sprintf("CELL_%03d", seq_len(n_cells)),
  x = as.integer(runif(n_cells, 0, 10000)),
  y = as.integer(runif(n_cells, -8000, 2000)),
  expression = runif(n_cells, 0.2, 1)
)

# Build hexagon polygons around each centroid with small jitter
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
  # Close the polygon by repeating first vertex
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

# DuckDB query to construct polygon coordinates from separate columns
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

# Define the deck.gl specification
spec <- list(
  meta = list(
    title = "Cell Polygons & Centroids",
    description = "Synthetic segmentation polygons rendered with Deck.gl. Centroids are sized by expression value."
  ),
  initialViewState = list(
    target = c(4895.5, -4035, 0),
    zoom = -1.3,
    minZoom = -10,
    maxZoom = 6,
    rotationX = 0,
    rotationOrbit = 0
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
      autoHighlight = TRUE,
      coordinateSystem = "@@#COORDINATE_SYSTEM.CARTESIAN",
      coordinateOrigin = c(0, 0, 0),
      parameters = list(depthTest = FALSE)
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
      getLineColor = c(16, 78, 139, 255),
      pickable = TRUE,
      autoHighlight = TRUE,
      parameters = list(depthTest = FALSE),
      coordinateSystem = "@@#COORDINATE_SYSTEM.CARTESIAN",
      coordinateOrigin = c(0, 0, 0)
    )
  )
)

# Render the visualization
deckgl(
  spec = spec,
  data = list(
    cell_polygons = cell_polygons,
    cell_centroids = cell_centroids
  ),
  width = "100%",
  height = "600px"
)
