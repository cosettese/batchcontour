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

From the root, run `moon run scripts/verify.mbtx portable` to exercise all three
fixtures. It checks the blocked report, refusal of the duplicate capacity key in
`invalid.json`, and the repaired report following the refusal.
