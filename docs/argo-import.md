# Replay Argo CronWorkflow history

Export Workflow objects for one namespace and deployment cohort. Restrict the
export to terminal workflows so the run has both start and finish timestamps.
The importer reads the CronWorkflow label as the BatchContour job ID and the
Workflow UID as the run ID. [Argo fields](https://argo-workflows.readthedocs.io/en/latest/fields/) · [CronWorkflow label](https://github.com/argoproj/argo-workflows/blob/main/workflow/common/common.go)

```sh
kubectl get workflows.argoproj.io -n demo -l 'workflows.argoproj.io/cron-workflow=nightly,workflows.argoproj.io/completed=true' -o json > workflows.json
moon run cmd/batchcontour --target wasm -- import-argo examples/argo/workflows.json candidate demo --min-samples 2 > argo-history.json
moon run cmd/batchcontour --target wasm -- summarize-replay examples/argo/replay-plan.json argo-history.json candidate
```

Use `workflows.json` in place of the example export for your own workloads
and supply a replay plan that matches their window and job IDs. The example
uses synthetic Workflow rows. One successful and one failed Workflow held
their modeled slots for 21 overlapping seconds. Both count toward coverage.

The importer accepts a complete kubectl `v1 List` or Argo
`argoproj.io/v1alpha1 WorkflowList`. It accepts Succeeded, Failed and Error
with whole-second UTC endpoints. It reports incomplete pagination, mixed
namespaces, missing labels, duplicate UIDs and unsupported states. Resource
use comes from the replay plan and applies for the complete Workflow interval.
