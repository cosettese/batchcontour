///|
fn history_field(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise ReviewError {
  read_string(fields.get(key).unwrap_or(Json::null()), path + "." + key)
}

///|
fn history_object(
  value : Json?,
  path : String,
) -> Map[String, Json] raise ReviewError {
  guard value is Some(Object(fields)) else {
    raise InvalidInput(path~, detail="expected an object")
  }
  fields
}

///|
fn imported_observation(
  plan : String,
  job_id : String,
  run_id : String,
  index : Int32,
  fields : Map[String, Json],
  path : String,
  start_key : String,
  end_key : String,
) -> Observation raise ReviewError {
  let started_at = history_field(fields, start_key, path)
  let finished_at = history_field(fields, end_key, path)
  let (start_second, elapsed_seconds) = history_times(
    started_at,
    finished_at,
    path + "." + start_key,
    path + "." + end_key,
  )
  {
    plan,
    job_id,
    run_id,
    source_index: index,
    started_at,
    finished_at,
    start_second,
    elapsed_seconds,
  }
}

///|
fn validate_import_context(
  plan : String,
  min_samples : Int32,
) -> Unit raise ReviewError {
  guard plan == "baseline" || plan == "candidate" else {
    raise InvalidInput(path="plan", detail="expected baseline or candidate")
  }
  guard min_samples >= 1 && min_samples <= max_history_runs else {
    raise InvalidInput(path="min_samples", detail="expected 1–4,096 samples")
  }
}

///|
/// Project a complete GitHub Actions jobs response using explicit name aliases.
pub fn import_actions_history(
  text : String,
  aliases : String,
  plan~ : String,
  min_samples~ : Int32 = 1,
) -> RunHistory raise ReviewError {
  validate_import_context(plan, min_samples)
  let mapping = history_object(Some(parse_document(aliases)), "$.aliases")
  let names : Map[String, String] = Map([])
  let used_aliases : Map[String, Unit] = Map([])
  for name, value in mapping {
    let job_id = read_id(value, "$.aliases." + name)
    guard !name.is_empty() && !used_aliases.contains(job_id) else {
      raise InvalidInput(
        path="$.aliases",
        detail="expected nonempty job names and unique aliases",
      )
    }
    names[name] = job_id
    used_aliases[job_id] = ()
  }
  let root = history_object(Some(parse_document(text, max_depth=48)), "$")
  guard root.get("jobs") is Some(Array(jobs)) else {
    raise InvalidInput(path="$.jobs", detail="expected a jobs array")
  }
  let total = read_integer(
    root.get("total_count").unwrap_or(Json::null()),
    0,
    max_history_runs,
    "$.total_count",
  )
  guard jobs.length() == total else {
    raise InvalidInput(
      path="$.jobs",
      detail="incomplete response: collect all pages before import",
    )
  }
  let seen : Map[String, Unit] = Map([])
  let runs : Array[Observation] = []
  for index, job in jobs {
    let path = "$.jobs[\{index}]"
    let fields = history_object(Some(job), path)
    let name = history_field(fields, "name", path)
    guard names.get(name) is Some(job_id) else {
      raise InvalidInput(
        path=path + ".name",
        detail="missing BatchContour alias for " + name,
      )
    }
    guard fields.get("status") is Some(String("completed")) &&
      fields.get("conclusion") is Some(String("success" | "failure")) else {
      raise InvalidInput(
        path=path + ".conclusion",
        detail="expected a completed job with success or failure",
      )
    }
    guard fields.get("id") is Some(Number(_, repr=Some(id))) &&
      id.length() >= 1 &&
      id.length() <= 64 &&
      !id.has_prefix("0") &&
      id[:].iter().all(ch => ch is ('0'..<='9')) &&
      !seen.contains(id) else {
      raise InvalidInput(
        path=path + ".id",
        detail="expected a unique positive decimal job ID",
      )
    }
    seen[id] = ()
    runs.push(
      imported_observation(
        plan, job_id, id, index, fields, path, "started_at", "completed_at",
      ),
    )
  }
  let history = normalized_history(min_samples, runs)
  guard history.to_json().stringify().length() < max_input_units else {
    raise LimitExceeded(
      path="$.jobs",
      detail="normalized history exceeds the supported JSON size",
    )
  }
  history
}
