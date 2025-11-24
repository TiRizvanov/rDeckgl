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
#' @param width     CSS or pixel width (e.g. "100%", "600px", or numeric).
#' @param height    CSS or pixel height (e.g. "100%", "600px", or numeric).
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
  width = NULL,
  height = NULL
) {
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

  # 4) Setup DuckDB connection
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)
  try(DBI::dbExecute(con, "LOAD 'arrow';"), silent = TRUE)

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
      # Factors can cause issues when serializing to JSON
      df[] <- lapply(df, function(col) {
        if (is.factor(col)) as.character(col) else col
      })

      # Register data.frame as DuckDB table
      tryCatch(
        {
          DBI::dbWriteTable(con, nm, df, overwrite = TRUE)
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
    spec_list <- hydrate_deckgl_spec(spec_list, con)
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
            dfres <- DBI::dbGetQuery(con, req$sql)
            payload <- lapply(seq_len(nrow(dfres)), function(i) {
              as.list(dfres[i, , drop = FALSE])
            })
            session$sendCustomMessage(
              paste0(uid, "_deckgl_response"),
              list(request = req$request, data = payload)
            )
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
#' @return A hydrated list that is safe to JSON-encode for Deck.gl.
#' @keywords internal
hydrate_deckgl_spec <- function(spec, con) {
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
        df <- DBI::dbGetQuery(con, query)
        if (!is.data.frame(df) || nrow(df) == 0) {
          return(list())
        }
        # Convert factors to characters for safe JSON serialization
        df[] <- lapply(df, function(col) {
          if (is.factor(col)) as.character(col) else col
        })
        # Convert to row-oriented format
        rows <- lapply(seq_len(nrow(df)), function(i) {
          as.list(df[i, , drop = FALSE])
        })
        return(rows)
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
