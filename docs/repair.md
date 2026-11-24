# Screen candidate schedule changes

Use `repair` when a capacity review blocks a schedule change and the job owner can propose acceptable alternative cron expressions. Provide one candidate job ID and between one and eight options in preference order.

```sh
moon run cmd/batchcontour --target wasm -- repair examples/kubernetes/repair-input.json examples/kubernetes/repair-options.json
```

The options document uses schema `batchcontour.launch-repairs.v1`. Each option has a unique `id` and a `cron` expression in the same UTC subset as the review input. The example models a snapshot that occupies both worker slots from 02:01 to 02:03. `keep` overlaps the snapshot, `after-window` drops the required launch from the window, and `after-snapshot` performs the launch after the snapshot releases its slots. The snapshot, resource quantities, and window are illustrative.

The report includes an ordered result for each option. An option that changes the number of effective launches in the half-open review window gets status `launch_count_changed`. Explicit launch overrides apply to both counts. Options that preserve the count run the full capacity comparison, including any runs that carry into the window. The first option without a regression is recommended. The original candidate job must have at least one effective launch in the window.

The command exits **0** when it recommends an option and **2** when all options are ruled out. Both produce a complete JSON report. Format and analysis errors exit **1** and give a diagnostic. The recommended `proposal` can be saved as a standalone input for `review` or an absolute capacity `gate`. For a new observation window, repeat the evaluation with the relevant dates and budgets.

The library exposes the same workflow through `evaluate_launch_repairs(input, options_json)`. Use `results()` to read the option decisions and `recommendation()` to retrieve the optional pair of option ID and updated `ReviewInput`.
