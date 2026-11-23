///|
priv struct ActiveLoad {
  contributors : Map[Int32, Contribution]
  mut minimum : Int64
  mut maximum : Int64
}

///|
fn ActiveLoad::new() -> ActiveLoad {
  { contributors: Map([]), minimum: 0L, maximum: 0L, }
}

///|
fn ActiveLoad::apply(self : ActiveLoad, event : Event) -> Unit {
  match event.kind {
    Start(contribution) => {
      let units = contribution.units.to_int64()
      self.contributors[event.instance] = contribution
      self.maximum += units
      if contribution.guaranteed {
        self.minimum += units
      }
    }
    LoseGuarantee => {
      let contribution = self.contributors[event.instance]
      self.minimum -= contribution.units.to_int64()
      self.contributors[event.instance] = { ..contribution, guaranteed: false, }
    }
    Finish => {
      let contribution = self.contributors[event.instance]
      let units = contribution.units.to_int64()
      self.contributors.remove(event.instance)
      self.maximum -= units
      if contribution.guaranteed {
        self.minimum -= units
      }
    }
  }
}

///|
fn excess(occupancy : Int64, capacity : Int64) -> Int64 {
  if occupancy > capacity {
    occupancy - capacity
  } else {
    0L
  }
}

///|
fn ActiveLoad::snapshot(self : ActiveLoad, capacity : Int64) -> Load {
  let entries : Array[Contribution] = []
  for _, contribution in self.contributors {
    entries.push(contribution)
  }
  entries.sort_by((left, right) => {
    let by_job = left.job_id[:].lexical_compare(right.job_id[:])
    if by_job == 0 {
      left.start_minute.compare(right.start_minute)
    } else {
      by_job
    }
  })
  {
    minimum: self.minimum,
    maximum: self.maximum,
    minimum_excess: excess(self.minimum, capacity),
    maximum_excess: excess(self.maximum, capacity),
    contributors: entries[:],
  }
}

///|
priv struct ReportBuilder {
  findings : Array[Finding]
  mut contributors : Int32
  mut regressions : Int32
}

///|
fn review_resource(
  findings : ReportBuilder,
  events : Array[Event],
  budget : Capacity,
  end : Int64,
) -> Unit raise ReviewError {
  let baseline = ActiveLoad::new()
  let candidate = ActiveLoad::new()
  let capacity = budget.units.to_int64()
  events.sort_by_key(event => event.minute)
  let mut index = 0
  while index < events.length() {
    let start = events[index].minute
    // Apply all changes at the boundary before looking at the next interval.
    while index < events.length() && events[index].minute == start {
      let event = events[index]
      if event.candidate {
        candidate.apply(event)
      } else {
        baseline.apply(event)
      }
      index += 1
    }
    let until = match events.get(index) {
      Some(event) => event.minute
      None => end
    }
    if baseline.maximum <= capacity && candidate.maximum <= capacity {
      continue
    }
    findings.contributors += baseline.contributors.length() +
      candidate.contributors.length()
    guard findings.findings.length() < 12_000 &&
      findings.contributors <= 100_000 else {
      raise LimitExceeded(
        path="$.report",
        detail="findings exceed 12,000 intervals or 100,000 contributors; shorten the window or split the review",
      )
    }
    let before = baseline.snapshot(capacity)
    let after = candidate.snapshot(capacity)
    let regression = after.minimum_excess > before.minimum_excess ||
      after.maximum_excess > before.maximum_excess
    if regression {
      findings.regressions += 1
    }
    findings.findings.push({
      resource: budget.resource,
      capacity: budget.units,
      from_minute: start,
      until_minute: until,
      baseline: before,
      candidate: after,
      regression,
    })
  }
}

///|
/// Compare both schedules under one shared budget. A bound increase in an
/// overload interval blocks the default gate. Failure returns no partial report.
pub fn compare_capacity(
  input : ReviewInput,
) -> CapacityReport raise ReviewError {
  let queue : EventQueue = {
    by_resource: Array::makei(input.capacities.length(), _ => []),
    event_count: 0,
  }
  expand_plan(queue, input.baseline, input.start, input.end, false)
  expand_plan(queue, input.candidate, input.start, input.end, true)
  let result : ReportBuilder = {
    findings: [],
    contributors: 0,
    regressions: 0,
  }
  for index, capacity in input.capacities {
    review_resource(result, queue.by_resource[index], capacity, input.end)
  }
  {
    start: input.start,
    end: input.end,
    findings: result.findings,
    regression_count: result.regressions,
  }
}
