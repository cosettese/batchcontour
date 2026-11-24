# Review separately versioned plans

Keep the resource budget and schedule in separate files. When a change is proposed, extract the schedule from the deployed revision and compare it with the proposed revision under the shared budget. This lets operators reuse the same baseline without copying it into each candidate.

```sh
moon run cmd/batchcontour --target wasm -- assemble examples/pull-request/budget.json examples/pull-request/baseline.json examples/pull-request/candidate.json > review.json
moon run cmd/batchcontour --target wasm -- review review.json
```

The example compares the five-minute baseline against the minute-by-minute candidate and reports two regressions during maintenance. Pass the assembled file to `gate`, `archive-review` or any command that accepts a combined review.

A `batchcontour.budget.v1` document carries `window`, `capacities` and `capacity_overrides`. Each `batchcontour.plan.v1` document carries only `jobs`. Jobs follow the v3 review schema and include `launch_overrides`, using an empty array for no overrides. The assembler validates both plans against the same resources and UTC window, and emits a canonical v3 review. Unknown fields and reuse of an override outside its supported window produce an error. [Combined schema](format.md)

For an existing combined review, `split INPUT.json` returns a JSON object with `budget`, `baseline` and `candidate` documents. Save those values as separate files. For example, with `jq`:

```sh
moon run cmd/batchcontour --target wasm -- split examples/kubernetes/maintenance.json > parts.json
jq .budget parts.json > budget.json
jq .baseline parts.json > baseline.json
jq .candidate parts.json > candidate.json
```

Reassembling split v3 data preserves its canonical serialization. Older versions gain empty arrays and the v3 schema while keeping their capacity review results. Both file commands return 0 on successful conversion and 1 on invalid input. MoonBit callers can use `assemble_review(budget, baseline, candidate)` and `ReviewInput::split_documents()`.
