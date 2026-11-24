# 叠峰 · BatchContour

叠峰帮助维护定时批任务的平台工程师，在合并排程改动前发现共享资源超载。把当前排程、候选排程、每次运行的时长范围和资源用量放进一份文件，工具就能指出数据库连接、GPU 或工作槽位在哪些时段会新增短缺，并列出当时可能仍在运行的任务。

例如，备份 02:00 启动并占 7 个连接，报表 02:20 启动并占 5 个连接。池容量为 10 时，两者虽然错开启动，只要备份还没结束就会超载。时长范围使报告能区分在哪些分钟一定超载，哪些分钟只有任务跑得较久时才会超载。

## 运行公开示例

安装当前稳定版 MoonBit 后，从仓库根目录运行。开发验证使用 `moonc v0.10.22+124d61d05`。

```sh
moon run cmd/batchcontour --target wasm -- review examples/kubernetes/blocked.json
moon run cmd/batchcontour --target wasm -- review examples/kubernetes/repaired.json
```

第一条命令退出码为 **2**。候选排程使 Kubernetes 官方示例任务 `hello` 的上一次运行可能仍占 1 个槽位。02:01 至 02:03 期间，资源占用从基线的 3 个变成候选的 3–4 个，对容量 3 产生最多 1 个槽位的缺口。第二条命令把 `hello` 改为每 5 分钟启动一次，退出码为 **0**。样例无须部署集群。[样例来源与手算](examples/kubernetes/README.md)

| 退出码 | CI 如何解释 |
|---|---|
| 0 | 审查完成且无容量回归，报告仍包含已有超载 |
| 2 | 审查完成且发现新增或加重的容量缺口 |
| 1 | 文件、格式、输入约束或分析规模有误，诊断写入标准错误 |

退出码为 0 或 2 时，标准输出是一份完整的 JSON 报告。

维护期间容量会变化时，可以用 v2 文件为任意资源声明临时容量。下例的工作槽位平时为 2，02:02 至 02:04 降为 1。报告只会在这段时间指出候选排程的超载风险。

```sh
moon run cmd/batchcontour --target wasm -- review examples/kubernetes/maintenance.json
```

CI 日志可以用 `summarize` 查看每种资源的超载分钟数、峰值缺口和累计缺口。维护示例会显示该资源有 2 分钟回归，候选的累计缺口上界为 2 槽位·分钟。

```sh
moon run cmd/batchcontour --target wasm -- summarize examples/kubernetes/maintenance.json
```

资源有硬性限制时，可以在回归检查之外配置绝对容量门禁。示例的新旧排程相同，但候选有 2 分钟可能超载，超过策略允许的 1 分钟，因此退出 **2**。 [容量门禁](docs/capacity-policy.md)

```sh
moon run cmd/batchcontour --target wasm -- gate examples/kubernetes/existing-overload.json examples/kubernetes/strict-policy.json
```

提交排程前也可以核对历史时长。下例里候选任务 `can-2` 运行了 143 秒，超过声明的 120 秒上限，命令退出 **2**。报告还会标出缺乏足够样本的任务。[时长记录格式与用法](docs/duration-evidence.md)

```sh
moon run cmd/batchcontour --target wasm -- verify-durations examples/kubernetes/maintenance.json examples/kubernetes/runtime-outlier.json
```

样本足够时，可以用 `propose-durations` 生成一份更新后的排程文件。示例中候选任务的上限会从 2 分钟扩到 3 分钟，生成的文件可以直接交给容量审查。 [提案流程](docs/duration-evidence.md#propose-wider-bounds)

## 在 MoonBit 项目中使用

`cosettese/batchcontour` 提供可从源码接入的库。把此模块和下游模块加入同一 `moon.work`，在下游 `moon.mod` 引用版本 `0.8.1`，并在 `moon.pkg` 导入 `cosettese/batchcontour`。

```moonbit
let input = @batchcontour.ReviewInput::from_json(request_text)
let report = @batchcontour.compare_capacity(input)
let findings = report.findings()
let blocked = report.has_regressions()
let report_text = report.to_json().stringify()
```

库提供版本化输入往返和只读发现视图。输入与报告字段、UTC cron 子集、分析限制和门禁公式见 [格式与语义](docs/format.md)，可执行的库用法见 [快速上手](quickstart.mbt.md)。

需要留存审查依据时，可用 `archive-review` 保存输入与完整结论。复核者用 `verify-evidence` 对照可信排程重新计算，检查结论及每条任务证据。 [归档与复核](docs/review-evidence.md)

在同一份排程上可用 `scenarios` 对照多套容量预算，例如正常与维护降容。每个情景都有独立结论和缺口汇总。 [多情景示例](docs/scenarios.md)

## 验证

```sh
moon run scripts/verify.mbtx portable
moon run scripts/verify.mbtx all
```

`portable` 执行 Wasm、Wasm-GC、JavaScript 库测试和 Wasm 文件流程。`all` 还实际运行 Native 库测试和 CLI，并要求两种 CLI 输出一致。JavaScript 测试需要 Node，Native 需要受支持的 C 工具链。GitHub Actions 在 Linux、macOS、Windows 上执行 `all` 并检查生成接口。逐分钟参考实现独立核对 60 组排程和容量，另有边界、往返、确定性及失败恢复测试。

发行 ZIP 也有独立验证入口。它解包后用全新的下游模块实际调用公开 API，并输出验证过的归档 SHA-256。 [发行包验证](docs/distribution.md)

当前版本支持固定和分时容量预算，以及历史时长证据核对。[设计与生态对比](docs/design.md) 记录了可采用的场景、已有方案的接口边界和后续迭代。[来源与许可证](SOURCES.md) 记录了依赖和样例出处。本项目采用 Apache-2.0。
