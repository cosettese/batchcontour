///|
/// Candidate overload exceeding a configured resource ceiling.
pub struct CapacityViolation {
  resource : String
  metric : String
  limit : Int64
  actual : Int64
}

///|
/// Separate results for the existing regression gate and the policy ceilings.
struct CapacityGate {
  regression_blocked : Bool
  violations : Array[CapacityViolation]
}

///|
pub fn CapacityGate::regression_blocked(self : CapacityGate) -> Bool {
  self.regression_blocked
}

///|
pub fn CapacityGate::violations(
  self : CapacityGate,
) -> ArrayView[CapacityViolation] {
  self.violations[:]
}

///|
pub fn CapacityGate::has_failures(self : CapacityGate) -> Bool {
  self.regression_blocked || !self.violations.is_empty()
}

///|
/// Run the capacity review and apply absolute limits to the candidate.
/// A compliant absolute policy cannot override a regression.
pub fn check_capacity_policy(
  input : ReviewInput,
  policy : CapacityPolicy,
) -> CapacityGate raise ReviewError {
  for rule in policy.resources {
    guard input.capacities.any(capacity => capacity.resource == rule.resource) else {
      raise InvalidInput(
        path="$.resources." + rule.resource,
        detail="resource is absent from the review's capacity budget",
      )
    }
  }
  let report = compare_capacity(input)
  let summaries = report.summaries()
  let violations : Array[CapacityViolation] = []
  for rule in policy.resources {
    let stats = match
      summaries.search_by(summary => summary.resource == rule.resource) {
      Some(index) => summaries[index].candidate
      None => empty_stats()
    }
    for entry in rule.limits {
      let (metric, limit) = entry
      let actual = metric.measure(stats)
      if actual > limit {
        violations.push({
          resource: rule.resource,
          metric: metric.key(),
          limit,
          actual,
        })
      }
    }
  }
  { regression_blocked: report.has_regressions(), violations, }
}

///|
pub fn CapacityGate::to_json(self : CapacityGate) -> Json {
  let entries = self.violations.map(violation => {
    let entry : Json = {
      "resource": Json::string(violation.resource),
      "metric": Json::string(violation.metric),
      "limit": Json::number(
        violation.limit.to_double(),
        repr=violation.limit.to_string(),
      ),
      "actual": Json::number(
        violation.actual.to_double(),
        repr=violation.actual.to_string(),
      ),
    }
    entry
  })
  {
    "schema": "batchcontour.capacity-gate.v1",
    "verdict": if self.has_failures() {
      "blocked"
    } else {
      "passed"
    },
    "regression_blocked": Json::boolean(self.regression_blocked),
    "violations": Json::array(entries),
  }
}
