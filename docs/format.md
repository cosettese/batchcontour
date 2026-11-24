# Formats and review semantics

A review file describes both versions of a schedule and their shared capacity
budget. Use `batchcontour.input.v1` for a fixed budget,
`batchcontour.input.v2` for a capacity timeline, or
`batchcontour.input.v3` to specify individual launch decisions as well.

| Field | Accepted value |
|---|---|
| `window.start`, `window.end` | UTC `YYYY-MM-DDTHH:MM:00Z`, years 1970–2099 inclusive. The half-open window lasts between 1 minute and 31 days. |
| `capacities` | Object with 1–32 resource IDs and nonnegative capacities up to 1,000,000. |
| `baseline`, `candidate` | Each is an array of 0–128 jobs. IDs must be unique within a plan. |
| Job `id` | Like resource IDs, 1–64 ASCII letters, digits, underscores or hyphens. IDs are case-sensitive. |
| Job `cron` | Numeric five-field cron in UTC, with spaces or tabs between fields. See the dialect below. |
| Job `min_minutes`, `max_minutes` | Integral duration bounds, from 1 through 10,080 minutes, in ascending order. |
| Job `demand` | Object mapping at least one declared resource to an integer from 1 through 1,000,000. Each resource uses its own unit. |
| `capacity_overrides` | Required in v2 and v3. Array of 0–512 objects with `resource`, `start`, `end`, and `units`. Each interval replaces the capacity of that resource for both plans. |
| Job `launch_overrides` | Required in v3. Array of 0–128 objects with a UTC minute `at` and a boolean `run`. |

An explicit launch decision takes priority over cron for that job and minute.
Use `true` to make one launch happen, including a one-time backfill, or
`false` to suppress one. A true decision at a scheduled minute still produces
only one run. Duplicate decisions and starts that could never overlap the
review window are rejected. Carry-in starts before the window are accepted
when the job can still be running in it. Decisions sort by UTC minute in the
canonical input and retain the job's original duration and demand. The
[maintenance example](../examples/kubernetes/skip-maintenance.json) cancels
two launches to keep the workload within the temporarily reduced budget.

An override uses the same UTC timestamps and capacity bounds as the default.
The resource must exist in `capacities`. Every override must have positive
length and fit entirely inside the review window. Overrides for the same
resource may touch at an endpoint. Overlapping overrides for one resource are
rejected, including equal-valued duplicates. Different resources may change
capacity at the same time. Outside its override intervals, a resource uses
its default capacity. A capacity of zero models a complete outage.

Numbers use decimal digits. Fractional and exponent representations, duplicate
keys including escaped equivalents, unknown fields and invalid UTF-8 are
rejected. The CLI accepts a regular UTF-8 file up to 1 MiB. The library limits
JSON input to 1,048,576 UTF-16 code units and nesting depth 8. The canonical
serialization retains the input schema, sorts resource and job IDs lexically
and preserves the cron expression text. It also orders overrides by resource
and start. Object order, job order and whitespace outside strings have no
capacity meaning.

The cron dialect uses fields minute, hour, day of month, month and weekday.
Sunday is 0 or 7. It supports numeric values, lists, ranges and steps with
numbers of at most two digits. An expression is at most 128 characters.
When both day selectors differ from the literal `*`, either may match.
When one is `*`, the other decides. The restricted grammar rejects
nicknames, named months and weekdays, seconds fields and Quartz directives.
It evaluates minutes using [MoonDate's cron matching](https://github.com/moonbitstack/moondate/blob/master/src/cron/cron.mbt).

For one scheduled start `t` and duration bounds `lo`, `hi`, demand is
present in both totals over `[t, t+lo)` and only in the maximum over
`[t+lo, t+hi)`. Runs that start before the window still contribute if
they can extend into it. The analysis assumes every run starts at the given
minute, holds each listed quantity throughout execution, and finishes within
the declared bounds. The model excludes queued starts, missed launches,
cluster controller catch-up, retry, capacity derived from live telemetry and
local time/DST.

The report uses schema `batchcontour.report.v1`. For each resource it partitions
the window at occupancy changes from either plan and at the boundaries of the
resource's capacity overrides. It emits an interval whenever
either plan may exceed capacity. The minimum and maximum excess are independently
`max(0, occupancy - capacity)`. The gate blocks if the candidate increases
either excess bound on any interval. It can pass with pre-existing overload,
which is still reported. `regression_count` counts flagged resource intervals,
with evidence and capacity boundaries allowed to split otherwise contiguous
intervals. A finding's `capacity` is the effective value for its interval.
All three input versions emit the same report schema.

The report lists each possible contributor with the original run start and its
units. Entries with `guaranteed: true` make up the lower bound, all entries make
up the upper bound. An interval with `minimum_excess > 0` is guaranteed to
overload under the model. An interval with zero minimum excess and positive
maximum excess may overload. Bound changes compare the two submitted models.
They do not measure actual runtime deltas.

Expansion is bounded by 120,000 combined resource events. A report can contain
up to 12,000 intervals and 100,000 contributor entries. Exceeding any budget
returns a limit diagnostic with no partial report. A shorter review window or
a review of independent resource groups can reduce the size.

## Capacity summary

`summarize INPUT.json` uses the same gate and exit codes as `review`. It
emits `batchcontour.capacity-summary.v1`. Each resource that may exceed
capacity in either plan gets one row. In each plan, guaranteed minutes count
intervals with a positive lower excess and possible minutes count all
intervals with a positive upper excess, including those guaranteed to overload.
The peak fields are the largest lower and upper shortfall. Excess unit-minutes
are the sum of shortfall multiplied by interval length, such as
2 connections for 3 minutes producing 6 connection-minutes. Values are per
resource and use exact integers within the analysis limits.

`regression_minutes` counts minutes when either excess bound increases for
the same resource. Improvements elsewhere do not offset those minutes, so
the summary's verdict matches the detailed report. For job-level evidence
use `review`. Downstream MoonBit code can use `CapacityReport::summaries`
or encode the same summary with `summary_json`.

[Absolute policies](capacity-policy.md) use these measurements to constrain
the candidate even if its overload already existed in the baseline.
