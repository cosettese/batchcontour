# Sources and licenses

| Source | Use | License |
|---|---|---|
| [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0) | Standard text in `LICENSE` | Apache-2.0 |
| [MoonDate 0.2.1](https://mooncakes.io/docs/moonbitstack/moondate%400.2.1) | Direct dependency for UTC calendars and cron matching. Its registry manifest depends on `moonbitlang/x@0.5.7`. | Apache-2.0 ([MoonDate](https://github.com/moonbitstack/moondate/blob/master/LICENSE), [moonbitlang/x](https://github.com/moonbitlang/x/blob/main/LICENSE)) |
| [MoonBit core](https://github.com/moonbitlang/core) | Runtime library, strict JSON and CLI file I/O. | Apache-2.0 |
| [moonbitlang/async 0.22.10](https://mooncakes.io/docs/moonbitlang/async%400.22.10) | Standalone verification script dependency. | Apache-2.0 |
| [moonbitlang/x 0.5.7](https://mooncakes.io/docs/moonbitlang/x%400.5.7) | Computes an archive SHA-256 in the standalone verification script. | Apache-2.0 |
| [Kubernetes examples](https://github.com/kubernetes/website/blob/main/content/en/examples/application/job/cronjob.yaml) | The `hello` job name and `* * * * *` expression. No job image, command, or full manifest is bundled. | Apache-2.0 for sample code ([upstream code license](https://github.com/kubernetes/website/blob/main/LICENSE)) |
| [Kubernetes Job API](https://kubernetes.io/docs/reference/kubernetes-api/batch/job-v1/#JobStatus) | Reference for the semantics of exported start and completion timestamps. The synthetic history fixtures use authored timestamps and run IDs. | Kubernetes documentation, CC BY 4.0 ([upstream policy](https://github.com/kubernetes/website/blob/main/LICENSE)) |
| [Kubernetes API conventions for lists](https://kubernetes.io/docs/reference/using-api/api-concepts/) | Reference for the synthetic Job list fixture and supported collection shapes. | Kubernetes documentation, CC BY 4.0 ([upstream policy](https://github.com/kubernetes/website/blob/main/LICENSE)) |
| [actions/upload-artifact](https://github.com/actions/upload-artifact/tree/cf430e030ddbb5b0abf93d22962f4752f3646cd9) | Saves JSON review reports in the CI integration test. | MIT ([license](https://github.com/actions/upload-artifact/blob/cf430e030ddbb5b0abf93d22962f4752f3646cd9/LICENSE)) |
| [helm/kind-action v1.15.2](https://github.com/helm/kind-action/tree/ea822c7bf1874f08e5a491df991c228edffc3376) | Creates a disposable Kubernetes cluster for actual Job exports. | Apache-2.0 ([license](https://github.com/helm/kind-action/blob/ea822c7bf1874f08e5a491df991c228edffc3376/LICENSE)) |
| [BatchContour capture run](https://github.com/cosettese/batchcontour/actions/runs/45776363623) | `observed-jobs.json` is a kubectl export from the repository's disposable kind cluster. Its timestamps and Job UIDs are the observed controller values. The replay budget is illustrative. | Apache-2.0 (fixture distributed with this repository) |

Other fixtures, test expectations, duration and demand values are written for
this repository. The reference minute simulation and the production interval
sweep are separate local implementations. Ecosystem projects in the design
notes and product documentation were consulted for comparison.

The [Actions job fixture](examples/actions/jobs.json) retains job metadata
from this repository's [PR integration run](https://github.com/cosettese/batchcontour/actions/runs/46075771400).
It is distributed here under Apache-2.0. The replay budget is illustrative.

The Argo fixture is authored for this repository under Apache-2.0. It follows
the documented Workflow status and CronWorkflow label.
[Argo field reference](https://argo-workflows.readthedocs.io/en/latest/fields/) · [Argo source](https://github.com/argoproj/argo-workflows/blob/main/workflow/common/common.go)
