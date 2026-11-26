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
  review : CapacityReport
  violations : Array[CapacityViolation]
}

///|
pub fn CapacityGate::regression_blocked(self : CapacityGate) -> Bool {
  self.review.has_regressions()
}

///|
/// Read the intervals and contributing runs from the same sweep as the gate.
pub fn CapacityGate::report(self : CapacityGate) -> CapacityReport {
  self.review
}

///|
pub fn CapacityGate::violations(
  self : CapacityGate,
) -> ArrayView[CapacityViolation] {
  self.violations[:]
}

///|
pub fn CapacityGate::has_failures(self : CapacityGate) -> Bool {
  self.regression_blocked() || !self.violations.is_empty()
}

///|
fn validate_policy_resources(
  input : ReviewInput,
  policy : CapacityPolicy,
) -> Unit raise ReviewError {
  for rule in policy.resources {
    guard input.capacities.any(capacity => capacity.resource == rule.resource) else {
      raise InvalidInput(
        path="$.resources." + rule.resource,
        detail="resource is absent from the review's capacity budget",
      )
    }
  }
}

///|
fn capacity_violations(
  report : CapacityReport,
  policy : CapacityPolicy,
) -> Array[CapacityViolation] {
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
  violations
}

///|
/// Run the capacity review and apply absolute limits to the candidate.
/// A compliant absolute policy cannot override a regression.
pub fn check_capacity_policy(
  input : ReviewInput,
  policy : CapacityPolicy,
) -> CapacityGate raise ReviewError {
  validate_policy_resources(input, policy)
  apply_capacity_policy(compare_capacity(input), policy)
}

///|
fn apply_capacity_policy(
  review : CapacityReport,
  policy : CapacityPolicy,
) -> CapacityGate {
  { review, violations: capacity_violations(review, policy), }
}

///|
fn CapacityViolation::to_json(violation : CapacityViolation) -> Json {
  {
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
}

///|
pub fn CapacityGate::to_json(self : CapacityGate) -> Json {
  {
    "schema": "batchcontour.capacity-gate.v1",
    "verdict": if self.has_failures() {
      "blocked"
    } else {
      "passed"
    },
    "regression_blocked": Json::boolean(self.regression_blocked()),
    "violations": Json::array(self.violations.map(CapacityViolation::to_json)),
  }
}
