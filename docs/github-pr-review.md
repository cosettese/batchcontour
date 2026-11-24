# Gate schedule changes on GitHub

Store a [budget and schedule](review-documents.md) as separate JSON files in the target branch. The action reads the budget, optional absolute policy, and baseline schedule from the PR base commit. It reads the candidate schedule from the proposed merge commit. Budget or policy edits in the PR take effect in later reviews after they reach the base branch.

In `.github/workflows/capacity.yml`, use a full commit hash for `BATCHCONTOUR_COMMIT_SHA` from a revision containing this action:

```yaml
name: Capacity review
on: pull_request
permissions:
  contents: read
jobs:
  capacity:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6
        with:
          fetch-depth: 0
          persist-credentials: false
      - uses: cosettese/batchcontour/.github/actions/review@BATCHCONTOUR_COMMIT_SHA
        with:
          base-sha: ${{ github.event.pull_request.base.sha }}
          candidate-sha: ${{ github.sha }}
          budget-path: ops/budget.json
          plan-path: ops/plan.json
          report-path: ${{ runner.temp }}/capacity-review.json
      - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7
        if: ${{ !cancelled() }}
        with:
          name: capacity-review
          path: ${{ runner.temp }}/capacity-review.json
          if-no-files-found: ignore
```

Use the `capacity` job as a required check if your repository gates merges. The `pull_request` event supplies the synthetic merge commit, so base-branch changes are included in the candidate. The full fetch keeps both Git objects available. Use read-only permissions and keep the caller workflow under the review rules of your repository. [GitHub PR event and merge commit](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#pull_request) · [Composite action metadata](https://docs.github.com/en/actions/reference/workflows-and-actions/metadata-syntax)

`policy-path` optionally adds an [absolute overload policy](capacity-policy.md) from the base commit. `candidate-plan-path` handles a plan moved in the proposed revision. The action extracts JSON blobs by hash and path, and runs the MoonBit CLI from the action checkout. It produces a `batchcontour.pr-review.v1` document recording both commits, file paths, verdict and JSON findings or policy results. A capacity failure exits 2 and leaves the report for upload. Invalid inputs fail before the report is created. Set the report path to a new file for each invocation.

The integration is exercised on a GitHub-hosted Linux runner. Run the commit-isolation check locally with Git and MoonBit. It creates a temporary repository, stages a schedule change with budget and policy edits, and verifies that the review still uses the base controls and ignores working-tree edits.

```sh
moon run --deny-warn scripts/verify-pr-review.mbtx
```
