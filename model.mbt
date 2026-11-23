///|
let input_schema = "batchcontour.input.v1"

///|
let max_input_units = 1_048_576

///|
let max_window_minutes : Int32 = 31 * 24 * 60

///|
let max_duration_minutes : Int32 = 7 * 24 * 60

///|
let max_jobs = 128

///|
let max_resources = 32

///|
let max_units = 1_000_000

///|
/// A rejected input or incomplete computation. Paths identify submitted fields.
#derive(Debug)
pub(all) suberror ReviewError {
  InvalidInput(path~ : String, detail~ : String)
  LimitExceeded(path~ : String, detail~ : String)
}

///|
pub impl Show for ReviewError with fn output(self, logger) {
  match self {
    InvalidInput(path~, detail~) =>
      logger.write_string("input \{path}: \{detail}")
    LimitExceeded(path~, detail~) =>
      logger.write_string("limit \{path}: \{detail}")
  }
}

///|
priv struct Capacity {
  resource : String
  units : Int32
}

///|
priv struct Demand {
  resource_index : Int32
  units : Int32
}

///|
priv struct Job {
  id : String
  expression : String
  cron : @cron.Cron
  min_minutes : Int32
  max_minutes : Int32
  demands : Array[Demand]
}

///|
/// Validated baseline and candidate schedules with one UTC window and budget.
struct ReviewInput {
  start : Int64
  end : Int64
  capacities : Array[Capacity]
  baseline : Array[Job]
  candidate : Array[Job]
}

///|
/// An instance that can still hold a particular resource in the interval.
pub struct Contribution {
  job_id : String
  start_minute : Int64
  units : Int32
  guaranteed : Bool
}

///|
/// Occupancy and overload bounds for one side of a comparison.
pub struct Load {
  minimum : Int64
  maximum : Int64
  minimum_excess : Int64
  maximum_excess : Int64
  contributors : ArrayView[Contribution]
}

///|
/// A half-open UTC interval with possible or guaranteed overload on either side.
pub struct Finding {
  resource : String
  capacity : Int32
  from_minute : Int64
  until_minute : Int64
  baseline : Load
  candidate : Load
  regression : Bool
}

///|
/// Complete review of a bounded model, including pre-existing overload.
struct CapacityReport {
  start : Int64
  end : Int64
  findings : Array[Finding]
  regression_count : Int32
}

///|
/// Findings are ordered by resource ID, then by interval start.
pub fn CapacityReport::findings(self : CapacityReport) -> ArrayView[Finding] {
  self.findings[:]
}

///|
/// True if at least one interval has an increased lower or upper excess bound.
pub fn CapacityReport::has_regressions(self : CapacityReport) -> Bool {
  self.regression_count > 0
}
