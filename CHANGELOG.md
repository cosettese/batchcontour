# Changelog

## 0.22.0

- Import completed Argo CronWorkflow history and verify replay against a documented fixture.

## 0.21.0

- Import GitHub Actions jobs with explicit name mapping and exact numeric identities.

## 0.20.0

- Merge repeated history exports without double-counting runs or combining conflicting observations.

## 0.19.0

- Summarize observed overload seconds, peak shortfall, and accumulated shortfall by resource.

## 0.18.2

- Use the current byte-view API when reading CLI input files with MoonBit 1.0 RC1.

## 0.18.1

- Keep the JSON input and evidence nesting limits with the current MoonBit stable API.

## 0.18.0

- Export a versioned source ZIP and SHA-256 manifest after testing the unpacked archive and an isolated downstream module.
- Document the independent acceptance command for the exported package.

## 0.17.0

- Add an explicit sample threshold to the Kubernetes history CLI.
- Capture successful CronJob runs in a disposable Kubernetes cluster and validate the export before saving it.
- Include the actual Job export and an offline replay that verifies the 25-second overlap.

## 0.16.0

- Apply the release policy to each schedule repair that preserves launch counts.
- Report the limit and actual measurement for every policy violation.

## 0.15.0

- Include the normalized inputs, policy and detailed capacity report in policy-gated PR evidence.
- Verify archived gate results offline against trusted inputs.

## 0.14.1 and earlier

- Compare baseline and candidate schedules with fixed and time-varying resource budgets.
- Model one-time launches and cancellations, screen schedule repairs and replay completed runs.
- Assemble independently versioned plans and run capacity reviews as a GitHub PR check.
