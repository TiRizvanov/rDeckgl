# Giotto Geometries Example - Simplified
# Quick example for visualizing Giotto cell centroids

library(rDeckgl)
library(DBI)
library(duckdb)
library(sf)

# ============================================================================
# Setup
# ============================================================================

db_path <- "giottodb-visium.db"

if (!file.exists(db_path)) {
  stop("Database file not found. Create it with:\n",
       "  library(GiottoDB)\n",
       "  gdb <- as_giottodb(gobject, con, temporary = FALSE)")
}

# ============================================================================
# Extract Cell Centroids
# ============================================================================

# Connect and read geometry data
con <- dbConnect(duckdb(), dbdir = db_path, read_only = TRUE)

# Load spatial extension
try(dbExecute(con, "INSTALL spatial"), silent = TRUE)
try(dbExecute(con, "LOAD spatial"), silent = TRUE)

# Find polygon table
tables <- dbListTables(con)
poly_table <- tables[grepl("poly", tables, ignore.case = TRUE)][1]

if (is.na(poly_table)) {
  stop("No polygon table found in database")
}

print(paste("Using table:", poly_table))

# Read geometries as WKT strings for robust parsing
geom_data <- dbGetQuery(
  con,
  sprintf("SELECT poly_ID, ST_AsText(geom) AS wkt FROM %s", poly_table)
)

# Convert to sf and extract centroids
geom_sf <- st_as_sfc(geom_data$wkt, crs = NA)
centroids_sf <- st_centroid(geom_sf)
centroids_coords <- st_coordinates(centroids_sf)

centroid_data <- data.frame(
  cell_ID = geom_data$poly_ID,
  x = centroids_coords[, "X"],
  y = centroids_coords[, "Y"]
)

dbDisconnect(con, shutdown = TRUE)

print(paste("Extracted", nrow(centroid_data), "cell centroids"))

# ============================================================================
# Visualize with Deck.gl
# ============================================================================

spec <- list(
  `@@type` = "DeckGL",
  initialViewState = list(
    target = c(mean(centroid_data$x), mean(centroid_data$y), 0),
    zoom = -1.3,
    minZoom = -10,
    maxZoom = 6
  ),
  views = list(list(
    `@@type` = "OrthographicView",
    controller = TRUE,
    flipY = TRUE
  )),
  layers = list(
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
      pickable = TRUE,
      autoHighlight = TRUE,
      coordinateSystem = "@@#COORDINATE_SYSTEM.CARTESIAN",
      coordinateOrigin = c(0, 0, 0)
    )
  )
)

deckgl(
  spec = spec,
  data = list(centroids = centroid_data),
  width = "100%",
  height = "600px"
)

# ============================================================================
# For full polygon visualization, see: giotto_wkb_polygons.R
# ============================================================================
