///|
/// A completed run outside the duration range declared for its plan and job.
pub struct DurationViolation {
  run_id : String
  started_at : String
  finished_at : String
  elapsed_seconds : Int64
  reason : String
}

///|
/// One job's sample coverage, observed extrema and out-of-range runs.
pub struct DurationCheck {
  plan : String
  job_id : String
  minimum_seconds : Int64
  maximum_seconds : Int64
  sample_count : Int32
  observed_minimum_seconds : Int64?
  observed_maximum_seconds : Int64?
  violations : ArrayView[DurationViolation]
}

///|
/// Evidence checks in baseline then candidate order, sorted by job ID.
struct DurationReport {
  min_samples : Int32
  checks : Array[DurationCheck]
}

///|
pub fn DurationReport::checks(
  self : DurationReport,
) -> ArrayView[DurationCheck] {
  self.checks[:]
}

///|
/// Required observations per job and plan side.
pub fn DurationReport::min_samples(self : DurationReport) -> Int32 {
  self.min_samples
}

///|
pub fn DurationReport::has_failures(self : DurationReport) -> Bool {
  self.checks.any(check => {
    check.sample_count < self.min_samples || !check.violations.is_empty()
  })
}

///|
fn summarize_duration(
  plan : String,
  job : Job,
  runs : Array[Observation],
) -> DurationCheck {
  let minimum_seconds = job.min_minutes.to_int64() * 60L
  let maximum_seconds = job.max_minutes.to_int64() * 60L
  let mut observed_low : Int64? = None
  let mut observed_high : Int64? = None
  let violations : Array[DurationViolation] = []
  for run in runs {
    let elapsed = run.elapsed_seconds
    if !(observed_low is Some(low) && low <= elapsed) {
      observed_low = Some(elapsed)
    }
    if !(observed_high is Some(high) && high >= elapsed) {
      observed_high = Some(elapsed)
    }
    let reason = if elapsed < minimum_seconds {
      "below_minimum"
    } else if elapsed > maximum_seconds {
      "above_maximum"
    } else {
      continue
    }
    violations.push({
      run_id: run.run_id,
      started_at: run.started_at,
      finished_at: run.finished_at,
      elapsed_seconds: elapsed,
      reason,
    })
  }
  {
    plan,
    job_id: job.id,
    minimum_seconds,
    maximum_seconds,
    sample_count: runs.length(),
    observed_minimum_seconds: observed_low,
    observed_maximum_seconds: observed_high,
    violations: violations[:],
  }
}

///|
/// Check measurements against the named plan and job without modifying the review.
/// Evidence for undeclared jobs raises an error rather than disappearing.
pub fn check_durations(
  input : ReviewInput,
  history : RunHistory,
) -> DurationReport raise ReviewError {
  let groups : Map[(String, String), Array[Observation]] = Map([])
  let plans = [("baseline", input.baseline), ("candidate", input.candidate)]
  for entry in plans {
    let (plan, jobs) = entry
    for job in jobs {
      groups[(plan, job.id)] = []
    }
  }
  for run in history.runs {
    guard groups.get((run.plan, run.job_id)) is Some(group) else {
      raise InvalidInput(
        path="$.runs[\{run.source_index}].job",
        detail="job " + run.job_id + " is absent from the " + run.plan + " plan",
      )
    }
    group.push(run)
  }
  let checks : Array[DurationCheck] = []
  for entry in plans {
    let (plan, jobs) = entry
    for job in jobs {
      checks.push(summarize_duration(plan, job, groups[(plan, job.id)]))
    }
  }
  { min_samples: history.min_samples, checks, }
}

///|
fn seconds_json(seconds : Int64?) -> Json {
  match seconds {
    Some(seconds) => Json::number(seconds.to_double())
    None => Json::null()
  }
}

///|
fn violation_json(violation : DurationViolation) -> Json {
  {
    "id": Json::string(violation.run_id),
    "started_at": Json::string(violation.started_at),
    "finished_at": Json::string(violation.finished_at),
    "elapsed_seconds": Json::number(violation.elapsed_seconds.to_double()),
    "reason": Json::string(violation.reason),
  }
}

///|
/// Encode the evidence checks and independent pass or block verdict.
pub fn DurationReport::to_json(self : DurationReport) -> Json {
  let checks = self.checks.map(check => {
    let value : Json = {
      "plan": Json::string(check.plan),
      "job": Json::string(check.job_id),
      "minimum_seconds": Json::number(check.minimum_seconds.to_double()),
      "maximum_seconds": Json::number(check.maximum_seconds.to_double()),
      "sample_count": Json::number(check.sample_count.to_double()),
      "observed_minimum_seconds": seconds_json(check.observed_minimum_seconds),
      "observed_maximum_seconds": seconds_json(check.observed_maximum_seconds),
      "insufficient_samples": Json::boolean(
        check.sample_count < self.min_samples,
      ),
      "violations": Json::array(check.violations.map(violation_json)),
    }
    value
  })
  {
    "schema": "batchcontour.duration-report.v1",
    "verdict": if self.has_failures() {
      "blocked"
    } else {
      "passed"
    },
    "min_samples": Json::number(self.min_samples.to_double()),
    "checks": Json::array(checks),
  }
}
