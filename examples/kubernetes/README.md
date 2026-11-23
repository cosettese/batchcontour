# Kubernetes cron example

The job name `hello` and expression `* * * * *` are from the public Kubernetes
CronJob example. The duration bounds, resource budget, `snapshot` job, alternate
schedule and observation window are synthetic, as Kubernetes does not declare
those inputs in the example. The fixtures use the UTC start-time model documented
in this project. [Upstream manifest](https://kubernetes.io/examples/application/job/cronjob.yaml)

At 02:01 and 02:02, `snapshot` holds two slots and the new `hello` instance
holds one. The previous `hello` instance can hold an additional slot at each
of those minutes in the candidate. Expected load is 3 in both baseline bounds,
3–4 in the candidate, with capacity 3. The report contains two intervals
because the contributing `hello` run IDs change at 02:02. With the
five-minute repair, no pair of `hello` instances can overlap.

In `maintenance.json` the candidate adopts the upstream minute schedule.
Its 1–2 minute runtime means it needs at most two slots in the review window.
Two slots fit at normal capacity. During the synthetic maintenance interval
`[02:02, 02:04)`, one slot is available and the upper demand bound exceeds
capacity by one slot. The report contains two one-minute regression intervals
and the CLI exits 2. The baseline keeps the five-minute cadence.

From the root, run `moon run scripts/verify.mbtx portable` to exercise all four
fixtures. It checks the blocked report, refusal of the duplicate capacity key in
`invalid.json`, the repaired report following the refusal and the maintenance
window's effective capacity.
