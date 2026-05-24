# Hydrate Deck.gl DuckDB data references

Recursively walks a Deck.gl specification and replaces \`type =
"duckdb"\` data nodes with concrete result sets queried via the provided
connection.

## Usage

``` r
hydrate_deckgl_spec(
  spec,
  con,
  list_col_metadata = NULL,
  data_transport = c("auto", "file", "inline"),
  data_dir = NULL
)
```

## Arguments

- spec:

  Deck.gl specification as an R list.

- con:

  A live DBI connection to DuckDB.

- list_col_metadata:

  Environment containing metadata about JSON-encoded list columns.

- data_transport:

  \`"auto"\` to use \`"file"\` when \`data_dir\` is supplied and
  \`"inline"\` otherwise, \`"inline"\` for base64 payloads, or
  \`"file"\` for relative Arrow/Parquet URLs.

- data_dir:

  Directory used by \`"file"\` transport.

## Value

A hydrated list that is safe to JSON-encode for Deck.gl.
