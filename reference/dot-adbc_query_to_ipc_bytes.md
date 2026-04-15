# Export a DuckDB query to Arrow IPC bytes via ADBC

Uses the ADBC driver (adbcdrivermanager) to execute a query and capture
the result as raw Arrow IPC stream bytes. This preserves GeoArrow
extension metadata automatically in DuckDB \>= 1.5.

## Usage

``` r
.adbc_query_to_ipc_bytes(con, query)
```

## Arguments

- con:

  A DBI connection to DuckDB (used to resolve the database path).

- query:

  SQL query string.

## Value

Raw vector of Arrow IPC stream bytes, or NULL on failure.
