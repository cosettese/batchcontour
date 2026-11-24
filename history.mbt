///|
let history_schema = "batchcontour.history.v1"

///|
let max_history_runs = 4096

///|
priv struct Observation {
  plan : String
  job_id : String
  run_id : String
  started_at : String
  finished_at : String
  start_second : Int64
  elapsed_seconds : Int64
  source_index : Int32
}

///|
/// Validated, version-labelled completed runtime observations.
struct RunHistory {
  min_samples : Int32
  runs : Array[Observation]
}

///|
fn read_observation(
  value : Json,
  index : Int32,
) -> Observation raise ReviewError {
  let path = "$.runs[\{index}]"
  let fields = read_object(
    value,
    ["plan", "job", "id", "started_at", "finished_at"],
    path,
  )
  let plan = read_string(fields["plan"], path + ".plan")
  guard plan == "baseline" || plan == "candidate" else {
    raise InvalidInput(
      path=path + ".plan",
      detail="expected baseline or candidate",
    )
  }
  let job_id = read_id(fields["job"], path + ".job")
  let run_id = read_id(fields["id"], path + ".id")
  let started_at = read_string(fields["started_at"], path + ".started_at")
  let finished_at = read_string(fields["finished_at"], path + ".finished_at")
  let start = parse_utc_timestamp(
    started_at,
    path + ".started_at",
    minute_aligned=false,
  )
  let end = parse_utc_timestamp(
    finished_at,
    path + ".finished_at",
    minute_aligned=false,
  )
  guard start <= end else {
    raise InvalidInput(
      path=path + ".finished_at",
      detail="finish precedes start",
    )
  }
  {
    plan,
    job_id,
    run_id,
    started_at,
    finished_at,
    start_second: start,
    elapsed_seconds: end - start,
    source_index: index,
  }
}

///|
/// Parse completed runs and reject ambiguous or duplicate records.
pub fn RunHistory::from_json(text : String) -> RunHistory raise ReviewError {
  let fields = read_object(
    parse_document(text),
    ["schema", "min_samples", "runs"],
    "$",
  )
  guard read_string(fields["schema"], "$.schema") == history_schema else {
    raise InvalidInput(path="$.schema", detail="expected " + history_schema)
  }
  let min_samples = read_integer(
    fields["min_samples"],
    1,
    max_history_runs,
    "$.min_samples",
  )
  guard fields["runs"] is Array(values) else {
    raise InvalidInput(
      path="$.runs",
      detail="expected an array of observations",
    )
  }
  guard values.length() <= max_history_runs else {
    raise LimitExceeded(path="$.runs", detail="expected at most 4,096 runs")
  }
  let seen : Map[(String, String), Unit] = Map([])
  let runs : Array[Observation] = []
  for index, value in values {
    let run = read_observation(value, index)
    let identity = (run.plan, run.run_id)
    guard !seen.contains(identity) else {
      raise InvalidInput(
        path="$.runs[\{index}].id",
        detail="duplicate run ID within " + run.plan,
      )
    }
    seen[identity] = ()
    runs.push(run)
  }
  runs.sort_by((a, b) => {
    let side_order = a.plan[:].lexical_compare(b.plan[:])
    if side_order == 0 {
      a.run_id[:].lexical_compare(b.run_id[:])
    } else {
      side_order
    }
  })
  { min_samples, runs, }
}

///|
/// Canonical serialization preserves all accepted observations and their times.
pub fn RunHistory::to_json(self : RunHistory) -> Json {
  let runs = self.runs.map(run => {
    let value : Json = {
      "plan": Json::string(run.plan),
      "job": Json::string(run.job_id),
      "id": Json::string(run.run_id),
      "started_at": Json::string(run.started_at),
      "finished_at": Json::string(run.finished_at),
    }
    value
  })
  {
    "schema": Json::string(history_schema),
    "min_samples": Json::number(self.min_samples.to_double()),
    "runs": Json::array(runs),
  }
}
