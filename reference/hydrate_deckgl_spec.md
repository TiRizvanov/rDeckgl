# Hydrate Deck.gl DuckDB data references

Recursively walks a Deck.gl specification and replaces \`type =
"duckdb"\` data nodes with concrete result sets queried via the provided
connection.

## Usage

``` r
hydrate_deckgl_spec(spec, con, list_col_metadata = NULL)
```

## Arguments

- spec:

  Deck.gl specification as an R list.

- con:

  A live DBI connection to DuckDB.

- list_col_metadata:

  Environment containing metadata about JSON-encoded list columns.

## Value

A hydrated list that is safe to JSON-encode for Deck.gl.
