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
let usage = "Usage: batchcontour review INPUT.json"

///|
async fn run(args : ArrayView[String]) -> Int32 {
  match args {
    ["--help"] => {
      @stdio.stdout.text.write(usage + "\n")
      0
    }
    ["review", path] =>
      try {
        let input = @capacity.ReviewInput::from_json(read_input(path))
        let report = @capacity.compare_capacity(input)
        @stdio.stdout.text.write(report.to_json().stringify() + "\n")
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
