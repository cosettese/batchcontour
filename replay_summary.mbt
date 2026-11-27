///|
/// Accumulated overload attributable to the recorded runs for one resource.
pub struct ReplayResourceSummary {
  resource : String
  overload_seconds : Int64
  peak_excess_units : Int64
  excess_unit_seconds : Int64
}

///|
/// Summarize disjoint intervals without counting the same second twice.
pub fn ReplayReport::summaries(
  self : ReplayReport,
) -> Array[ReplayResourceSummary] {
  let totals : Map[String, ReplayResourceSummary] = Map([])
  for interval in self.overloads {
    let resource = interval.resource
    let previous = totals
      .get(resource)
      .unwrap_or({
        resource,
        overload_seconds: 0L,
        peak_excess_units: 0L,
        excess_unit_seconds: 0L,
      })
    let seconds = interval.until_second - interval.from_second
    let excess = interval.occupied_units - interval.capacity.to_int64()
    totals[resource] = {
      resource,
      overload_seconds: previous.overload_seconds + seconds,
      peak_excess_units: if excess > previous.peak_excess_units {
        excess
      } else {
        previous.peak_excess_units
      },
      excess_unit_seconds: previous.excess_unit_seconds + excess * seconds,
    }
  }
  let rows : Array[ReplayResourceSummary] = []
  for _, totals_for_resource in totals {
    rows.push(totals_for_resource)
  }
  rows.sort_by((a, b) => a.resource[:].lexical_compare(b.resource[:]))
  rows
}

///|
fn replay_integer(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
/// Encode the time-weighted shortfall and coverage for a historical replay.
pub fn ReplayReport::summary_json(self : ReplayReport) -> Json {
  let resources = self
    .summaries()
    .map(row => {
      let entry : Json = {
        "resource": Json::string(row.resource),
        "overload_seconds": replay_integer(row.overload_seconds),
        "peak_excess_units": replay_integer(row.peak_excess_units),
        "excess_unit_seconds": replay_integer(row.excess_unit_seconds),
      }
      entry
    })
  {
    "schema": "batchcontour.history-replay-summary.v1",
    "window": window_json(self.start_minute, self.end_minute),
    "plan": Json::string(self.plan),
    "min_samples": Json::number(self.min_samples.to_double()),
    "verdict": Json::string(
      if self.has_failures() {
        "blocked"
      } else {
        "passed"
      },
    ),
    "coverage": self.coverage_json(),
    "run_counts": self.counts_json(),
    "resources": Json::array(resources),
  }
}
