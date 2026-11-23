# Project scope

BatchContour helps teams review a change to recurring jobs that share limited
resources. The stable unit of analysis is a resource and a UTC interval.
A report records both occupancy bounds and the instances underlying them.

| Scenario | Operator workflow |
|---|---|
| Backups and ETL share a database pool | Export both schedule versions, enter the observed duration bounds and connection demand, and block a change that overlaps enough runs to exhaust the pool. Move the ETL start and compare again. |
| A sync job moves from hourly to every 15 minutes | Describe the jobs that share its worker slots, inspect overlapping instances of the same sync job when duration exceeds 15 minutes, then compare the original schedule against the repaired candidate. |
| A new GPU evaluation job runs early Monday | Review the deployment with Sunday night training included. If a training instance can remain active when evaluation launches, use the report's start times to move the evaluation window or arrange capacity. |

Kubernetes documents concurrency policy at the individual CronJob level. Its
public issue tracker describes overlapping executions when a multi-tenant
workload takes longer under load. Prefect's global concurrency limits address
shared resources while jobs run. The review described here models a proposed
change before dispatch, using supplied bounds. [Kubernetes controller contract](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) · [Operator report](https://github.com/kubernetes/kubernetes/issues/138569) · [Prefect concurrency limits](https://docs.prefect.io/v3/how-to-guides/workflows/global-concurrency-limits)

| MoonBit project reviewed | Public interface and boundary |
|---|---|
| [moon_cron 0.1.0](https://skills.mooncakes.io/docs/p1nbored/moon_cron%400.1.0) | `Cron::collisions_with` and `ScheduleBook::report` detect coincident trigger minutes and summarize schedule activity. The source report counts names in the same start batch. [Source](https://assets.mooncakes.io/assets/p1nbored/moon_cron%400.1.0/schedule_report.mbt.html) |
| [Moon Change Window Auditor](https://github.com/chen-657/moon-change-window-auditor/blob/main/pkg.generated.mbti) | `audit_with_policy`, `load_profile`, `peak_concurrency` and `diff_plans` overlap on operational window auditing, load and before/after comparisons. BatchContour's comparison aligns recurring instances, weighted named resources and lower/upper duration bounds over the same budget. |
| [SlotPlan](https://github.com/cauchyQ/moonbit-slotplan/blob/master/pkg.generated.mbti) and [ContinuityForge](https://github.com/lllg123/ContinuityForge/blob/main/scheduling/pkg.generated.mbti) | SlotPlan has resource calendars and reservation selection. ContinuityForge's `inspect_rcpsp_schedule` checks explicit resource-constrained schedules and `solve_rcpsp` searches for solutions. BatchContour consumes two fixed recurring schedules and reports capacity changes for review. |
| [MoonDate Cron](https://github.com/moonbitstack/moondate/blob/master/src/cron/pkg.generated.mbti) and [MoonTask](https://github.com/moonbitstack/moontask/blob/master/src/pkg.generated.mbti) | Calendar matching, task execution and backfill can supply input to the audit. BatchContour calls the existing MoonDate parser and matcher. |

The initial search used the Mooncakes index snapshot `26bf2c23` on
2026-11-23 and GitHub queries for `cron`, `schedule`, `capacity scheduling`,
`resource capacity`, `blackout`, `concurrency limit` and `任务排程`.
The published interfaces above establish the observed boundary. Unindexed
repositories and unpublished code may contain related work.

The library keeps parsing, occurrence expansion and capacity comparison in
one portable package. The file CLI performs bounded I/O outside the library.
For each side and each run, expansion emits the start and up to two duration
boundaries per named resource. The comparison sorts resource events and
applies all events at a minute before reporting the following interval.
This also accounts for runs that start before the review window and avoids
counting a shared end/start boundary as an overlap.

The current release compares a fixed UTC model and produces a CI gate with
evidence. Future milestones can bring in duration bounds from documented
runtime exports, then extend the budget to a timeline for scheduled capacity
changes. Real runtime validation and provider adapters will need separate
tests with representative datasets.
