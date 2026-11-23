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
async fn read_input(path : String) -> String {
  let file = @fs.open(path, mode=ReadOnly) catch {
    _ => raise FileError("cannot open the input file")
  }
  defer file.close()
  guard file.kind() == @fs.Regular else {
    raise FileError("expected a regular UTF-8 file")
  }
  let max_bytes = 1_048_576
  guard file.size() <= max_bytes.to_int64() else {
    raise FileError("input file exceeds 1 MiB")
  }
  let buffer = @buffer.Buffer()
  while file.read() is Some(chunk) {
    guard chunk.length() <= max_bytes - buffer.length() else {
      raise FileError("input file exceeds 1 MiB")
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
async fn run(args : ArrayView[String]) -> Int32 {
  match args {
    ["--help"] => {
      @stdio.stdout.text.write(usage + "\n")
      0
    }
    ["review" | "summarize" as command, path] =>
      try {
        let input = @capacity.ReviewInput::from_json(read_input(path))
        let report = @capacity.compare_capacity(input)
        let output = if command == "summarize" {
          report.summary_json()
        } else {
          report.to_json()
        }
        @stdio.stdout.text.write(output.stringify() + "\n")
        if report.has_regressions() {
          2
        } else {
          0
        }
      } catch {
        error => {
          @stdio.stderr.text.write("batchcontour: \{path}: \{error}\n")
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
