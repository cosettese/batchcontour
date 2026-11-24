# Compare multiple capacity scenarios

Teams can evaluate the same two job plans under several named budgets.
Keep the schedules, runtime bounds, demands and review window in one
review file. Supply budgets in a `batchcontour.capacity-scenarios.v1`
document with a `scenarios` array containing one to eight entries.

```sh
moon run cmd/batchcontour --target wasm -- scenarios examples/kubernetes/maintenance.json examples/kubernetes/capacity-scenarios.json
```

The public `hello` cron example uses synthetic demand values in this
workflow. Its candidate may need two worker slots. The normal budget
provides two slots. The maintenance budget reduces capacity to one for
two minutes, so only that scenario blocks.

Each entry has a unique `id`, a `capacities` map and a
`capacity_overrides` array. Use the same complete resource ID set as
the review file. The entry supplies its entire budget. Use an empty override
array for fixed capacity. Every override must fit in the common review
window and follow the [timestamp and budget rules](format.md).

The `batchcontour.scenario-report.v1` response orders results by identifier
and includes each scenario's verdict, count of regression intervals and
resource summary. The CLI exits 2 when any scenario regresses, 0 when all
pass and 1 for rejected input or an analysis limit. If any scenario fails
to compute, the command emits a diagnostic and withholds the entire report.

Use `compare_capacity_scenarios(input, text)` from MoonBit to get a typed
`ScenarioReport`. Occurrences are expanded and sorted once. The comparison
scans that timeline separately for each budget, preserving scenario independence
and the detailed review's per-scenario evidence limits.
