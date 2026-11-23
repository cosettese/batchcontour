///|
fn widened_jobs(
  jobs : Array[Job],
  checks : ArrayView[DurationCheck],
  min_samples : Int32,
) -> Array[Job] raise ReviewError {
  let updated : Array[Job] = []
  for index, job in jobs {
    let check = checks[index]
    let label = check.plan + "/" + job.id
    guard check.sample_count >= min_samples &&
      check.observed_minimum_seconds is Some(low) &&
      check.observed_maximum_seconds is Some(high) else {
      raise InvalidInput(
        path="$.runs",
        detail="\{label} has \{check.sample_count} observations; need \{min_samples}",
      )
    }
    guard low >= 60L && high <= max_duration_minutes.to_int64() * 60L else {
      raise InvalidInput(
        path="$.runs",
        detail="\{label} has observed durations \{low}–\{high} seconds outside the representable range of 60–604800 seconds",
      )
    }
    let lower = (low / 60L).to_int()
    let upper = ((high + 59L) / 60L).to_int()
    updated.push({
      ..job,
      min_minutes: if lower < job.min_minutes {
        lower
      } else {
        job.min_minutes
      },
      max_minutes: if upper > job.max_minutes {
        upper
      } else {
        job.max_minutes
      },
    })
  }
  updated
}

///|
/// Propose a new review whose duration bounds contain all accepted samples.
/// A proposal only widens existing bounds, rounds outward to full minutes,
/// and requires sufficient, representable evidence for each job and side.
pub fn widen_duration_bounds(
  input : ReviewInput,
  history : RunHistory,
) -> ReviewInput raise ReviewError {
  let evidence = check_durations(input, history)
  let checks = evidence.checks()
  let split = input.baseline.length()
  let baseline = widened_jobs(
    input.baseline,
    checks[:split],
    evidence.min_samples(),
  )
  let candidate = widened_jobs(
    input.candidate,
    checks[split:],
    evidence.min_samples(),
  )
  { ..input, baseline, candidate, }
}
