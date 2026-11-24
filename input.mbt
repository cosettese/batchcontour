///|
fn read_object(
  value : Json,
  allowed : ArrayView[String],
  path : String,
) -> Map[String, Json] raise ReviewError {
  guard value is Object(fields) else {
    raise InvalidInput(path~, detail="expected an object")
  }
  for key, _ in fields {
    guard allowed.contains(key) else {
      raise InvalidInput(
        path~,
        detail="unknown field " + Json::string(key).stringify(),
      )
    }
  }
  for key in allowed {
    guard fields.contains(key) else {
      raise InvalidInput(
        path=path + "." + key,
        detail="required field is missing",
      )
    }
  }
  fields
}

///|
fn read_string(value : Json, path : String) -> String raise ReviewError {
  guard value is String(text) else {
    raise InvalidInput(path~, detail="expected a string")
  }
  text
}

///|
fn read_id(value : Json, path : String) -> String raise ReviewError {
  let text = read_string(value, path)
  guard text.length() >= 1 && text.length() <= 64 else {
    raise InvalidInput(
      path~,
      detail="identifier must contain 1–64 ASCII letters, digits, underscores or hyphens",
    )
  }
  for ch in text {
    match ch {
      'a'..<='z' | 'A'..<='Z' | '0'..<='9' | '_' | '-' => ()
      _ =>
        raise InvalidInput(
          path~,
          detail="identifier must use ASCII letters, digits, underscores or hyphens",
        )
    }
  }
  text
}

///|
fn read_integer(
  value : Json,
  minimum : Int32,
  maximum : Int32,
  path : String,
) -> Int32 raise ReviewError {
  let detail = "expected an integer written in decimal digits (\{minimum}–\{maximum})"
  // parse() preserves the lexeme so a rounded Double cannot turn invalid
  // fractional or exponent notation into an accepted integer.
  guard value is Number(_, repr=Some(text)) && text.length() <= 7 else {
    raise InvalidInput(path~, detail~)
  }
  let mut number = 0
  for unit in text {
    guard unit >= '0' && unit <= '9' else { raise InvalidInput(path~, detail~) }
    number = number * 10 + unit.to_int() - 48
  }
  guard number >= minimum && number <= maximum else {
    raise InvalidInput(path~, detail~)
  }
  number
}

///|
fn read_capacities(
  value : Json,
  path~ : String = "$.capacities",
) -> Array[Capacity] raise ReviewError {
  guard value is Object(fields) &&
    !fields.is_empty() &&
    fields.length() <= max_resources else {
    raise InvalidInput(path~, detail="expected 1–32 named resources")
  }
  let result : Array[Capacity] = []
  for key, units in fields {
    let id = read_id(Json::string(key), path)
    result.push({
      resource: id,
      units: read_integer(units, 0, max_units, path + "." + id),
      overrides: [],
    })
  }
  result.sort_by((a, b) => a.resource[:].lexical_compare(b.resource[:]))
  result
}

///|
fn read_demands(
  value : Json,
  capacities : Array[Capacity],
  path : String,
) -> Array[Demand] raise ReviewError {
  guard value is Object(fields) && !fields.is_empty() else {
    raise InvalidInput(path~, detail="expected at least one resource demand")
  }
  let result : Array[Demand] = []
  for key, units in fields {
    guard capacities.search_by(capacity => capacity.resource == key)
      is Some(index) else {
      raise InvalidInput(
        path~,
        detail="no capacity declared for " + Json::string(key).stringify(),
      )
    }
    result.push({
      resource_index: index,
      units: read_integer(units, 1, max_units, path + "." + key),
    })
  }
  result.sort_by_key(demand => demand.resource_index)
  result
}

///|
fn read_jobs(
  value : Json,
  capacities : Array[Capacity],
  path : String,
) -> Array[Job] raise ReviewError {
  guard value is Array(items) && items.length() <= max_jobs else {
    raise InvalidInput(path~, detail="expected an array of at most 128 jobs")
  }
  let jobs : Array[Job] = []
  let seen : Map[String, Unit] = Map([])
  for index, item in items {
    let job_path = path + "[\{index}]"
    let fields = read_object(
      item,
      ["id", "cron", "min_minutes", "max_minutes", "demand"],
      job_path,
    )
    let id = read_id(fields["id"], job_path + ".id")
    guard !seen.contains(id) else {
      raise InvalidInput(path=job_path + ".id", detail="duplicate job ID " + id)
    }
    seen[id] = ()
    let expression = read_string(fields["cron"], job_path + ".cron")
    let cron = parse_schedule(expression, job_path + ".cron")
    let min_minutes = read_integer(
      fields["min_minutes"],
      1,
      max_duration_minutes,
      job_path + ".min_minutes",
    )
    let max_minutes = read_integer(
      fields["max_minutes"],
      min_minutes,
      max_duration_minutes,
      job_path + ".max_minutes",
    )
    let demands = read_demands(
      fields["demand"],
      capacities,
      job_path + ".demand",
    )
    jobs.push({ id, expression, cron, min_minutes, max_minutes, demands, })
  }
  // Job order has no semantic effect. Keep IDs stable for the sweep and output.
  jobs.sort_by((a, b) => a.id[:].lexical_compare(b.id[:]))
  jobs
}

///|
fn parse_document(text : String) -> Json raise ReviewError {
  guard text.length() <= max_input_units else {
    raise LimitExceeded(path="$", detail="input exceeds 1 Mi UTF-16 code units")
  }
  @json.parse(
    text[:],
    max_nesting_depth=8,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    error => raise InvalidInput(path="$", detail=error.to_string())
  }
}

///|
/// Decode and validate a v1 or v2 review. Unknown and duplicate keys fail.
pub fn ReviewInput::from_json(text : String) -> ReviewInput raise ReviewError {
  let value = parse_document(text)
  guard value is Object(root) else {
    raise InvalidInput(path="$", detail="expected an object")
  }
  let schema = match root.get("schema") {
    Some(String(name)) if name == input_schema || name == timed_input_schema =>
      name
    _ =>
      raise InvalidInput(
        path="$.schema",
        detail="expected " + input_schema + " or " + timed_input_schema,
      )
  }
  let fields = if schema == timed_input_schema {
    read_object(
      value,
      [
        "schema", "window", "capacities", "baseline", "candidate", "capacity_overrides",
      ],
      "$",
    )
  } else {
    read_object(
      value,
      ["schema", "window", "capacities", "baseline", "candidate"],
      "$",
    )
  }
  let window = read_object(fields["window"], ["start", "end"], "$.window")
  let start = parse_utc(
    read_string(window["start"], "$.window.start"),
    "$.window.start",
  )
  let end = parse_utc(
    read_string(window["end"], "$.window.end"),
    "$.window.end",
  )
  guard end > start && end - start <= max_window_minutes.to_int64() else {
    raise InvalidInput(
      path="$.window",
      detail="window must be positive and at most 31 days",
    )
  }
  let capacities = read_capacities(fields["capacities"])
  if schema == timed_input_schema {
    read_capacity_overrides(
      fields["capacity_overrides"],
      capacities,
      start,
      end,
    )
  }
  let baseline = read_jobs(fields["baseline"], capacities, "$.baseline")
  let candidate = read_jobs(fields["candidate"], capacities, "$.candidate")
  { schema, start, end, capacities, baseline, candidate, }
}

///|
fn job_json(job : Job, capacities : Array[Capacity]) -> Json {
  let demands : Map[String, Json] = Map([])
  for demand in job.demands {
    demands[capacities[demand.resource_index].resource] = Json::number(
      demand.units.to_double(),
    )
  }
  {
    "id": Json::string(job.id),
    "cron": Json::string(job.expression),
    "min_minutes": Json::number(job.min_minutes.to_double()),
    "max_minutes": Json::number(job.max_minutes.to_double()),
    "demand": Json::object(demands),
  }
}

///|
fn window_json(start : Int64, end : Int64) -> Json {
  { "start": Json::string(utc_text(start)), "end": Json::string(utc_text(end)) }
}

///|
/// Canonical serialization. The original cron expression text is preserved.
pub fn ReviewInput::to_json(self : ReviewInput) -> Json {
  let capacities : Map[String, Json] = Map([])
  for capacity in self.capacities {
    capacities[capacity.resource] = Json::number(capacity.units.to_double())
  }
  let fields : Map[String, Json] = {
    "schema": Json::string(self.schema),
    "window": window_json(self.start, self.end),
    "capacities": Json::object(capacities),
    "baseline": Json::array(
      self.baseline.map(job => job_json(job, self.capacities)),
    ),
    "candidate": Json::array(
      self.candidate.map(job => job_json(job, self.capacities)),
    ),
  }
  if self.schema == timed_input_schema {
    fields["capacity_overrides"] = overrides_json(self.capacities)
  }
  Json::object(fields)
}
