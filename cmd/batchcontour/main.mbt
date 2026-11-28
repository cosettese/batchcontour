///|
priv suberror FileError {
  FileError(String)
}

///|
impl Show for FileError with fn output(self, logger) {
  let FileError(message) = self
  logger.write_string(message)
}

///|
async fn read_input(path : String, archive~ : Bool = false) -> String {
  let file = @fs.open(path, mode=ReadOnly) catch {
    _ => raise FileError("cannot open the input file")
  }
  defer file.close()
  guard file.kind() == @fs.Regular else {
    raise FileError("expected a regular UTF-8 file")
  }
  let max_bytes = if archive { 32 * 1024 * 1024 } else { 1_048_576 }
  let size_error = if archive {
    "archive file exceeds 32 MiB"
  } else {
    "input file exceeds 1 MiB"
  }
  guard file.size() <= max_bytes.to_int64() else { raise FileError(size_error) }
  let buffer = @buffer.Buffer()
  while file.read() is Some(chunk) {
    guard chunk.length() <= max_bytes - buffer.length() else {
      raise FileError(size_error)
    }
    buffer.write_bytesview(chunk)
  }
  @utf8.decode(buffer.to_bytes()) catch {
    _ => raise FileError("input is not valid UTF-8")
  }
}

///|
let usage =
  #|Usage: batchcontour review INPUT.json
  #|       batchcontour summarize INPUT.json
  #|       batchcontour gate INPUT.json POLICY.json
  #|       batchcontour archive-gate INPUT.json POLICY.json
  #|       batchcontour verify-gate-evidence INPUT.json POLICY.json ARCHIVE.json
  #|       batchcontour scenarios INPUT.json SCENARIOS.json
  #|       batchcontour repair INPUT.json OPTIONS.json [POLICY.json]
  #|       batchcontour archive-review INPUT.json
  #|       batchcontour verify-evidence INPUT.json ARCHIVE.json
  #|       batchcontour verify-durations INPUT.json HISTORY.json
  #|       batchcontour propose-durations INPUT.json HISTORY.json
  #|       batchcontour replay-history INPUT.json HISTORY.json baseline|candidate
  #|       batchcontour summarize-replay INPUT.json HISTORY.json baseline|candidate
  #|       batchcontour merge-history HISTORY.json HISTORY.json [...]
  #|       batchcontour import-kubernetes JOBS.json baseline|candidate NAMESPACE [--min-samples N]
  #|       batchcontour import-actions JOBS.json ALIASES.json baseline|candidate [--min-samples N]
  #|       batchcontour import-argo WORKFLOWS.json baseline|candidate NAMESPACE [--min-samples N]
  #|       batchcontour assemble BUDGET.json BASELINE.json CANDIDATE.json
  #|       batchcontour split INPUT.json

///|
async fn duration_command(
  command : String,
  plan_path : String,
  history_path : String,
) -> Int32 {
  let input = @capacity.ReviewInput::from_json(read_input(plan_path)) catch {
    error => raise FileError("\{plan_path}: \{error}")
  }
  let (document, exit_code) = try {
    let history = @capacity.RunHistory::from_json(read_input(history_path))
    if command == "propose-durations" {
      let proposal = @capacity.widen_duration_bounds(input, history)
      (proposal.to_json(), 0)
    } else {
      let report = @capacity.check_durations(input, history)
      (report.to_json(), if report.has_failures() { 2 } else { 0 })
    }
  } catch {
    error => raise FileError("\{history_path}: \{error}")
  }
  @stdio.stdout.text.write(document.stringify() + "\n")
  exit_code
}

///|
async fn gate_command(
  plan_path : String,
  policy_path : String,
  archive_output~ : Bool = false,
  evidence_path? : String,
) -> Int32 {
  let input = @capacity.ReviewInput::from_json(read_input(plan_path)) catch {
    error => raise FileError("\{plan_path}: \{error}")
  }
  let policy = @capacity.CapacityPolicy::from_json(read_input(policy_path)) catch {
    error => raise FileError("\{policy_path}: \{error}")
  }
  if evidence_path is Some(path) {
    let gate = @capacity.verify_gate_evidence(
      input,
      policy,
      read_input(path, archive=true),
    ) catch {
      error => raise FileError("\{path}: \{error}")
    }
    @stdio.stdout.text.write(gate.to_json().stringify() + "\n")
    return 0
  }
  if archive_output {
    let archive = @capacity.archive_capacity_gate(input, policy) catch {
      error => raise FileError("\{plan_path}, \{policy_path}: \{error}")
    }
    @stdio.stdout.text.write(archive.stringify() + "\n")
    return 0
  }
  let gate = @capacity.check_capacity_policy(input, policy) catch {
    error => raise FileError("\{plan_path}, \{policy_path}: \{error}")
  }
  @stdio.stdout.text.write(gate.to_json().stringify() + "\n")
  if gate.has_failures() {
    2
  } else {
    0
  }
}

///|
async fn repair_command(
  plan_path : String,
  options_path : String,
  policy_path? : String,
) -> Int32 {
  let input = @capacity.ReviewInput::from_json(read_input(plan_path)) catch {
    error => raise FileError("\{plan_path}: \{error}")
  }
  let options = read_input(options_path) catch {
    error => raise FileError("\{options_path}: \{error}")
  }
  let policy = match policy_path {
    Some(path) => {
      let policy = @capacity.CapacityPolicy::from_json(read_input(path)) catch {
        error => raise FileError("\{path}: \{error}")
      }
      Some(policy)
    }
    None => None
  }
  let report = try {
    match policy {
      Some(policy) =>
        @capacity.evaluate_launch_repairs_with_policy(input, options, policy)
      None => @capacity.evaluate_launch_repairs(input, options)
    }
  } catch {
    error => {
      let paths = match policy_path {
        Some(path) => options_path + ", " + path
        None => options_path
      }
      raise FileError("\{paths}: \{error}")
    }
  }
  @stdio.stdout.text.write(report.to_json().stringify() + "\n")
  if report.recommendation() is Some(_) {
    0
  } else {
    2
  }
}

///|
fn read_min_samples(arguments : ArrayView[String]) -> Int32 raise FileError {
  if arguments.is_empty() {
    return 1
  }
  let detail = "expected --min-samples with an integer from 1 to 4096"
  guard arguments is ["--min-samples", value] &&
    !value.is_empty() &&
    value.length() <= 4 else {
    raise FileError(detail)
  }
  let mut count = 0
  for ch in value {
    guard ch is ('0'..<='9') else { raise FileError(detail) }
    count = count * 10 + ch.to_int() - '0'.to_int()
  }
  guard count >= 1 && count <= 4096 else { raise FileError(detail) }
  count
}

///|
async fn merge_history_command(paths : ArrayView[String]) -> Int32 {
  guard paths.length() >= 2 && paths.length() <= 16 else {
    raise FileError("merge-history expects 2–16 input files")
  }
  let inputs : Array[@capacity.RunHistory] = []
  for path in paths {
    let history = @capacity.RunHistory::from_json(read_input(path)) catch {
      error => raise FileError("\{path}: \{error}")
    }
    inputs.push(history)
  }
  let history = @capacity.merge_run_histories(inputs[:])
  @stdio.stdout.text.write(history.to_json().stringify() + "\n")
  0
}

///|
async fn run(args : ArrayView[String]) -> Int32 {
  match args {
    ["--help"] => {
      @stdio.stdout.text.write(usage + "\n")
      0
    }
    ["review" | "summarize" | "archive-review" as command, path] =>
      try {
        let input = @capacity.ReviewInput::from_json(read_input(path))
        let (output, status) = if command == "archive-review" {
          (@capacity.archive_capacity_review(input), 0)
        } else {
          let report = @capacity.compare_capacity(input)
          let output = if command == "summarize" {
            report.summary_json()
          } else {
            report.to_json()
          }
          (output, if report.has_regressions() { 2 } else { 0 })
        }
        @stdio.stdout.text.write(output.stringify() + "\n")
        status
      } catch {
        error => {
          @stdio.stderr.text.write("batchcontour: \{path}: \{error}\n")
          1
        }
      }
    ["verify-evidence", plan_path, archive_path] =>
      try {
        let input = @capacity.ReviewInput::from_json(read_input(plan_path)) catch {
          error => raise FileError("\{plan_path}: \{error}")
        }
        let report = @capacity.verify_capacity_evidence(
          input,
          read_input(archive_path, archive=true),
        ) catch {
          error => raise FileError("\{archive_path}: \{error}")
        }
        @stdio.stdout.text.write(report.to_json().stringify() + "\n")
        0
      } catch {
        error => {
          @stdio.stderr.text.write("batchcontour: \{error}\n")
          1
        }
      }
    ["scenarios", plan_path, scenario_path] =>
      try {
        let input = @capacity.ReviewInput::from_json(read_input(plan_path)) catch {
          error => raise FileError("\{plan_path}: \{error}")
        }
        let report = @capacity.compare_capacity_scenarios(
          input,
          read_input(scenario_path),
        ) catch {
          error => raise FileError("\{scenario_path}: \{error}")
        }
        @stdio.stdout.text.write(report.to_json().stringify() + "\n")
        if report.has_regressions() {
          2
        } else {
          0
        }
      } catch {
        error => {
          @stdio.stderr.text.write("batchcontour: \{error}\n")
          1
        }
      }
    ["repair", plan_path, options_path, .. extra] => {
      let policy_path = match extra {
        [] => None
        [path] => Some(path)
        _ => {
          @stdio.stderr.text.write(usage + "\n")
          return 1
        }
      }
      repair_command(plan_path, options_path, policy_path?) catch {
        error => {
          @stdio.stderr.text.write("batchcontour: \{error}\n")
          1
        }
      }
    }
    ["assemble", budget, baseline, candidate] =>
      try {
        let budget_text = read_input(budget) catch {
          error => raise FileError("\{budget}: \{error}")
        }
        let baseline_text = read_input(baseline) catch {
          error => raise FileError("\{baseline}: \{error}")
        }
        let candidate_text = read_input(candidate) catch {
          error => raise FileError("\{candidate}: \{error}")
        }
        let review = @capacity.assemble_review(
          budget_text, baseline_text, candidate_text,
        )
        @stdio.stdout.text.write(review.to_json().stringify() + "\n")
        0
      } catch {
        error => {
          @stdio.stderr.text.write("batchcontour: \{error}\n")
          1
        }
      }
    ["split", path] =>
      try {
        let parts = @capacity.ReviewInput::from_json(read_input(path)).split_documents()
        let output : Json = {
          "budget": parts.budget,
          "baseline": parts.baseline,
          "candidate": parts.candidate,
        }
        @stdio.stdout.text.write(output.stringify() + "\n")
        0
      } catch {
        error => {
          @stdio.stderr.text.write("batchcontour: \{path}: \{error}\n")
          1
        }
      }
    ["merge-history", .. paths] =>
      merge_history_command(paths) catch {
        error => {
          @stdio.stderr.text.write("batchcontour: \{error}\n")
          1
        }
      }
    ["import-actions", path, aliases, plan, .. arguments] =>
      try {
        let min_samples = read_min_samples(arguments)
        let history = @capacity.import_actions_history(
          read_input(path),
          read_input(aliases),
          plan~,
          min_samples~,
        )
        @stdio.stdout.text.write(history.to_json().stringify() + "\n")
        0
      } catch {
        error => {
          @stdio.stderr.text.write(
            "batchcontour: \{path}, \{aliases}: \{error}\n",
          )
          1
        }
      }
    [
      "import-kubernetes"
      | "import-argo" as command,
      path,
      plan,
      namespace_name,
      .. arguments,
    ] =>
      try {
        let min_samples = read_min_samples(arguments)
        let input = read_input(path)
        let history = if command == "import-argo" {
          @capacity.import_argo_history(
            input,
            plan~,
            namespace_name~,
            min_samples~,
          )
        } else {
          @capacity.import_kubernetes_history(
            input,
            plan~,
            namespace_name~,
            min_samples~,
          )
        }
        @stdio.stdout.text.write(history.to_json().stringify() + "\n")
        0
      } catch {
        error => {
          @stdio.stderr.text.write("batchcontour: \{path}: \{error}\n")
          1
        }
      }
    [
      "replay-history"
      | "summarize-replay" as command,
      plan_path,
      history_path,
      plan,
    ] =>
      try {
        let input = @capacity.ReviewInput::from_json(read_input(plan_path)) catch {
          error => raise FileError("\{plan_path}: \{error}")
        }
        let report = @capacity.replay_history(
          input,
          @capacity.RunHistory::from_json(read_input(history_path)),
          plan,
        ) catch {
          error => raise FileError("\{history_path}: \{error}")
        }
        let output = if command == "summarize-replay" {
          report.summary_json()
        } else {
          report.to_json()
        }
        @stdio.stdout.text.write(output.stringify() + "\n")
        if report.has_failures() {
          2
        } else {
          0
        }
      } catch {
        error => {
          @stdio.stderr.text.write("batchcontour: \{error}\n")
          1
        }
      }
    ["gate" | "archive-gate" as command, plan_path, policy_path] =>
      gate_command(
        plan_path,
        policy_path,
        archive_output=command == "archive-gate",
      ) catch {
        error => {
          @stdio.stderr.text.write("batchcontour: \{error}\n")
          1
        }
      }
    ["verify-gate-evidence", plan_path, policy_path, evidence_path] =>
      gate_command(plan_path, policy_path, evidence_path~) catch {
        error => {
          @stdio.stderr.text.write("batchcontour: \{error}\n")
          1
        }
      }
    [
      "verify-durations"
      | "propose-durations" as command,
      plan_path,
      history_path,
    ] =>
      duration_command(command, plan_path, history_path) catch {
        error => {
          @stdio.stderr.text.write("batchcontour: \{error}\n")
          1
        }
      }
    _ => {
      @stdio.stderr.text.write(usage + "\n")
      1
    }
  }
}

///|
async fn main {
  let args = @env.args()
  let code = run(args[1:])
  if code != 0 {
    @env.exit(code)
  }
}
