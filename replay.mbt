///|
/// Coverage counts completed runs with positive overlap for one plan job.
pub struct ReplayCoverage {
  job_id : String
  sample_count : Int32
}

///|
/// A half-open overloaded interval, in UTC epoch seconds.
pub struct ReplayInterval {
  resource : String
  from_second : Int64
  until_second : Int64
  capacity : Int32
  occupied_units : Int64
  run_ids : ArrayView[String]
}

///|
struct ReplayReport {
  plan : String
  start_minute : Int64
  end_minute : Int64
  min_samples : Int32
  coverage : Array[ReplayCoverage]
  overloads : Array[ReplayInterval]
  used : Int32
  outside : Int32
  zero_duration : Int32
  other_plan : Int32
}

///|
pub fn ReplayReport::coverage(self : ReplayReport) -> ArrayView[ReplayCoverage] {
  self.coverage[:]
}

///|
pub fn ReplayReport::overloads(
  self : ReplayReport,
) -> ArrayView[ReplayInterval] {
  self.overloads[:]
}

///|
pub fn ReplayReport::has_failures(self : ReplayReport) -> Bool {
  !self.overloads.is_empty() ||
  self.coverage.any(job => job.sample_count < self.min_samples)
}

///|
priv struct ReplayEvent {
  second : Int64
  run_id : String
  change : Int64
}

///|
priv struct ReplayFindings {
  overloads : Array[ReplayInterval]
  mut witnesses : Int32
}

///|
fn replay_resource(
  findings : ReplayFindings,
  events : Array[ReplayEvent],
  budget : Capacity,
  start : Int64,
  end : Int64,
) -> Unit raise ReviewError {
  events.sort_by_key(event => event.second)
  let active : Map[String, Unit] = Map([])
  let mut occupied = 0L
  let mut index = 0
  let mut override_index = 0
  let mut cursor = start
  while cursor < end {
    let from = cursor
    let (units, boundary, next_override) = budget.band_at(
      from, end, override_index, 60L,
    )
    override_index = next_override
    while events.get(index) is Some(event) && event.second == from {
      occupied += event.change
      if event.change > 0L {
        active[event.run_id] = ()
      } else {
        active.remove(event.run_id)
      }
      index += 1
    }
    let until = match events.get(index) {
      Some(event) if event.second < boundary => event.second
      _ => boundary
    }
    cursor = until
    if occupied <= units.to_int64() {
      continue
    }
    findings.witnesses += active.length()
    guard findings.overloads.length() < 12_000 && findings.witnesses <= 100_000 else {
      raise LimitExceeded(
        path="$.report",
        detail="replay exceeds 12,000 overload intervals or 100,000 run references; shorten the window",
      )
    }
    let ids : Array[String] = []
    for id, _ in active {
      ids.push(id)
    }
    ids.sort_by((a, b) => a[:].lexical_compare(b[:]))
    findings.overloads.push({
      resource: budget.resource,
      from_second: from,
      until_second: until,
      capacity: units,
      occupied_units: occupied,
      run_ids: ids[:],
    })
  }
}

///|
/// Apply one plan's declared demand to the completed runs observed in its window.
pub fn replay_history(
  input : ReviewInput,
  history : RunHistory,
  plan : String,
) -> ReplayReport raise ReviewError {
  let jobs = match plan {
    "baseline" => input.baseline
    "candidate" => input.candidate
    _ =>
      raise InvalidInput(path="plan", detail="expected baseline or candidate")
  }
  let indices : Map[String, Int32] = Map([])
  for index, job in jobs {
    indices[job.id] = index
  }
  let start = input.start * 60L
  let end = input.end * 60L
  let samples = Array::make(jobs.length(), 0)
  let events : Array[Array[ReplayEvent]] = Array::makei(
    input.capacities.length(),
    _ => [],
  )
  let mut event_count = 0
  let mut used = 0
  let mut outside = 0
  let mut zero_duration = 0
  let mut other_plan = 0
  for run in history.runs {
    if run.plan != plan {
      other_plan += 1
      continue
    }
    guard indices.get(run.job_id) is Some(index) else {
      raise InvalidInput(
        path="$.runs[\{run.source_index}].job",
        detail="job " + run.job_id + " is absent from the " + plan + " plan",
      )
    }
    if run.elapsed_seconds == 0L {
      zero_duration += 1
      continue
    }
    let finish = run.start_second + run.elapsed_seconds
    if finish <= start || run.start_second >= end {
      outside += 1
      continue
    }
    used += 1
    samples[index] += 1
    let from = if run.start_second < start { start } else { run.start_second }
    let demands = jobs[index].demands
    event_count += demands.length() * (if finish < end { 2 } else { 1 })
    guard event_count <= max_events else {
      raise LimitExceeded(
        path="$.runs",
        detail="replay exceeds 120,000 resource events; shorten the window",
      )
    }
    for demand in demands {
      let queue = events[demand.resource_index]
      let units = demand.units.to_int64()
      queue.push({ second: from, run_id: run.run_id, change: units, })
      if finish < end {
        queue.push({ second: finish, run_id: run.run_id, change: -units, })
      }
    }
  }
  let findings : ReplayFindings = { overloads: [], witnesses: 0, }
  for index, budget in input.capacities {
    replay_resource(findings, events[index], budget, start, end)
  }
  let coverage = Array::makei(jobs.length(), index => {
    job_id: jobs[index].id,
    sample_count: samples[index],
  })
  {
    plan,
    start_minute: input.start,
    end_minute: input.end,
    min_samples: history.min_samples,
    coverage,
    overloads: findings.overloads,
    used,
    outside,
    zero_duration,
    other_plan,
  }
}

///|
pub fn ReplayReport::to_json(self : ReplayReport) -> Json {
  let coverage = self.coverage.map(job => {
    let entry : Json = {
      "job": Json::string(job.job_id),
      "sample_count": Json::number(job.sample_count.to_double()),
      "insufficient_samples": Json::boolean(job.sample_count < self.min_samples),
    }
    entry
  })
  let overloads = self.overloads.map(interval => {
    let entry : Json = {
      "resource": Json::string(interval.resource),
      "start": Json::string(utc_second_text(interval.from_second)),
      "end": Json::string(utc_second_text(interval.until_second)),
      "capacity": Json::number(interval.capacity.to_double()),
      "occupied_units": Json::number(interval.occupied_units.to_double()),
      "runs": Json::array(interval.run_ids.to_owned().map(Json::string)),
    }
    entry
  })
  {
    "schema": "batchcontour.history-replay.v1",
    "window": window_json(self.start_minute, self.end_minute),
    "plan": Json::string(self.plan),
    "verdict": Json::string(
      if self.has_failures() {
        "blocked"
      } else {
        "passed"
      },
    ),
    "min_samples": Json::number(self.min_samples.to_double()),
    "coverage": Json::array(coverage),
    "overloads": Json::array(overloads),
    "run_counts": {
      "used": Json::number(self.used.to_double()),
      "outside_window": Json::number(self.outside.to_double()),
      "zero_duration": Json::number(self.zero_duration.to_double()),
      "other_plan": Json::number(self.other_plan.to_double()),
    },
  }
}
