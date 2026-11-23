# Sources and licenses

| Source | Use | License |
|---|---|---|
| [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0) | Standard text in `LICENSE` | Apache-2.0 |
| [MoonDate 0.2.1](https://mooncakes.io/docs/moonbitstack/moondate%400.2.1) | Direct dependency for UTC calendars and cron matching. Its registry manifest depends on `moonbitlang/x@0.5.7`. | Apache-2.0 ([MoonDate](https://github.com/moonbitstack/moondate/blob/master/LICENSE), [moonbitlang/x](https://github.com/moonbitlang/x/blob/main/LICENSE)) |
| [MoonBit core](https://github.com/moonbitlang/core) | Runtime library, strict JSON and CLI file I/O. | Apache-2.0 |
| [moonbitlang/async 0.22.10](https://mooncakes.io/docs/moonbitlang/async%400.22.10) | Standalone verification script dependency. | Apache-2.0 |
| [Kubernetes examples](https://github.com/kubernetes/website/blob/main/content/en/examples/application/job/cronjob.yaml) | The `hello` job name and `* * * * *` expression. No job image, command, or full manifest is bundled. | Apache-2.0 for sample code ([upstream code license](https://github.com/kubernetes/website/blob/main/LICENSE)) |

Other fixtures, test expectations, duration and demand values are written for
this repository. The reference minute simulation and the production interval
sweep are separate local implementations. Ecosystem projects in the design
notes and product documentation were consulted for comparison.
