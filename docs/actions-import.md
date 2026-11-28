# Replay GitHub Actions job history

Export the response from GitHub's list-jobs endpoint. For runs that fit a
single page, use `gh api repos/OWNER/REPO/actions/runs/RUN_ID/jobs?per_page=100`.
For larger runs, collect the jobs from every page into one response while
preserving `total_count`. Use a run-attempt endpoint when analyzing a specific
retry. Provide a JSON object mapping each exact job name to a unique BatchContour
job ID. [GitHub Actions jobs API](https://docs.github.com/en/rest/actions/workflow-jobs)

```sh
moon run cmd/batchcontour --target wasm -- import-actions examples/actions/jobs.json examples/actions/job-map.json candidate > actions-history.json
moon run cmd/batchcontour --target wasm -- summarize-replay examples/actions/replay-plan.json actions-history.json candidate
```

The sample retains the relevant fields from a successful PR integration job
in this repository. The illustrative replay budget shows 32 seconds of
shortfall. Completed jobs with success or failure and whole-second UTC
timestamps are supported. Skipped jobs, incomplete pages, duplicate job
IDs and unmapped names fail with diagnostics. Import each deployment cohort
separately and pass `--min-samples N` to configure coverage checks.
The import uses elapsed job time and leaves resource demand to the replay plan.
[Source run](https://github.com/cosettese/batchcontour/actions/runs/46075771400)
