### Minor Changes

- ead1ee7: fix: bump the default ClickHouse server image to `26.8.36.3-alpine` (from `25.7-alpine`) for a security fix, and pin ClickHouse Keeper to `clickhouse/clickhouse-keeper:26.8.36.3-alpine` instead of the operator's `latest` default

### Patch Changes

- e2c4be5: feat: update the default HyperDX sources to match the current source schema (only applies to new installs; existing sources are not modified)

  - Traces: set `spanEventsValueExpression: "Events"` and `spanLinksValueExpression: "Links"` so span events (including exceptions) and span links are shown
  - Metrics: register the `summary` and `exponential histogram` metric tables
  - Remove fields HyperDX ignores for each source kind (e.g. log-style fields on the Sessions source, stray `_id`/`id` keys in `metricTables`)
