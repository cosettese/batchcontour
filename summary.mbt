///|
/// Duration, peak and integrated shortage for one plan on one resource.
pub struct OverloadStats {
  guaranteed_minutes : Int64
  possible_minutes : Int64
  peak_minimum_excess : Int64
  peak_maximum_excess : Int64
  minimum_excess_unit_minutes : Int64
  maximum_excess_unit_minutes : Int64
}

///|
/// Whole-window totals for a resource that can overload in either plan.
pub struct ResourceSummary {
  resource : String
  baseline : OverloadStats
  candidate : OverloadStats
  regression_minutes : Int64
}

///|
fn empty_stats() -> OverloadStats {
  {
    guaranteed_minutes: 0L,
    possible_minutes: 0L,
    peak_minimum_excess: 0L,
    peak_maximum_excess: 0L,
    minimum_excess_unit_minutes: 0L,
    maximum_excess_unit_minutes: 0L,
  }
}

///|
fn OverloadStats::add_span(
  self : OverloadStats,
  load : Load,
  minutes : Int64,
) -> OverloadStats {
  let low = load.minimum_excess
  let high = load.maximum_excess
  {
    guaranteed_minutes: self.guaranteed_minutes +
    (if low > 0L { minutes } else { 0L }),
    possible_minutes: self.possible_minutes +
    (if high > 0L { minutes } else { 0L }),
    peak_minimum_excess: if low > self.peak_minimum_excess {
      low
    } else {
      self.peak_minimum_excess
    },
    peak_maximum_excess: if high > self.peak_maximum_excess {
      high
    } else {
      self.peak_maximum_excess
    },
    minimum_excess_unit_minutes: self.minimum_excess_unit_minutes +
    low * minutes,
    maximum_excess_unit_minutes: self.maximum_excess_unit_minutes +
    high * minutes,
  }
}

///|
/// Aggregate disjoint intervals without netting improvements against regressions.
/// A resource within budget in both plans has no summary row.
pub fn CapacityReport::summaries(
  self : CapacityReport,
) -> Array[ResourceSummary] {
  let summaries : Array[ResourceSummary] = []
  for finding in self.findings {
    let minutes = finding.until_minute - finding.from_minute
    let previous = match summaries.last() {
      Some(entry) if entry.resource == finding.resource => {
        ignore(summaries.pop())
        entry
      }
      _ =>
        {
          resource: finding.resource,
          baseline: empty_stats(),
          candidate: empty_stats(),
          regression_minutes: 0L,
        }
    }
    summaries.push({
      resource: finding.resource,
      baseline: previous.baseline.add_span(finding.baseline, minutes),
      candidate: previous.candidate.add_span(finding.candidate, minutes),
      regression_minutes: previous.regression_minutes +
      (if finding.regression { minutes } else { 0L }),
    })
  }
  summaries
}

///|
fn stats_json(stats : OverloadStats) -> Json {
  {
    "guaranteed_minutes": Json::number(stats.guaranteed_minutes.to_double()),
    "possible_minutes": Json::number(stats.possible_minutes.to_double()),
    "peak_minimum_excess": Json::number(stats.peak_minimum_excess.to_double()),
    "peak_maximum_excess": Json::number(stats.peak_maximum_excess.to_double()),
    "minimum_excess_unit_minutes": Json::number(
      stats.minimum_excess_unit_minutes.to_double(),
    ),
    "maximum_excess_unit_minutes": Json::number(
      stats.maximum_excess_unit_minutes.to_double(),
    ),
  }
}

///|
fn resources_json(resources : ArrayView[ResourceSummary]) -> Json {
  Json::array(
    resources.map(summary => {
      let row : Json = {
        "resource": Json::string(summary.resource),
        "baseline": stats_json(summary.baseline),
        "candidate": stats_json(summary.candidate),
        "regression_minutes": Json::number(
          summary.regression_minutes.to_double(),
        ),
      }
      row
    }),
  )
}

///|
/// Aggregate JSON for CI logs. The verdict matches the detailed review.
pub fn CapacityReport::summary_json(self : CapacityReport) -> Json {
  {
    "schema": "batchcontour.capacity-summary.v1",
    "window": window_json(self.start, self.end),
    "verdict": if self.has_regressions() {
      "blocked"
    } else {
      "passed"
    },
    "resources": resources_json(self.summaries()[:]),
  }
}
