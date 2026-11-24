# Absolute capacity policy

`review` blocks regressions, so it can pass when both plans have the same
overload. Use `gate` when release criteria also restrict the candidate's
absolute overload. The command exits 2 if either the regression check or a
configured resource ceiling blocks, 0 if both pass, and 1 for rejected input
or an analysis error.

Run from the repository root.

```sh
moon run cmd/batchcontour --target wasm -- review examples/kubernetes/existing-overload.json
moon run cmd/batchcontour --target wasm -- gate examples/kubernetes/existing-overload.json examples/kubernetes/strict-policy.json
```

Both plans use the upstream `hello` minute schedule with synthetic duration
and demand. Two instances occupy the shared resource in both minutes of the
window, including an instance launched before the window. The review exits
0 because nothing worsens. The policy gate reports `possible_minutes` with
actual 2 and limit 1. Peak excess equals its ceiling and passes.

## Input and report

The policy uses `batchcontour.capacity-policy.v1` and a `resources` object.
Include one to 32 named resources from the review budget, with at least one
named ceiling per resource. Each ceiling is an integer from 0 through
9,007,199,254,740,991 in decimal digit notation. An omitted ceiling leaves that
metric unconstrained. A zero ceiling permits no overload in that metric.
Complete absence of overload for a listed resource yields zero metrics.

| Ceiling | Candidate measurement |
|---|---|
| `guaranteed_minutes` | Total minutes with a positive lower shortfall bound |
| `possible_minutes` | Total minutes with a positive upper shortfall bound |
| `peak_maximum_excess` | Largest upper shortfall, in resource units |
| `maximum_excess_unit_minutes` | Upper shortfall multiplied by interval duration and summed |

Values equal to their ceilings pass. The `batchcontour.capacity-gate.v1`
report includes `verdict`, `regression_blocked` and `violations`. Each violation
gives the resource, metric, limit and observed model value. The separate
regression field records the original gate even if all ceilings pass.

Libraries can load `CapacityPolicy::from_json`, preserve it with
`CapacityPolicy::to_json`, then call `check_capacity_policy(input, policy)`
and inspect the typed `CapacityGate` or encode it as JSON. Policy and review
resources must refer to the same named budget.
