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
    buffer.write_bytes(chunk)
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
  #|       batchcontour scenarios INPUT.json SCENARIOS.json
  #|       batchcontour archive-review INPUT.json
  #|       batchcontour verify-evidence INPUT.json ARCHIVE.json
  #|       batchcontour verify-durations INPUT.json HISTORY.json
  #|       batchcontour propose-durations INPUT.json HISTORY.json

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
async fn gate_command(plan_path : String, policy_path : String) -> Int32 {
  let input = @capacity.ReviewInput::from_json(read_input(plan_path)) catch {
    error => raise FileError("\{plan_path}: \{error}")
  }
  let policy = @capacity.CapacityPolicy::from_json(read_input(policy_path)) catch {
    error => raise FileError("\{policy_path}: \{error}")
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
    ["gate", plan_path, policy_path] =>
      gate_command(plan_path, policy_path) catch {
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
