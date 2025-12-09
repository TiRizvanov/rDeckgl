#' @importFrom base64enc base64encode
#' @importFrom DBI dbGetQuery dbConnect dbDisconnect dbWriteTable dbExecute
#' @importFrom duckdb duckdb
#' @importFrom htmlwidgets createWidget
#' @importFrom shiny getDefaultReactiveDomain httpResponse
#' @importFrom digest digest
NULL

#' Hydrate Deck.gl DuckDB data references
#'
#' @param spec The Deck.gl spec list
#' @param con The DuckDB connection
#' @return A spec list where DuckDB nodes are replaced with Arrow IPC payloads
#' @keywords internal
hydrate_deckgl_spec <- function(spec, con) {
  
  # Check if we are inside a generic Shiny session
  session <- shiny::getDefaultReactiveDomain()
  
  transform_node <- function(node, inside_data = FALSE) {
    if (is.list(node)) {
      
      # DETECT DUCKDB DATA REQUEST
      if (!is.null(node$type) && identical(node$type, "duckdb") && inside_data) {
        
        if (is.null(con)) stop("Deck.gl: No active DuckDB connection.")
        
        query <- node$query
        
        # Use DuckDB's native Arrow export for performance and complex type support
        arrow_file <- tempfile(fileext = ".arrow")
        on.exit(if(file.exists(arrow_file)) unlink(arrow_file), add = TRUE)
        
        copy_query <- sprintf("COPY (%s) TO '%s' (FORMAT ARROW)", query, arrow_file)
        DBI::dbExecute(con, copy_query)
        
        raw_ipc <- readBin(arrow_file, "raw", n = file.size(arrow_file))
        
        # DECISION: Shiny vs Static
        if (!is.null(session)) {
          # --- SHINY PATH (BINARY URL) ---
          
          # Generate a unique ID for this specific dataset
          uid <- paste0("arrow_", digest::digest(query))
          
          # Register a binary data handler for this session
          # This creates a temporary URL that serves the raw bytes
          session$registerDataObj(uid, raw_ipc, function(data, req) {
            shiny::httpResponse(
              200, "application/octet-stream", content = data
            )
          })
          
          return(list(
            type = "__arrow_url__", # JS will fetch() this
            url = session$registerDataObj(uid, raw_ipc, function(data, req) {
                 shiny::httpResponse(200, "application/octet-stream", content = data)
            })
          ))
          
        } else {
          # --- STATIC PATH (BASE64) ---
          return(list(
            type = "__arrow_ipc_base64__",
            payload = base64enc::base64encode(raw_ipc)
          ))
        }
      }

      # Recursive Traversal
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

#' Render a Deck.gl visualization
#'
#' @param spec A Deck.gl specification. Can be a list, JSON string, YAML string, or file path.
#' @param specType Format of the spec: "auto" (default), "json", or "yaml". Auto-detection is used by default.
#' @param data Optional named list of data frames to register in DuckDB for querying in the spec.
#' @param width Width of the widget (optional, auto-detected in Shiny).
#' @param height Height of the widget (optional, auto-detected in Shiny).
#'
#' @return An htmlwidget object for rendering a Deck.gl visualization.
#' @export
#' @examples
#' \dontrun{
#' # Create a simple scatterplot layer
#' spec <- list(
#'   initialViewState = list(longitude = -122.4, latitude = 37.8, zoom = 11),
#'   layers = list(
#'     list(
#'       "@@type" = "ScatterplotLayer",
#'       data = list(list(position = c(-122.4, 37.8)))
#'     )
#'   )
#' )
#' deckgl(spec)
#' }
deckgl <- function(spec, specType = c("auto", "json", "yaml"), data = NULL, width = NULL, height = NULL) {
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

  # Setup DuckDB
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Load required extensions
  # We need 'arrow' for the COPY (FORMAT ARROW) command
  # We need 'spatial' in case the user's query uses spatial functions
  try({
    DBI::dbExecute(con, "INSTALL arrow; LOAD arrow;")
    DBI::dbExecute(con, "INSTALL spatial; LOAD spatial;")
  }, silent = TRUE)
  
  # Register R dataframes if provided
  if(!is.null(data)) {
     for(nm in names(data)) {
        DBI::dbWriteTable(con, nm, data[[nm]])
     }
  }
  
  # Hydrate Spec
  hydrated_spec <- hydrate_deckgl_spec(spec_list, con)

  x <- list(
    spec = hydrated_spec
  )

  htmlwidgets::createWidget("deckgl", x, width = width, height = height, package = "rDeckgl")
}
