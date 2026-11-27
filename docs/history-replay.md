# Replay resource occupancy from completed runs

Use `replay-history` after a batch window when job records have reliable UTC start and finish timestamps. Select the plan whose job IDs and resource quantities describe those runs. The command applies each job's declared demand throughout the recorded run, then compares the sum with the capacity in effect at each second.

```sh
moon run cmd/batchcontour --target wasm -- replay-history examples/kubernetes/maintenance.json examples/kubernetes/replay-runs.json candidate
moon run cmd/batchcontour --target wasm -- replay-history examples/kubernetes/maintenance.json examples/kubernetes/replay-runs.json baseline
```

The synthetic candidate runs `early` and `later` overlap from **02:02:15Z** to **02:02:45Z**. Together they occupy two worker slots while maintenance leaves one. The first command emits one overload and exits **2**. The baseline run fits, meets the sample threshold, and exits **0**. See [fixture sources](../SOURCES.md) and the [history input format](duration-evidence.md).

Both commands consume a validated review input (v1, v2, or v3) and a `batchcontour.history.v1` document. The replay uses the exact endpoints of each completed run and clips them to the review window. Start times are inclusive and finish times are exclusive. Capacity overrides apply at their exact minute boundaries. The replay gets the timeline from the completed runs, so cron, launch overrides, and declared duration bounds have no effect on this calculation.

The JSON report `batchcontour.history-replay.v1` shows each overload interval, its demand and capacity, and the sorted IDs of contributing runs. It also shows sample coverage for every job in the selected plan. `run_counts` classifies every record as belonging to the other plan, having zero duration, falling entirely outside the window, or being used. A covered job has at least `min_samples` completed runs with positive overlap. The report estimates occupancy from the supplied records and declared per-run demand. Its coverage threshold counts observed samples.

Exit **2** can indicate overload, insufficient job coverage, or both. Exit **1** reports an input error or analysis limit, including a run whose job is missing from the selected plan. Such errors produce no partial report.

Downstream MoonBit modules can call `replay_history(input, history, "candidate")`, inspect `coverage()` and `overloads()`, or serialize the report with `to_json()`.

## Summarize the impact by resource

```sh
moon run cmd/batchcontour --target wasm -- summarize-replay examples/kubernetes/maintenance.json examples/kubernetes/replay-runs.json candidate
```

The summary reports 30 overloaded seconds, a peak shortfall of one worker
slot, and 30 slot-seconds of accumulated shortfall. The accumulated value is
the sum of each interval's excess multiplied by its duration. It therefore
distinguishes brief peaks from sustained shortfalls.

The summary uses the same coverage, run counts, and exit codes as
`replay-history`. Only overloaded resources appear in `resources`, in
lexical order. Use `replay-history` to locate individual runs. MoonBit
callers can use `ReplayReport::summaries()` or `summary_json()`.
