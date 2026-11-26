# Verify the packaged library in a downstream module

Run from the repository root.

```sh
moon run --deny-warn scripts/verify-distribution.mbtx portable
moon run --deny-warn scripts/verify-distribution.mbtx all
```

The script builds an actual ZIP with `moon package`, checks its member list
for required source, license, interface and example files, and refuses
unexpected development state or invalid member paths. It extracts that ZIP
into a fresh temporary workspace alongside a separate consumer module.
The library under test comes from the archive. The consumer imports
`cosettese/batchcontour` by its public path and uses only its exported API.

The three consumer tests cover creating and verifying a capacity review
archive, applying a release policy, reviewing a new schedule after a
historical duration proposal, and replaying completed runs. They use the public
Kubernetes example cron with synthetic capacities, demands and history. The
script requires all three tests to execute on each requested backend. It
prints the archive member count and SHA-256 before removing the workspace.

`portable` tests Wasm, Wasm-GC and JavaScript. `all` also builds and runs
the Native consumer with a compatible C toolchain. Extraction uses
`tar` on Windows and `unzip` on Linux/macOS. Standard dependencies may
resolve from the configured Mooncakes index or cache. The test installs
the BatchContour library from the locally built archive.

The source package excludes the development consumer, workspaces and
local build/dependency caches using `.moonignore`. The [consumer source](https://github.com/cosettese/batchcontour/tree/main/integration/consumer)
shows the dependency and import declarations.

## Download and verify a versioned bundle

Download the `batchcontour-source-bundle` artifact from the completed bundle
workflow for the revision you want to evaluate. [Bundle workflow runs](https://github.com/cosettese/batchcontour/actions/workflows/release-bundle.yml)
The artifact contains
`batchcontour-v0.18.0-source.zip` and `SHA256SUMS` for version 0.18.0.

Place the two files in an empty directory. On Linux, verify the ZIP with
`sha256sum -c SHA256SUMS`. On macOS use `shasum -a 256 -c SHA256SUMS`.
On Windows compare `Get-FileHash .\batchcontour-v0.18.0-source.zip -Algorithm SHA256`
with the value in `SHA256SUMS`.

Extract the ZIP into a new directory and run the acceptance command there.
With MoonBit and Node on the path, it checks the generated interfaces,
runs the portable test suite, and exercises the file-based CLI examples.

```sh
moon run --deny-warn scripts/verify.mbtx portable
```

To generate the verified bundle from a source checkout, pass an existing
output directory outside the checkout to the distribution check.

```sh
moon run --deny-warn scripts/verify-distribution.mbtx all --export /path/to/bundle
```

The bundle workflow uses all four backends for downstream tests. An
invocation on a Git tag also checks that the tag matches the packaged version.
