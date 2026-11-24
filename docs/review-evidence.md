# Archive and reproduce a capacity review

Store an input and its full report together when a deployment review needs
to stay reproducible after a pipeline run. Keep the approved review input
separately, such as in the reviewed Git revision. Verification checks
the archive against that trusted input, then recomputes each finding.

Run from the repository root in a POSIX shell or PowerShell 7.

```sh
moon run cmd/batchcontour --target wasm -- archive-review examples/kubernetes/maintenance.json > capacity-evidence.json
moon run cmd/batchcontour --target wasm -- verify-evidence examples/kubernetes/maintenance.json capacity-evidence.json
```

The maintenance example has two regression intervals. Both commands exit 0
when the archive is generated and verified. The archived and recomputed
review retains `"verdict":"blocked"`. A CI job that needs to use the review
as a deployment gate can run `review` or `gate` separately.

The `batchcontour.review-evidence.v1` envelope contains `schema`, the normalized
`input` and the detailed `report`. The verifier accepts object member order
and insignificant whitespace. Array ordering and exact integer spelling are
canonical. Unknown, missing or duplicate keys, inconsistent inputs, altered
totals and changed contributors are refused. A mismatch exits 1 with a path
to the first discrepancy and no report on standard output. The CLI reads
archives from regular UTF-8 files of up to 32 MiB.

Use `archive_capacity_review(input)` to compute the archive in a MoonBit
program. `verify_capacity_evidence(trusted_input, text)` returns the fresh
`CapacityReport`. This is a reproducibility check using independent input
from the caller. The archive carries no signature or author authentication.
