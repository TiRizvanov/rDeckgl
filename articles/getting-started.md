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

## GeoArrow examples

The following self-contained scripts mirror our internal GeoArrow tests.
Copy them into your own session—no local `Examples/` folder required.

### GeoArrow scatterplot (points)

``` r
library(rDeckgl)

set.seed(42)
n_points <- 1000

points_data <- data.frame(
  id = 1:n_points,
  lon = runif(n_points, -122.5, -122.3),
  lat = runif(n_points, 37.7, 37.85),
  value = rnorm(n_points, mean = 0.5, sd = 0.3),
  radius = runif(n_points, 50, 200)
)

points_data$value <- pmax(0, pmin(1, points_data$value))

spec <- list(
  `@@type` = "DeckGL",
  initialViewState = list(
    longitude = -122.4,
    latitude = 37.78,
    zoom = 12,
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
        query = "SELECT id, lon, lat, value, radius FROM points_data"
      ),
      getPosition = "@@=[lon, lat]",
      getRadius = "@@=radius",
      getFillColor = "@@=[value * 255, (1 - value) * 255, 100, 200]",
      radiusUnits = "meters",
      pickable = TRUE,
      autoHighlight = TRUE
    )
  )
)

deckgl(
  spec = spec,
  data = list(points_data = points_data),
  width = "100%",
  height = "600px"
)
```

### Simple GeoArrow polygons

``` r
library(rDeckgl)

con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")

DBI::dbExecute(con, "INSTALL spatial")
DBI::dbExecute(con, "LOAD spatial")

DBI::dbExecute(con, "INSTALL nanoarrow FROM community")
DBI::dbExecute(con, "LOAD nanoarrow")

DBI::dbExecute(con, "CALL register_geoarrow_extensions()")

set.seed(42)
n_polygons <- 50

polygons_data <- data.frame(
  id = 1:n_polygons,
  center_x = runif(n_polygons, -122.5, -122.3),
  center_y = runif(n_polygons, 37.7, 37.85),
  size = runif(n_polygons, 0.005, 0.015),
  value = runif(n_polygons, 0, 1)
)

polygons_data$wkt <- apply(polygons_data, 1, function(row) {
  cx <- as.numeric(row["center_x"])
  cy <- as.numeric(row["center_y"])
  s <- as.numeric(row["size"])
  sprintf(
    "POLYGON((%f %f, %f %f, %f %f, %f %f, %f %f))",
    cx - s, cy - s,
    cx + s, cy - s,
    cx + s, cy + s,
    cx - s, cy + s,
    cx - s, cy - s
  )
})

DBI::dbWriteTable(con, "polygon_data", polygons_data, overwrite = TRUE)

DBI::dbExecute(con, "
  CREATE TABLE polygons_geoarrow AS
  SELECT
    id,
    'Polygon ' || id AS name,
    value,
    ST_GeomFromText(wkt) AS geometry
  FROM polygon_data
")

spec <- list(
  `@@type` = "DeckGL",
  initialViewState = list(
    longitude = -122.4,
    latitude = 37.78,
    zoom = 11,
    pitch = 45,
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
      `@@type` = "GeoArrowSolidPolygonLayer",
      id = "geoarrow-polygons",
      data = list(
        type = "duckdb",
        query = "SELECT id, name, value, geometry FROM polygons_geoarrow",
        format = "geoarrow"
      ),
      getFillColor = "@@=[value * 255, (1 - value) * 200, 100, 180]",
      getElevation = "@@=value * 1000",
      extruded = TRUE,
      pickable = TRUE
    )
  )
)

widget <- deckgl(
  spec = spec,
  con = con,
  width = "100%",
  height = "600px"
)

DBI::dbDisconnect(con)

widget
```

### Utah building footprints (GeoArrow)

This script renders the Utah portion of the [Microsoft
USBuildingFootprints](https://github.com/microsoft/USBuildingFootprints)
dataset as GeoArrow polygons. Create a GeoParquet with GeoArrow-encoded
geometries from the upstream ZIP:

``` bash
ogr2ogr \
  Utah.parquet \
  /vsizip/Utah.geojson.zip \
  -dialect SQLite \
  -sql "SELECT geometry FROM 'Utah.geojson'" \
  -lco COMPRESSION=BROTLI \
  -lco GEOMETRY_ENCODING=GEOARROW \
  -lco POLYGON_ORIENTATION=COUNTERCLOCKWISE \
  -lco ROW_GROUP_SIZE=9999999
```

``` r
library(rDeckgl)
library(arrow)

cat("╔═══════════════════════════════════════════════════════════════╗\n")
cat("║  Working GeoArrow Example (up to 50k buildings)              ║\n")
cat("╚═══════════════════════════════════════════════════════════════╝\n\n")

parquet_path <- "Utah.parquet"

if (!file.exists(parquet_path)) {
  stop("❌ Parquet file not found: ", parquet_path)
}

cat("📦 Reading Parquet file...\n")

parquet_data <- arrow::read_parquet(parquet_path)
cat("   Total rows in file:", nrow(parquet_data), "\n")

max_rows <- 1000000
if (nrow(parquet_data) > max_rows) {
  cat("   Sampling", max_rows, "rows (use URL-loading for full dataset)\n")
  sample_data <- head(parquet_data, max_rows)
} else {
  sample_data <- parquet_data
}

cat("✅ Using", nrow(sample_data), "buildings\n\n")

cat("📍 Computing density center...\n")
bbox_data <- sample_data$GEOMETRY_bbox
if (!is.null(bbox_data)) {
  xmin <- as.numeric(bbox_data$xmin)
  xmax <- as.numeric(bbox_data$xmax)
  ymin <- as.numeric(bbox_data$ymin)
  ymax <- as.numeric(bbox_data$ymax)

  cx <- (xmin + xmax) / 2
  cy <- (ymin + ymax) / 2

  grid_size <- 0.1
  grid_x <- floor(cx / grid_size)
  grid_y <- floor(cy / grid_size)
  grid_key <- paste(grid_x, grid_y, sep = ",")

  grid_counts <- table(grid_key)
  densest_cell <- names(which.max(grid_counts))
  densest_count <- max(grid_counts)
  densest_indices <- which(grid_key == densest_cell)

  center_lon <- mean(cx[densest_indices], na.rm = TRUE)
  center_lat <- mean(cy[densest_indices], na.rm = TRUE)

  cat("   Found densest area with", densest_count, "buildings\n")
  cat("   Center: [", round(center_lon, 4), ", ", round(center_lat, 4), "]\n\n", sep = "")
} else {
  center_lon <- -110.4144
  center_lat <- 39.4991
  cat("   Using default center (no bbox data)\n\n")
}

cat("🔧 Converting to Arrow IPC...\n")

arrow_table <- arrow::arrow_table(sample_data)
temp_file <- tempfile(fileext = ".arrows")
arrow::write_ipc_stream(arrow_table, temp_file)
arrow_bytes <- readBin(temp_file, "raw", n = file.info(temp_file)$size)
unlink(temp_file)
arrow_b64 <- base64enc::base64encode(arrow_bytes)

size_mb <- length(arrow_bytes) / 1024 / 1024
cat("✅ Encoded", round(size_mb, 1), "MB\n")
if (size_mb > 50) {
  warning("⚠️  Data > 50MB may cause browser issues!")
}
cat("\n")

cat("🎨 Creating deck.gl spec centered at [", round(center_lon, 4), ", ", round(center_lat, 4), "]...\n", sep = "")

spec <- list(
  `@@type` = "DeckGL",
  width = 1024,
  height = 768,
  initialViewState = list(
    longitude = center_lon,
    latitude = center_lat,
    zoom = 12,
    pitch = 0,
    bearing = 0
  ),
  controller = TRUE,
  layers = list(
    list(
      `@@type` = "GeoArrowSolidPolygonLayer",
      id = "utah-buildings",
      data = list(`__arrow` = arrow_b64),
      geometryColumn = "GEOMETRY",
      getFillColor = c(255, 100, 0, 200),
      extruded = FALSE,
      pickable = TRUE,
      `_normalize` = FALSE,
      `_windingOrder` = "CCW"
    )
  )
)

cat("✅ Spec created\n\n")

cat("🚀 Creating widget...\n")

widget <- deckgl(
  spec = spec,
  width = 1024,
  height = 768
)

cat("✅ Widget created!\n\n")
cat("📋 Expected:\n")
cat("   • Orange building footprints (up to 500k)\n")
cat("   • View centered on densest building cluster\n")
cat("   • Gray/black background (no basemap)\n\n")

cat("💡 Controls:\n")
cat("   • Scroll wheel: zoom in/out\n")
cat("   • Drag: pan around\n")
cat("   • Zoom in (14+) to see building shapes\n\n")

widget
```

### Native GeoArrow in Shiny (no binary conversion)

This example demonstrates rendering GeoArrow polygons in Shiny using the
native `GeoArrowPolygonLayer`, which passes Arrow tables directly to the
layer without converting to binary format:

``` r
library(shiny)
library(rDeckgl)
library(arrow)

# Prepare the data file
parquet_path <- "Utah.parquet"

if (!file.exists(parquet_path)) {
  stop("❌ Parquet file not found: ", parquet_path)
}

# Read Parquet and create Arrow IPC file
parquet_data <- arrow::read_parquet(parquet_path)

# Sample for reasonable performance
max_rows <- 1000000
if (nrow(parquet_data) > max_rows) {
  sample_data <- head(parquet_data, max_rows)
} else {
  sample_data <- parquet_data
}

# Compute density-based center
bbox_data <- sample_data$GEOMETRY_bbox
if (!is.null(bbox_data)) {
  xmin <- as.numeric(bbox_data$xmin)
  xmax <- as.numeric(bbox_data$xmax)
  ymin <- as.numeric(bbox_data$ymin)
  ymax <- as.numeric(bbox_data$ymax)

  cx <- (xmin + xmax) / 2
  cy <- (ymin + ymax) / 2

  grid_size <- 0.1
  grid_x <- floor(cx / grid_size)
  grid_y <- floor(cy / grid_size)
  grid_key <- paste(grid_x, grid_y, sep = ",")

  grid_counts <- table(grid_key)
  densest_cell <- names(which.max(grid_counts))
  densest_indices <- which(grid_key == densest_cell)

  center_lon <- mean(cx[densest_indices], na.rm = TRUE)
  center_lat <- mean(cy[densest_indices], na.rm = TRUE)
} else {
  center_lon <- -110.4144
  center_lat <- 39.4991
}

# Write Arrow IPC file to temporary location
temp_arrow <- tempfile(fileext = ".arrows")
arrow_table <- arrow::arrow_table(sample_data)
arrow::write_ipc_stream(arrow_table, temp_arrow)

# Set up static file serving
static_root <- dirname(temp_arrow)
static_name <- "utahdata"
addResourcePath(static_name, static_root)
arrow_url <- paste0(static_name, "/", basename(temp_arrow))

# UI
ui <- fluidPage(
  titlePanel("Utah Buildings - Native GeoArrow Rendering"),
  deckglOutput("map", width = "100%", height = "600px")
)

# Server
server <- function(input, output, session) {
  output$map <- renderDeckgl({
    spec <- list(
      `@@type` = "DeckGL",
      width = 1024,
      height = 600,
      initialViewState = list(
        longitude = center_lon,
        latitude = center_lat,
        zoom = 12,
        pitch = 0,
        bearing = 0
      ),
      controller = TRUE,
      layers = list(
        list(
          # Use GeoArrowPolygonLayer for native rendering (no binary conversion)
          `@@type` = "GeoArrowPolygonLayer",
          id = "utah-buildings-native",
          data = list(`__arrow_url` = arrow_url),
          geometryColumn = "GEOMETRY",
          getFillColor = c(255, 100, 0, 200),
          getLineColor = c(255, 255, 255, 100),
          filled = TRUE,
          stroked = TRUE,
          extruded = FALSE,
          pickable = TRUE,
          autoHighlight = TRUE
        )
      )
    )

    deckgl(spec = spec, width = "100%", height = "600px")
  })

  # Cleanup on session end
  onSessionEnded(function() {
    if (file.exists(temp_arrow)) {
      unlink(temp_arrow)
    }
  })
}

# Run app
shinyApp(ui, server)
```

**Key differences from binary conversion:**

- Uses `GeoArrowPolygonLayer` instead of `GeoArrowSolidPolygonLayer`
- Arrow table passed directly to layer (no conversion to binary arrays)
- Supports full data-driven styling with accessors
- No `_normalize` or `_windingOrder` flags needed

## Next Steps

- Build your own specs by swapping the data queries in these templates
  (DuckDB-backed or GeoArrow IPC/Parquet inputs).
- For large datasets, prefer URL-based loading patterns to avoid
  embedding multi-megabyte payloads in HTML.
- Read the [deck.gl documentation](https://deck.gl/docs) for the full
  catalog of layers, views, and accessors.
- Follow the [rDeckgl GitHub](https://github.com/TiRizvanov/rDeckgl) for
  updates and additional recipes.
