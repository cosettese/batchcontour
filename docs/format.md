# Formats and review semantics

A review file describes both versions of a schedule and their shared capacity
budget. The schema discriminator is `batchcontour.input.v1`.

| Field | Accepted value |
|---|---|
| `window.start`, `window.end` | UTC `YYYY-MM-DDTHH:MM:00Z`, years 1970–2099 inclusive. The half-open window lasts between 1 minute and 31 days. |
| `capacities` | Object with 1–32 resource IDs and nonnegative capacities up to 1,000,000. |
| `baseline`, `candidate` | Each is an array of 0–128 jobs. IDs must be unique within a plan. |
| Job `id` | Like resource IDs, 1–64 ASCII letters, digits, underscores or hyphens. IDs are case-sensitive. |
| Job `cron` | Numeric five-field cron in UTC, with spaces or tabs between fields. See the dialect below. |
| Job `min_minutes`, `max_minutes` | Integral duration bounds, from 1 through 10,080 minutes, in ascending order. |
| Job `demand` | Object mapping at least one declared resource to an integer from 1 through 1,000,000. Each resource uses its own unit. |

Numbers use decimal digits. Fractional and exponent representations, duplicate
keys including escaped equivalents, unknown fields and invalid UTF-8 are
rejected. The CLI accepts a regular UTF-8 file up to 1 MiB. The library limits
JSON input to 1,048,576 UTF-16 code units and nesting depth 8. The canonical
serialization sorts resource and job IDs lexically and preserves the cron
expression text. Object order, job order and whitespace outside strings have
no capacity meaning.

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
cluster controller catch-up, retry, dynamic capacity and local time/DST.

The report uses schema `batchcontour.report.v1`. For each resource it partitions
the window at occupancy changes from either plan. It emits an interval whenever
either plan may exceed capacity. The minimum and maximum excess are independently
`max(0, occupancy - capacity)`. The gate blocks if the candidate increases
either excess bound on any interval. It can pass with pre-existing overload,
which is still reported. `regression_count` counts flagged resource intervals,
with evidence changes allowed to split otherwise contiguous intervals.

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
