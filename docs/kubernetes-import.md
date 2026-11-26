# Import completed Kubernetes Jobs

Use `import-kubernetes` to extract history from one namespace and one deployment cohort. Give reviewed CronJobs a label in `spec.jobTemplate.metadata.labels`, such as `batch-review: hello`. Use the controlling CronJob's name as the job ID in the BatchContour plan.

```sh
kubectl get jobs -n batch-demo -l batch-review=hello --field-selector status.successful=1 -o json > completed-jobs.json
moon run cmd/batchcontour --target wasm -- import-kubernetes completed-jobs.json candidate batch-demo > history.json
moon run cmd/batchcontour --target wasm -- replay-history examples/kubernetes/maintenance.json history.json candidate
```

The field selector in this command selects Jobs with one successful Pod. Adapt the selection to the workload and its completion count. Kubernetes may prune finished Jobs via CronJob history limits or the Job TTL, so export retained Jobs while the needed evidence is available. [Field selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/field-selectors/) · [Job status](https://kubernetes.io/docs/reference/kubernetes-api/batch/job-v1/#JobStatus)

To reproduce the case without a cluster, replace `completed-jobs.json` with `examples/kubernetes/completed-jobs.json`. The fixture is a synthetic Kubernetes list. The replay exits 2 and reports two worker slots occupied between 02:02:15Z and 02:02:45Z during a one-slot maintenance window. The output uses Job UIDs to identify the corresponding Kubernetes objects.

The importer accepts a Kubernetes `batch/v1 JobList` or a kubectl `v1 List` of `batch/v1 Job` items. It extracts `metadata.uid`, the controlling CronJob's name, `status.startTime` and `status.completionTime`. Other Kubernetes fields are outside this projection. Every item needs a single controlling `batch/v1 CronJob`, a true terminal `Complete` condition and whole-second UTC timestamps. Exports with duplicate Job UIDs, different controller UIDs for the same name, a continuation token, failed or unfinished Jobs, suspension history, or a different namespace fail without a partial history document. The controller may reset start time after suspension. [Kubernetes list behavior](https://kubernetes.io/docs/reference/using-api/api-concepts/) · [Kubernetes Job lifecycle](https://kubernetes.io/docs/concepts/workloads/controllers/job/)

Job timestamps describe controller-level elapsed time, including any retries or delay before a Pod runs. Replay applies the plan's declared resource quantity to the entire interval. Select your deployment cohort before exporting. The CLI emits a `batchcontour.history.v1` document with `min_samples` set to 1 by default. Pass `--min-samples 3` to require three samples per job in downstream coverage checks. Library callers can use `import_kubernetes_history(export, plan="candidate", namespace_name="batch-demo", min_samples=3)`.

## Capture a live fixture

The [capture workflow](../.github/workflows/kubernetes-capture.yml) starts a
disposable kind cluster and runs the [capture CronJob](../examples/kubernetes/capture-cronjob.yaml).
It waits for at least two successful Jobs, validates the export with the CLI,
and stores the original JSON as the `completed-kubernetes-jobs` artifact.

The [checked-in export](../examples/kubernetes/observed-jobs.json) comes from
two controller-created Jobs in that cluster. The controller recorded the
first run from 07:36:00Z to 07:37:25Z and the second from 07:37:00Z to 07:38:23Z
on November 26, 2026. [Capture run](https://github.com/cosettese/batchcontour/actions/runs/45776363623)

```sh
moon run cmd/batchcontour --target wasm -- import-kubernetes examples/kubernetes/observed-jobs.json candidate batchcontour-capture --min-samples 2 > observed-history.json
moon run cmd/batchcontour --target wasm -- replay-history examples/kubernetes/observed-replay-plan.json observed-history.json candidate
```

The replay plan assigns one modeled worker slot per run and a budget of one
slot. The CLI exits 2 and shows a 25-second overlap with both Job UIDs.
Both runs satisfy the sample threshold of two. Repeat with
`--min-samples 3` to see insufficient coverage alongside the overload.
