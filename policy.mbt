///|
let capacity_policy_schema = "batchcontour.capacity-policy.v1"

///|
let max_exact_json_integer = 9_007_199_254_740_991L

///|
priv enum CapacityMetric {
  GuaranteedMinutes
  PossibleMinutes
  PeakMaximumExcess
  MaximumExcessUnitMinutes
}

///|
let capacity_metrics : Array[CapacityMetric] = [
  GuaranteedMinutes,
  PossibleMinutes,
  PeakMaximumExcess,
  MaximumExcessUnitMinutes,
]

///|
fn CapacityMetric::key(self : CapacityMetric) -> String {
  match self {
    GuaranteedMinutes => "guaranteed_minutes"
    PossibleMinutes => "possible_minutes"
    PeakMaximumExcess => "peak_maximum_excess"
    MaximumExcessUnitMinutes => "maximum_excess_unit_minutes"
  }
}

///|
fn CapacityMetric::measure(
  self : CapacityMetric,
  stats : OverloadStats,
) -> Int64 {
  match self {
    GuaranteedMinutes => stats.guaranteed_minutes
    PossibleMinutes => stats.possible_minutes
    PeakMaximumExcess => stats.peak_maximum_excess
    MaximumExcessUnitMinutes => stats.maximum_excess_unit_minutes
  }
}

///|
priv struct ResourceLimits {
  resource : String
  limits : Array[(CapacityMetric, Int64)]
}

///|
/// Optional absolute ceilings on the candidate's overload per named resource.
struct CapacityPolicy {
  resources : Array[ResourceLimits]
}

///|
fn read_policy_limit(value : Json, path : String) -> Int64 raise ReviewError {
  let detail = "expected a nonnegative integer up to 9007199254740991, written in decimal digits"
  guard value is Number(_, repr=Some(text)) && text.length() <= 16 else {
    raise InvalidInput(path~, detail~)
  }
  let mut limit = 0L
  for digit in text {
    guard digit >= '0' && digit <= '9' else {
      raise InvalidInput(path~, detail~)
    }
    limit = limit * 10L + digit.to_int().to_int64() - 48L
  }
  guard limit <= max_exact_json_integer else {
    raise InvalidInput(path~, detail~)
  }
  limit
}

///|
fn read_resource_limits(
  value : Json,
  path : String,
) -> Array[(CapacityMetric, Int64)] raise ReviewError {
  guard value is Object(fields) && !fields.is_empty() else {
    raise InvalidInput(path~, detail="expected at least one overload ceiling")
  }
  for key, _ in fields {
    guard capacity_metrics.any(metric => metric.key() == key) else {
      raise InvalidInput(
        path~,
        detail="unknown ceiling " + Json::string(key).stringify(),
      )
    }
  }
  let limits : Array[(CapacityMetric, Int64)] = []
  for metric in capacity_metrics {
    let key = metric.key()
    if fields.get(key) is Some(limit) {
      limits.push((metric, read_policy_limit(limit, path + "." + key)))
    }
  }
  limits
}

///|
/// Read a policy with 1–32 resource entries and at least one ceiling per entry.
pub fn CapacityPolicy::from_json(
  text : String,
) -> CapacityPolicy raise ReviewError {
  let root = read_object(parse_document(text), ["schema", "resources"], "$")
  guard root["schema"] == Json::string(capacity_policy_schema) else {
    raise InvalidInput(
      path="$.schema",
      detail="expected " + capacity_policy_schema,
    )
  }
  guard root["resources"] is Object(fields) &&
    !fields.is_empty() &&
    fields.length() <= max_resources else {
    raise InvalidInput(
      path="$.resources",
      detail="expected 1–32 named resources",
    )
  }
  let resources : Array[ResourceLimits] = []
  for name, value in fields {
    let resource = read_id(Json::string(name), "$.resources")
    resources.push({
      resource,
      limits: read_resource_limits(value, "$.resources." + name),
    })
  }
  resources.sort_by((left, right) => {
    left.resource[:].lexical_compare(right.resource[:])
  })
  { resources, }
}

///|
/// Canonical serialization preserves every ceiling and explicit zero.
pub fn CapacityPolicy::to_json(self : CapacityPolicy) -> Json {
  let resources : Map[String, Json] = Map([])
  for row in self.resources {
    let limits : Map[String, Json] = Map([])
    for entry in row.limits {
      let (metric, limit) = entry
      limits[metric.key()] = Json::number(
        limit.to_double(),
        repr=limit.to_string(),
      )
    }
    resources[row.resource] = Json::object(limits)
  }
  {
    "schema": Json::string(capacity_policy_schema),
    "resources": Json::object(resources),
  }
}
