///|
priv enum EventKind {
  Start(Contribution)
  LoseGuarantee
  Finish
}

///|
priv struct Event {
  minute : Int64
  instance : Int32
  candidate : Bool
  kind : EventKind
}

///|
let max_events = 120_000

///|
priv struct EventQueue {
  by_resource : Array[Array[Event]]
  mut event_count : Int32
}

///|
fn EventQueue::add(
  self : EventQueue,
  resource : Int32,
  minute : Int64,
  instance : Int32,
  candidate : Bool,
  kind : EventKind,
) -> Unit raise ReviewError {
  guard self.event_count < max_events else {
    let path = if candidate { "$.candidate" } else { "$.baseline" }
    raise LimitExceeded(
      path~,
      detail="combined plans exceed 120,000 resource events; shorten the window or split the review",
    )
  }
  self.event_count += 1
  self.by_resource[resource].push({ minute, instance, candidate, kind, })
}

///|
fn expand_plan(
  queue : EventQueue,
  jobs : Array[Job],
  start : Int64,
  end : Int64,
  candidate : Bool,
) -> Unit raise ReviewError {
  guard !jobs.is_empty() else { return }
  let mut lookback = 0L
  for job in jobs {
    let duration = job.max_minutes.to_int64()
    if duration > lookback {
      lookback = duration
    }
  }
  let mut instance = 0
  // In minute units, a start exactly max_minutes before the window has ended.
  for minute = start - lookback + 1L; minute < end; minute = minute + 1L {
    let moment = utc_moment(minute)
    for job in jobs {
      let possible_end = minute + job.max_minutes.to_int64()
      if possible_end <= start {
        continue
      }
      let runs = match job.launch_overrides.get(minute) {
        Some(run) => run
        None => job.cron.matches(moment)
      }
      if !runs {
        continue
      }
      let guaranteed_end = minute + job.min_minutes.to_int64()
      let clipped_start = if minute < start { start } else { minute }
      for demand in job.demands {
        let resource = demand.resource_index
        queue.add(
          resource,
          clipped_start,
          instance,
          candidate,
          Start({
            job_id: job.id,
            start_minute: minute,
            units: demand.units,
            guaranteed: guaranteed_end > clipped_start,
          }),
        )
        if guaranteed_end > clipped_start &&
          guaranteed_end < possible_end &&
          guaranteed_end < end {
          queue.add(
            resource,
            guaranteed_end,
            instance,
            candidate,
            LoseGuarantee,
          )
        }
        if possible_end < end {
          queue.add(resource, possible_end, instance, candidate, Finish)
        }
      }
      instance += 1
    }
  }
}
