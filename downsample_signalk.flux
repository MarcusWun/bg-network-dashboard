// downsample_signalk.flux — InfluxDB Task: Downsample Signal K raw data to 1-minute aggregates
//
// Purpose:
//   The `signalk` bucket holds raw high-frequency data with 7-day retention.
//   This task creates 1-minute mean/min/max aggregates in `signalk_1m`
//   (90-day retention), enabling Grafana to query longer time ranges efficiently.
//
// Setup:
//   In the InfluxDB UI → Tasks → Create Task, paste this file.
//   The `option task` block below is read by InfluxDB to schedule execution.
//   Ensure the `signalk_1m` bucket exists with 90-day retention before enabling.
//
// Grafana usage:
//   Point Grafana queries for time ranges > 7 days at the `signalk_1m` bucket.

// ---------------------------------------------------------------------------
// Task scheduler options
// ---------------------------------------------------------------------------
option task = {
    name:   "Downsample Signal K to 1m aggregates",
    every:  1m,          // run every 1 minute
    offset: 10s,         // slight offset to allow late-arriving writes to land first
}

// ---------------------------------------------------------------------------
// Time window
// ---------------------------------------------------------------------------
// Read the last 2 minutes of raw data to catch any late-arriving points from
// Signal K / signalk-to-influxdb2 without creating gaps.
timeStart = -2m
timeStop  = now()

// ---------------------------------------------------------------------------
// Source: raw Signal K data
// ---------------------------------------------------------------------------
rawData = from(bucket: "signalk")
    |> range(start: timeStart, stop: timeStop)

// ---------------------------------------------------------------------------
// Aggregate: mean per Signal K path per source
// ---------------------------------------------------------------------------
meanAgg = rawData
    |> filter(fn: (r) => r._value != "" and exists r._value)
    |> group(columns: ["_measurement", "_field", "source", "pgn", "sentence"])
    |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)
    |> set(key: "aggregate", value: "mean")
    |> to(
        bucket: "signalk_1m",
        org:    "YOUR_ORG_NAME_HERE",   // <-- match your InfluxDB org name
    )

// ---------------------------------------------------------------------------
// Aggregate: min per Signal K path per source
// ---------------------------------------------------------------------------
minAgg = rawData
    |> filter(fn: (r) => r._value != "" and exists r._value)
    |> group(columns: ["_measurement", "_field", "source", "pgn", "sentence"])
    |> aggregateWindow(every: 1m, fn: min, createEmpty: false)
    |> set(key: "aggregate", value: "min")
    |> to(
        bucket: "signalk_1m",
        org:    "YOUR_ORG_NAME_HERE",   // <-- match your InfluxDB org name
    )

// ---------------------------------------------------------------------------
// Aggregate: max per Signal K path per source
// ---------------------------------------------------------------------------
maxAgg = rawData
    |> filter(fn: (r) => r._value != "" and exists r._value)
    |> group(columns: ["_measurement", "_field", "source", "pgn", "sentence"])
    |> aggregateWindow(every: 1m, fn: max, createEmpty: false)
    |> set(key: "aggregate", value: "max")
    |> to(
        bucket: "signalk_1m",
        org:    "YOUR_ORG_NAME_HERE",   // <-- match your InfluxDB org name
    )
