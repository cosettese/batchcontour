# Check duration assumptions against completed runs

The capacity model requires a minimum and maximum duration for each job.
`verify-durations` checks those declarations against completed runs from both
plan versions. It compares exact elapsed seconds to the inclusive minute
bounds converted to seconds. A short run can invalidate the minimum used to
identify guaranteed overload. A long run can invalidate the upper bound.

```sh
moon run cmd/batchcontour --target wasm -- verify-durations examples/kubernetes/maintenance.json examples/kubernetes/runtime-outlier.json
moon run cmd/batchcontour --target wasm -- verify-durations examples/kubernetes/maintenance.json examples/kubernetes/runtime-in-range.json
```

The fixtures use synthetic timings for the public Kubernetes example job.
The first command flags `can-2` at 143 seconds and exits 2. The second supplies
a sample set within the range and exits 0. Invalid files or unknown job
references exit 1 and write a diagnostic to standard error. Run the separate
`review` command to decide whether the assessed schedules fit the capacity
budget. Evidence checks describe the supplied sample set. The caller determines
whether those measurements represent future resource occupancy.

## Input and mapping

The history document uses schema `batchcontour.history.v1` and contains
`min_samples`, an integer from 1 through 4,096, and `runs`, an array of at
most 4,096 completed observations.

| Run field | Meaning |
|---|---|
| `plan` | `baseline` or `candidate`. A measurement belongs to exactly one side. |
| `job` | The logical job ID declared on that side of the review. |
| `id` | Stable run ID, unique across the jobs on that plan side. |
| `started_at`, `finished_at` | UTC `YYYY-MM-DDTHH:MM:SSZ`, years 1970–2099. A finish can equal its start at this precision. |

IDs follow the review file's ASCII rules. The observation period can precede
the review window. Collect run IDs and timestamps that correspond to the
period during which the job holds the modelled resources. For Kubernetes Job
exports, a collector can use the Job's identity and map it to the logical
CronJob. The Job API's `status.startTime` refers to controller processing and
can reset on resume. Its `status.completionTime` covers successful completion.
Use those values only when they suit the duration assumptions. The CLI accepts
the explicit history schema. Raw manifests, failed or unfinished runs without
a finish, non-UTC and subsecond timestamps are rejected by this format.
The collector selects completed, comparable observations and assigns their
plan and job labels.
[Kubernetes Job Status](https://kubernetes.io/docs/reference/kubernetes-api/batch/job-v1/#JobStatus)

## Library and output

Read a `ReviewInput` and a `RunHistory` using their `from_json` methods.
Call `check_durations(review, history)` and inspect `DurationReport::checks`
and `DurationReport::min_samples`, or serialize it with `to_json`. A history can round-trip using
`RunHistory::to_json`. Its canonical form orders entries by plan and run ID.

The `batchcontour.duration-report.v1` result includes a row for every job on
each side, even without observations. A row gives the declared and observed
extremes in seconds, sample count, coverage result and each violating run's
ID, timestamps, elapsed seconds and reason. Missing extrema are JSON null.
Any outlier or row below the minimum sample count blocks the evidence check.
Fix an inaccurate declaration or collect a representative sample before
rerunning the checks.
