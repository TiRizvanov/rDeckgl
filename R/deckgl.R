# R/deckgl.R

#' @importFrom stats setNames
NULL

#' Render a Deck.gl visualization
#'
#' Creates an interactive deck.gl visualization from a JSON or YAML specification.
#' Supports server-side data hydration via DuckDB for efficient data handling.
#'
#' @param spec      Deck.gl specification as an R list, JSON text, JSON file path,
#'                  YAML text, or YAML file path.
#' @param specType  One of "auto" (default), "json", or "yaml". Auto-detection
#'                  attempts to infer the format from the input.
#' @param data      Named list of data.frames to register in DuckDB. These tables
#'                  can be referenced in the spec using `type = "duckdb"` data nodes.
#' @param con       Optional DuckDB connection to use for queries. If provided,
#'                  this connection will be used instead of creating a new one.
#'                  This is useful for GeoArrow workflows where you need spatial
#'                  extension and geometry tables already set up.
#' @param width     CSS or pixel width (e.g. "100\%", "600px", or numeric).
#' @param height    CSS or pixel height (e.g. "100\%", "600px", or numeric).
#'
#' @return An htmlwidget that renders the Deck.gl visualization.
#'
#' @examples
#' if (interactive()) {
#'   # Simple scatterplot with inline data
#'   spec <- list(
#'     `@@type` = "DeckGL",
#'     initialViewState = list(
#'       longitude = -122.4,
#'       latitude = 37.76,
#'       zoom = 12,
#'       pitch = 0,
#'       bearing = 0
#'     ),
#'     layers = list(
#'       list(
#'         `@@type` = "ScatterplotLayer",
#'         id = "scatterplot",
#'         data = list(
#'           type = "duckdb",
#'           query = "SELECT lon, lat, radius FROM points"
#'         ),
#'         getPosition = "@@=[lon, lat]",
#'         getRadius = "@@=radius",
#'         getFillColor = c(255, 0, 0)
#'       )
#'     )
#'   )
#'
#'   data <- list(
#'     points = data.frame(
#'       lon = c(-122.4, -122.45, -122.35),
#'       lat = c(37.76, 37.78, 37.74),
#'       radius = c(100, 150, 200)
#'     )
#'   )
#'
#'   deckgl(spec = spec, data = data)
#' }
#'
#' @export
deckgl <- function(
    spec,
    specType = c("auto", "json", "yaml"),
    data = NULL,
    con = NULL,
    width = NULL,
    height = NULL) {
  specType <- match.arg(specType)

  # 1) Determine format
  fmt <- specType
  if (fmt == "auto") {
    if (is.list(spec)) {
      fmt <- "json"
    } else if (is.character(spec) && length(spec) == 1 && file.exists(spec)) {
      ext <- tolower(tools::file_ext(spec))
      fmt <- if (ext %in% c("yaml", "yml")) "yaml" else "json"
    } else if (is.character(spec) && grepl("^\\s*-", spec)) {
      fmt <- "yaml"
    } else if (is.character(spec) && grepl("^\\s*\\{", spec)) {
      fmt <- "json"
    } else {
      fmt <- "json"
    }
  }

  spec_list <- NULL

  # 2) Parse JSON / YAML
  if (fmt == "json") {
    if (is.list(spec)) {
      spec_list <- spec
    } else {
      txt <- if (file.exists(spec)) readLines(spec) else spec
      spec_list <- jsonlite::fromJSON(
        paste(txt, collapse = "\n"),
        simplifyVector = FALSE
      )
    }
  } else if (fmt == "yaml") {
    if (is.list(spec)) {
      spec_list <- spec
    } else {
      txt <- if (file.exists(spec)) readLines(spec) else spec
      spec_list <- yaml::read_yaml(text = paste(txt, collapse = "\n"))
    }
  }

  # 3) Embed width/height into spec_list
  if (!is.null(spec_list)) {
    strip_px <- function(x) {
      if (is.numeric(x)) {
        return(as.integer(x))
      }
      if (is.character(x) && grepl("^[0-9]+px$", x)) {
        return(as.integer(sub("px$", "", x)))
      }
      NULL
    }
    if (is.null(spec_list$width) && !is.null(w <- strip_px(width))) {
      spec_list$width <- w
    }
    if (is.null(spec_list$height) && !is.null(h <- strip_px(height))) {
      spec_list$height <- h
    }
  }

  # 4) Setup DuckDB connection with spatial support
  # Use provided connection or create a new one
  own_con <- is.null(con)
  if (own_con) {
    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
    on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)
    
    # Load spatial extension for GeoArrow support
    try(DBI::dbExecute(con, "INSTALL spatial"), silent = TRUE)
    try(DBI::dbExecute(con, "LOAD spatial"), silent = TRUE)
    
    # Load nanoarrow extension for FORMAT ARROWS export
    try(DBI::dbExecute(con, "INSTALL nanoarrow FROM community"), silent = TRUE)
    try(DBI::dbExecute(con, "LOAD nanoarrow"), silent = TRUE)
    
    # Register GeoArrow extensions for proper Arrow export metadata
    try(DBI::dbExecute(con, "CALL register_geoarrow_extensions()"), silent = TRUE)
  }
  # Note: If user provides con, they are responsible for loading spatial extension,
  # nanoarrow extension, and calling register_geoarrow_extensions() if needed

  # Create metadata storage for list columns (use environment, not S4 slot)
  list_col_metadata <- new.env(parent = emptyenv())

  # 5) Handle data registration
  # Convert R data.frames to DuckDB tables for efficient server-side queries
  if (!is.null(data)) {
    if (!is.list(data)) {
      stop("'data' must be a named list of data.frames")
    }
    if (is.null(names(data)) || any(names(data) == "")) {
      stop("All elements in 'data' list must be named")
    }

    for (nm in names(data)) {
      df <- data[[nm]]
      if (!inherits(df, "data.frame")) {
        stop(sprintf(
          "Element '%s' in data list must be a data.frame, got: %s",
          nm,
          class(df)[1]
        ))
      }

      # Convert factors to character for safe JSON serialization
      # Also handle list columns by converting to JSON strings
      list_cols <- c()
      df[] <- lapply(names(df), function(col_name) {
        col <- df[[col_name]]
        if (is.factor(col)) {
          return(as.character(col))
        }
        # Check if this is a list column (nested structure like polygon coordinates)
        if (is.list(col) && !is.data.frame(col)) {
          list_cols <<- c(list_cols, col_name)
          # Convert list to JSON string for DuckDB storage
          return(vapply(col, jsonlite::toJSON, character(1), auto_unbox = TRUE))
        }
        col
      })
      names(df) <- names(data[[nm]])

      # Register data.frame as DuckDB table
      tryCatch(
        {
          DBI::dbWriteTable(con, nm, df, overwrite = TRUE)

          # Store metadata about which columns are JSON-encoded lists
          if (length(list_cols) > 0) {
            list_col_metadata[[nm]] <- list_cols
          }
        },
        error = function(e) {
          stop(sprintf(
            "Failed to register table '%s' in DuckDB: %s",
            nm,
            e$message
          ))
        }
      )
    }
  }

  # 6) Hydrate spec with DuckDB data
  if (!is.null(spec_list)) {
    spec_list <- hydrate_deckgl_spec(spec_list, con, list_col_metadata)
  }

  # 7) Setup Shiny query handler if in Shiny context
  uid <- paste0("deckgl_", sprintf("%08x", sample.int(.Machine$integer.max, 1)))
  session <- shiny::getDefaultReactiveDomain()

  if (!is.null(session) && !is.null(con)) {
    # Store connection in session userData
    session$userData$deckglConnections <-
      c(session$userData$deckglConnections, setNames(list(con), uid))

    # Override on.exit to prevent premature disconnection
    on.exit(NULL)

    # Register query handler
    shiny::observeEvent(
      session$input[[paste0(uid, "_deckgl_query")]],
      {
        req <- session$input[[paste0(uid, "_deckgl_query")]]
        if (is.null(req)) {
          return()
        }

        if (is.null(con)) {
          warning("Connection for widget ", uid, " is not available.")
          return()
        }

        tryCatch(
          {
            # Check if Arrow format is requested
            use_arrow <- identical(req$type, "arrow") || 
                         identical(req$type, "geoarrow")
            
            if (use_arrow && requireNamespace("arrow", quietly = TRUE) && 
                requireNamespace("base64enc", quietly = TRUE)) {
              # Export as Arrow IPC stream
              res <- DBI::dbSendQuery(con, req$sql)
              
              # Use duckdb's arrow export
              arrow_table <- duckdb::duckdb_fetch_arrow(res, stream = TRUE)
              DBI::dbClearResult(res)
              
              # Convert to raw IPC stream
              raw_bytes <- arrow::write_to_raw(arrow_table, format = "stream")
              
              # Convert to base64 for JSON-safe transmission
              base64_data <- base64enc::base64encode(raw_bytes)
              
              session$sendCustomMessage(
                paste0(uid, "_deckgl_response"),
                list(
                  request = req$request,
                  data = base64_data,
                  dataFormat = "arrow"
                )
              )
            } else {
              # Legacy JSON format
              dfres <- DBI::dbGetQuery(con, req$sql)
              payload <- lapply(seq_len(nrow(dfres)), function(i) {
                as.list(dfres[i, , drop = FALSE])
              })
              session$sendCustomMessage(
                paste0(uid, "_deckgl_response"),
                list(
                  request = req$request,
                  data = payload,
                  dataFormat = "json"
                )
              )
            }
          },
          error = function(e) {
            session$sendCustomMessage(
              paste0(uid, "_deckgl_response"),
              list(request = req$request, error = as.character(e))
            )
          }
        )
      },
      ignoreNULL = TRUE
    )

    # Cleanup connections on session end
    if (is.null(session$userData$.deckglCleanup)) {
      session$onSessionEnded(function() {
        lapply(session$userData$deckglConnections, function(cnn) {
          try(DBI::dbDisconnect(cnn), silent = TRUE)
        })
      })
      session$userData$.deckglCleanup <- TRUE
    }
  }

  # 8) Create widget
  widget_data <- list(
    spec = spec_list,
    widgetId = uid
  )

  htmlwidgets::createWidget(
    name = "deckgl",
    x = widget_data,
    width = width,
    height = height,
    package = "rDeckgl",
    sizingPolicy = htmlwidgets::sizingPolicy(browser.fill = TRUE)
  )
}


#' Hydrate Deck.gl DuckDB data references
#'
#' Recursively walks a Deck.gl specification and replaces `type = "duckdb"`
#' data nodes with concrete result sets queried via the provided connection.
#'
#' @param spec Deck.gl specification as an R list.
#' @param con  A live DBI connection to DuckDB.
#' @param list_col_metadata Environment containing metadata about JSON-encoded list columns.
#' @return A hydrated list that is safe to JSON-encode for Deck.gl.
#' @keywords internal
hydrate_deckgl_spec <- function(spec, con, list_col_metadata = NULL) {
  transform_node <- function(node, inside_data = FALSE) {
    if (is.list(node)) {
      if (
        !is.null(node$type) && identical(node$type, "duckdb") && inside_data
      ) {
        if (is.null(con)) {
          stop(
            "Deck.gl spec includes DuckDB data but no active connection is available."
          )
        }
        query <- node$query
        if (!is.character(query) || length(query) < 1 || !nzchar(query[[1]])) {
          stop("Deck.gl DuckDB data nodes require a non-empty 'query' field.")
        }
        query <- query[[1]]
        fmt <- if (is.null(node$format)) "json" else tolower(node$format[[1]])

        if (fmt == "geoarrow") {
          # For GeoArrow format, use DuckDB's native Arrow export to preserve
          # GeoArrow extension metadata. This requires spatial extension and
          # register_geoarrow_extensions() to be called.
          # 
          # IMPORTANT: We read the raw bytes directly from DuckDB's output
          # instead of parsing through R's arrow package, which might strip
          # extension metadata.
          temp_arrow <- tempfile(fileext = ".arrows")
          on.exit(unlink(temp_arrow), add = TRUE)
          
          result <- tryCatch({
            # Use COPY ... (FORMAT ARROWS) for proper GeoArrow metadata
            DBI::dbExecute(con, sprintf(
              "COPY (%s) TO '%s' (FORMAT ARROWS)",
              query, temp_arrow
            ))
            
            # Read raw bytes directly - DO NOT parse through R arrow package
            # as that can strip extension metadata
            raw_bytes <- readBin(temp_arrow, "raw", file.info(temp_arrow)$size)
            base64_data <- base64enc::base64encode(raw_bytes)
            
            list(
              `__arrow` = base64_data,
              `__arrow_format` = "stream",
              `__geoarrow` = TRUE
            )
          }, error = function(e) {
            # Fallback: regular Arrow export without GeoArrow metadata
            warning("GeoArrow export failed, falling back to regular Arrow: ", e$message)
            df <- DBI::dbGetQuery(con, query)
            if (!is.data.frame(df) || nrow(df) == 0) {
              return(list(`__arrow` = "", `__arrow_format` = "stream"))
            }
            df[] <- lapply(df, function(col) {
              if (is.factor(col)) as.character(col) else col
            })
            arrow_table <- arrow::as_arrow_table(df)
            raw_bytes <- arrow::write_to_raw(arrow_table, format = "stream")
            base64_data <- base64enc::base64encode(raw_bytes)
            list(
              `__arrow` = base64_data,
              `__arrow_format` = "stream"
            )
          })
          return(result)
        } else if (fmt %in% c("geoparquet", "parquet")) {
          # Export to Parquet, then re-read via parquet_scan and export Arrow stream
          temp_parquet <- tempfile(fileext = ".parquet")
          temp_arrow <- tempfile(fileext = ".arrows")
          on.exit(unlink(c(temp_parquet, temp_arrow)), add = TRUE)
          
          result <- tryCatch({
            DBI::dbExecute(con, sprintf(
              "COPY (%s) TO '%s' (FORMAT PARQUET)",
              query, temp_parquet
            ))
            DBI::dbExecute(con, sprintf(
              "COPY (SELECT * FROM parquet_scan('%s')) TO '%s' (FORMAT ARROWS)",
              temp_parquet, temp_arrow
            ))
            raw_bytes <- readBin(temp_arrow, "raw", file.info(temp_arrow)$size)
            base64_data <- base64enc::base64encode(raw_bytes)
            list(
              `__arrow` = base64_data,
              `__arrow_format` = "stream",
              `__geoarrow` = TRUE
            )
          }, error = function(e) {
            warning("GeoParquet export failed: ", e$message)
            list(`__arrow` = "", `__arrow_format` = "stream")
          })
          return(result)
        } else if (fmt == "arrow") {
          # Regular Arrow format without GeoArrow metadata
          df <- DBI::dbGetQuery(con, query)
          if (!is.data.frame(df) || nrow(df) == 0) {
            return(list(
              `__arrow` = "",
              `__arrow_format` = "stream"
            ))
          }
          df[] <- lapply(df, function(col) {
            if (is.factor(col)) as.character(col) else col
          })
          arrow_table <- arrow::as_arrow_table(df)
          raw_bytes <- arrow::write_to_raw(arrow_table, format = "stream")
          base64_data <- base64enc::base64encode(raw_bytes)
          return(list(
            `__arrow` = base64_data,
            `__arrow_format` = "stream"
          ))
        } else {
          # Default JSON format
          df <- DBI::dbGetQuery(con, query)
          if (!is.data.frame(df) || nrow(df) == 0) {
            return(list())
          }

          # Parse JSON-encoded list columns back to nested lists
          # Check if metadata environment has info about JSON-encoded columns
          if (!is.null(list_col_metadata) && length(list_col_metadata) > 0) {
            # Extract table names from query (simple heuristic: look for FROM clause)
            query_upper <- toupper(query)
            for (table_name in ls(list_col_metadata)) {
              if (grepl(toupper(table_name), query_upper, fixed = TRUE)) {
                json_cols <- list_col_metadata[[table_name]]
                for (col_name in json_cols) {
                  if (col_name %in% names(df)) {
                    df[[col_name]] <- lapply(df[[col_name]], function(json_str) {
                      if (is.na(json_str) || json_str == "") return(NULL)
                      jsonlite::fromJSON(json_str, simplifyVector = FALSE)
                    })
                  }
                }
              }
            }
          }

          # Convert factors to characters for safe JSON serialization
          df[] <- lapply(df, function(col) {
            if (is.factor(col)) as.character(col) else col
          })

          # Convert to row-oriented format, preserving list columns
          rows <- lapply(seq_len(nrow(df)), function(i) {
            row <- list()
            for (col_name in names(df)) {
              val <- df[[col_name]][i]
              # Preserve list-column structure (e.g., polygon coordinates)
              if (is.list(val) && length(val) == 1) {
                row[[col_name]] <- val[[1]]
              } else {
                row[[col_name]] <- val
              }
            }
            row
          })
          return(rows)
        }
      }

      if (is.null(names(node))) {
        return(lapply(node, transform_node, inside_data = inside_data))
      }

      result <- node
      for (nm in names(result)) {
        result[[nm]] <- transform_node(
          result[[nm]],
          inside_data = inside_data || identical(nm, "data")
        )
      }
      return(result)
    }

    node
  }

  transform_node(spec, inside_data = FALSE)
}
