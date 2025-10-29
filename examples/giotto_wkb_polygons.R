# Giotto WKB Polygons Example
# Complete working example for visualizing Giotto geometries with deck.gl

library(rDeckgl)
library(DBI)
library(duckdb)

# ============================================================================
# Prerequisites
# ============================================================================

# This example requires a GiottoDB database file created with GiottoDB::as_giottodb()
# The database file should be in your working directory

db_path <- "giottodb-visium.db"

if (!file.exists(db_path)) {
  stop("Database file '", db_path, "' not found.\n",
       "Please create it using GiottoDB first.")
}

# ============================================================================
# Prepare Data: Extract Coordinates in R
# ============================================================================

# Since rDeckgl creates its own DuckDB connection for the widget,
# we need to prepare the data in R first, then pass it to deckgl()

# Connect to read the geometry data
con <- dbConnect(duckdb(), dbdir = db_path, read_only = TRUE)

# Load spatial extension
tryCatch({
  dbExecute(con, "INSTALL spatial")
  dbExecute(con, "LOAD spatial")
}, error = function(e) {
  message("Spatial extension: ", e$message)
})

# Find the polygon table
tables <- dbListTables(con)
poly_table <- tables[grepl("poly", tables, ignore.case = TRUE)][1]

if (is.na(poly_table)) {
  stop("No polygon table found in database")
}

print(paste("Using polygon table:", poly_table))

# ============================================================================
# Extract Polygon Coordinates using sf package
# ============================================================================

# The most reliable way is to use the sf package to parse the geometries
library(sf)

# Read the geometry data as WKT for robust parsing
geom_data <- dbGetQuery(
  con,
  sprintf("SELECT poly_ID, ST_AsText(geom) AS wkt FROM %s", poly_table)
)

print(paste("Loaded", nrow(geom_data), "polygons"))

# Convert WKT to sf spatial object
geom_sf <- st_as_sfc(geom_data$wkt, crs = NA)

# Extract coordinates as nested lists for deck.gl
coords_list <- lapply(geom_sf, function(poly) {
  coords <- st_coordinates(poly)
  coord_df <- as.data.frame(coords)
  # Group by ring (L2) to handle polygons with holes
  rings <- split(coord_df, coord_df$L2)
  # Convert each ring to list of [x, y] pairs
  lapply(rings, function(ring_df) {
    if (nrow(ring_df) == 0) {
      return(list())
    }
    ring_xy <- ring_df[, c("X", "Y"), drop = FALSE]
    lapply(seq_len(nrow(ring_xy)), function(i) {
      as.numeric(ring_xy[i, ])
    })
  })
})

# For simple polygons (no holes), extract just the outer ring
polygon_coords <- lapply(coords_list, function(rings) {
  if (length(rings) == 0) {
    return(list())
  }
  rings[[1]]  # Take first ring (outer boundary)
})

# Create data frame for deck.gl
polygon_data <- data.frame(
  cell_ID = geom_data$poly_ID,
  stringsAsFactors = FALSE
)
polygon_data$polygon <- polygon_coords

print("Sample polygon structure:")
print(str(polygon_data[1:2, ]))

# ============================================================================
# Extract Centroids
# ============================================================================

# Get centroids for the scatterplot layer
centroids_sf <- st_centroid(geom_sf)
centroids_coords <- st_coordinates(centroids_sf)

centroid_data <- data.frame(
  cell_ID = geom_data$poly_ID,
  x = centroids_coords[, "X"],
  y = centroids_coords[, "Y"],
  stringsAsFactors = FALSE
)

print(paste("Extracted", nrow(centroid_data), "centroids"))

# Disconnect the read connection
dbDisconnect(con, shutdown = TRUE)

# ============================================================================
# Create Deck.gl Specification
# ============================================================================

# Now create the visualization using the extracted data
spec <- list(
  `@@type` = "DeckGL",
  initialViewState = list(
    target = c(mean(centroid_data$x), mean(centroid_data$y), 0),
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
    # Polygon layer
    list(
      `@@type` = "PolygonLayer",
      id = "cell-polygons",
      data = list(
        type = "duckdb",
        query = "SELECT cell_ID, polygon FROM polygons"
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
    # Centroid layer
    list(
      `@@type` = "ScatterplotLayer",
      id = "cell-centroids",
      data = list(
        type = "duckdb",
        query = "SELECT cell_ID, x, y FROM centroids"
      ),
      getPosition = "@@=[x, y]",
      positionFormat = "XY",
      getRadius = 50,
      radiusUnits = "common",
      radiusMinPixels = 2,
      radiusMaxPixels = 5,
      getFillColor = c(50, 205, 50, 200),
      getLineColor = c(16, 78, 139, 255),
      lineWidthMinPixels = 1,
      pickable = TRUE,
      autoHighlight = TRUE,
      coordinateSystem = "@@#COORDINATE_SYSTEM.CARTESIAN",
      coordinateOrigin = c(0, 0, 0),
      parameters = list(depthTest = FALSE)
    )
  )
)

# ============================================================================
# Render Visualization
# ============================================================================

print("Rendering Giotto geometries...")

widget <- deckgl(
  spec = spec,
  data = list(
    polygons = polygon_data,
    centroids = centroid_data
  ),
  width = "100%",
  height = "600px"
)

# Display the widget
widget

# ============================================================================
# Notes
# ============================================================================

# This example demonstrates the complete workflow:
# 1. Read geometries from GiottoDB
# 2. Convert to sf spatial objects
# 3. Extract coordinates in the format deck.gl expects
# 4. Pass data to deckgl() widget
# 5. Visualize both polygons and centroids

# The key insight: rDeckgl creates its own DuckDB connection internally,
# so we prepare the data in R and pass it via the data parameter.
