///|
let repairs_schema = "batchcontour.launch-repairs.v1"

///|
priv struct RepairOption {
  id : String
  expression : String
  cron : @cron.Cron
}

///|
/// Outcome for one operator-provided schedule option.
pub struct RepairResult {
  id : String
  launch_count : Int32
  regression_count : Int32?
}

///|
/// Evaluation in priority order and the first viable review input, if any.
struct RepairReport {
  job_id : String
  required_launches : Int32
  results : Array[RepairResult]
  recommendation : (String, ReviewInput)?
  policy : CapacityPolicy?
  violations : Map[String, Array[CapacityViolation]]
}

///|
pub fn RepairReport::recommendation(
  self : RepairReport,
) -> (String, ReviewInput)? {
  self.recommendation
}

///|
pub fn RepairReport::results(self : RepairReport) -> ArrayView[RepairResult] {
  self.results[:]
}

///|
/// Return the absolute violations for a policy-checked option.
/// An empty view means the option met the ceilings.
pub fn RepairReport::policy_violations(
  self : RepairReport,
  option_id : String,
) -> ArrayView[CapacityViolation]? {
  self.violations.get(option_id).map(entries => entries[:])
}

///|
fn read_repair_options(value : Json) -> Array[RepairOption] raise ReviewError {
  guard value is Array(entries) && !entries.is_empty() && entries.length() <= 8 else {
    raise InvalidInput(
      path="$.options",
      detail="expected 1–8 schedule options",
    )
  }
  let options : Array[RepairOption] = []
  let seen : Map[String, Unit] = Map([])
  for index, entry in entries {
    let path = "$.options[\{index}]"
    let fields = read_object(entry, ["id", "cron"], path)
    let id = read_id(fields["id"], path + ".id")
    guard !seen.contains(id) else {
      raise InvalidInput(path=path + ".id", detail="duplicate option ID " + id)
    }
    seen[id] = ()
    let expression = read_string(fields["cron"], path + ".cron")
    let cron = parse_schedule(expression, path + ".cron")
    options.push({ id, expression, cron, })
  }
  options
}

///|
fn count_launches(job : Job, start : Int64, end : Int64) -> Int32 {
  let mut count = 0
  for minute = start; minute < end; minute = minute + 1L {
    if job.runs_at(minute, utc_moment(minute)) {
      count += 1
    }
  }
  count
}

///|
/// Evaluate cron alternatives for one candidate job under the original budget.
/// Recommend the first option preserving in-window launches with no regression.
pub fn evaluate_launch_repairs(
  input : ReviewInput,
  text : String,
) -> RepairReport raise ReviewError {
  evaluate_repairs(input, text, None)
}

///|
/// Recommend the first option preserving launches that passes the same policy as `gate`.
pub fn evaluate_launch_repairs_with_policy(
  input : ReviewInput,
  text : String,
  policy : CapacityPolicy,
) -> RepairReport raise ReviewError {
  validate_policy_resources(input, policy)
  evaluate_repairs(input, text, Some(policy))
}

///|
fn evaluate_repairs(
  input : ReviewInput,
  text : String,
  policy : CapacityPolicy?,
) -> RepairReport raise ReviewError {
  let root = read_object(
    parse_document(text),
    ["schema", "job", "options"],
    "$",
  )
  guard root["schema"] == Json::string(repairs_schema) else {
    raise InvalidInput(path="$.schema", detail="expected " + repairs_schema)
  }
  let job_id = read_id(root["job"], "$.job")
  guard input.candidate.search_by(job => job.id == job_id) is Some(index) else {
    raise InvalidInput(
      path="$.job",
      detail="job is absent from the candidate plan",
    )
  }
  let options = read_repair_options(root["options"])
  let original = input.candidate[index]
  let required_launches = count_launches(original, input.start, input.end)
  guard required_launches > 0 else {
    raise InvalidInput(
      path="$.job",
      detail="candidate job has no launches in the review window",
    )
  }
  let results : Array[RepairResult] = []
  let violations : Map[String, Array[CapacityViolation]] = Map([])
  let mut recommendation : (String, ReviewInput)? = None
  for option in options {
    let modified = {
      ..original,
      expression: option.expression,
      cron: option.cron,
    }
    let launch_count = count_launches(modified, input.start, input.end)
    if launch_count != required_launches {
      results.push({ id: option.id, launch_count, regression_count: None, })
      continue
    }
    let jobs = input.candidate.copy()
    jobs[index] = modified
    let proposal = { ..input, candidate: jobs, }
    let report = compare_capacity(proposal) catch {
      InvalidInput(path~, detail~) =>
        raise InvalidInput(path~, detail="option " + option.id + ": " + detail)
      LimitExceeded(path~, detail~) =>
        raise LimitExceeded(path~, detail="option " + option.id + ": " + detail)
    }
    results.push({
      id: option.id,
      launch_count,
      regression_count: Some(report.regression_count),
    })
    let blocked = match policy {
      Some(policy) => {
        let gate = apply_capacity_policy(report, policy)
        violations[option.id] = gate.violations
        gate.has_failures()
      }
      None => report.has_regressions()
    }
    if recommendation is None && !blocked {
      recommendation = Some((option.id, proposal))
    }
  }
  { job_id, required_launches, results, recommendation, policy, violations, }
}

///|
pub fn RepairReport::to_json(self : RepairReport) -> Json {
  let options = self.results.map(option => {
    let violations = self.violations.get(option.id)
    let (verdict, regressions) = match option.regression_count {
      None => ("launch_count_changed", Json::null())
      Some(count) =>
        (
          if count > 0 || (violations is Some(entries) && !entries.is_empty()) {
            "blocked"
          } else {
            "passed"
          },
          Json::number(count.to_double()),
        )
    }
    let entry : Map[String, Json] = {
      "id": Json::string(option.id),
      "launch_count": Json::number(option.launch_count.to_double()),
      "verdict": Json::string(verdict),
      "regression_count": regressions,
    }
    if self.policy is Some(_) {
      entry["policy_violations"] = match violations {
        Some(entries) => Json::array(entries.map(CapacityViolation::to_json))
        None => Json::null()
      }
    }
    Json::object(entry)
  })
  let (selected, proposal) = match self.recommendation {
    Some((id, review)) => (Json::string(id), review.to_json())
    None => (Json::null(), Json::null())
  }
  let document : Map[String, Json] = {
    "schema": "batchcontour.launch-repair-report.v1",
    "job": Json::string(self.job_id),
    "required_launches": Json::number(self.required_launches.to_double()),
    "options": Json::array(options),
    "selected": selected,
    "proposal": proposal,
  }
  if self.policy is Some(policy) {
    document["schema"] = Json::string("batchcontour.launch-repair-report.v2")
    document["policy"] = policy.to_json()
  }
  Json::object(document)
}
