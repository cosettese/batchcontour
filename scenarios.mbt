///|
let scenarios_schema = "batchcontour.capacity-scenarios.v1"

///|
priv struct Scenario {
  id : String
  capacities : Array[Capacity]
}

///|
/// One budget's regression result and resource totals for the supplied plans.
pub struct ScenarioResult {
  id : String
  regression_count : Int32
  resources : ArrayView[ResourceSummary]
}

///|
/// A common review window and the results of all named capacity scenarios.
struct ScenarioReport {
  start : Int64
  end : Int64
  results : Array[ScenarioResult]
}

///|
pub fn ScenarioReport::results(
  self : ScenarioReport,
) -> ArrayView[ScenarioResult] {
  self.results[:]
}

///|
pub fn ScenarioReport::has_regressions(self : ScenarioReport) -> Bool {
  self.results.any(result => result.regression_count > 0)
}

///|
fn read_scenarios(
  input : ReviewInput,
  source : String,
) -> Array[Scenario] raise ReviewError {
  let root = read_object(parse_document(source), ["schema", "scenarios"], "$")
  guard root["schema"] == Json::string(scenarios_schema) else {
    raise InvalidInput(path="$.schema", detail="expected " + scenarios_schema)
  }
  guard root["scenarios"] is Array(entries) &&
    !entries.is_empty() &&
    entries.length() <= 8 else {
    raise InvalidInput(path="$.scenarios", detail="expected 1–8 scenarios")
  }
  let scenarios : Array[Scenario] = []
  let seen : Map[String, Unit] = Map([])
  let expected = input.capacities.map(capacity => capacity.resource)
  for index, value in entries {
    let path = "$.scenarios[\{index}]"
    let fields = read_object(
      value,
      ["id", "capacities", "capacity_overrides"],
      path,
    )
    let id = read_id(fields["id"], path + ".id")
    guard !seen.contains(id) else {
      raise InvalidInput(
        path=path + ".id",
        detail="duplicate scenario ID " + id,
      )
    }
    seen[id] = ()
    let capacities = read_capacities(
      fields["capacities"],
      path=path + ".capacities",
    )
    guard capacities.map(capacity => capacity.resource) == expected else {
      raise InvalidInput(
        path=path + ".capacities",
        detail="expected exactly the review's resource IDs: " +
          expected.join(", "),
      )
    }
    read_capacity_overrides(
      fields["capacity_overrides"],
      capacities,
      input.start,
      input.end,
      path=path + ".capacity_overrides",
    )
    scenarios.push({ id, capacities, })
  }
  scenarios.sort_by((a, b) => a.id[:].lexical_compare(b.id[:]))
  scenarios
}

///|
/// Evaluate several complete budgets against the same schedules and window.
/// A failed computation refuses the batch and does not return partial results.
pub fn compare_capacity_scenarios(
  input : ReviewInput,
  source : String,
) -> ScenarioReport raise ReviewError {
  let scenarios = read_scenarios(input, source)
  let events = collect_events(input)
  let results : Array[ScenarioResult] = []
  for scenario in scenarios {
    let report = compare_sorted_capacity(
      { ..input, capacities: scenario.capacities, },
      events,
    ) catch {
      InvalidInput(path~, detail~) =>
        raise InvalidInput(
          path~,
          detail="scenario " + scenario.id + ": " + detail,
        )
      LimitExceeded(path~, detail~) =>
        raise LimitExceeded(
          path~,
          detail="scenario " + scenario.id + ": " + detail,
        )
    }
    results.push({
      id: scenario.id,
      regression_count: report.regression_count,
      resources: report.summaries()[:],
    })
  }
  { start: input.start, end: input.end, results, }
}

///|
pub fn ScenarioReport::to_json(self : ScenarioReport) -> Json {
  let results = self.results.map(result => {
    let row : Json = {
      "id": Json::string(result.id),
      "verdict": if result.regression_count > 0 {
        "blocked"
      } else {
        "passed"
      },
      "regression_count": Json::number(result.regression_count.to_double()),
      "resources": resources_json(result.resources),
    }
    row
  })
  {
    "schema": "batchcontour.scenario-report.v1",
    "window": window_json(self.start, self.end),
    "verdict": if self.has_regressions() {
      "blocked"
    } else {
      "passed"
    },
    "scenarios": Json::array(results),
  }
}
