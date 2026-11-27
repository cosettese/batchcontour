///|
/// Merge histories from overlapping exports. A repeated identity within a plan
/// must describe the same job and interval, and all thresholds must agree.
pub fn merge_run_histories(
  histories : ArrayView[RunHistory],
) -> RunHistory raise ReviewError {
  guard histories.length() >= 2 && histories.length() <= 16 else {
    raise InvalidInput(path="$.histories", detail="expected 2–16 histories")
  }
  let samples = histories[0].min_samples
  let identities : Map[(String, String), Observation] = Map([])
  let combined : Array[Observation] = []
  for index, history in histories {
    let path = "$.histories[\{index}]"
    guard history.min_samples == samples else {
      raise InvalidInput(
        path=path + ".min_samples",
        detail="expected the shared threshold \{samples}",
      )
    }
    for run in history.runs {
      let key = (run.plan, run.run_id)
      if identities.get(key) is Some(prior) {
        guard run.job_id == prior.job_id &&
          run.start_second == prior.start_second &&
          run.elapsed_seconds == prior.elapsed_seconds else {
          raise InvalidInput(
            path=path + ".runs[\{run.source_index}]",
            detail="conflicting " + run.plan + " run ID " + run.run_id,
          )
        }
        continue
      }
      guard combined.length() < max_history_runs else {
        raise LimitExceeded(
          path="$.runs",
          detail="merged history exceeds 4,096 runs",
        )
      }
      identities[key] = run
      combined.push(run)
    }
  }
  let merged = normalized_history(samples, combined)
  for index, run in merged.runs {
    merged.runs[index] = { ..run, source_index: index, }
  }
  // Leave room for the line terminator emitted by the file CLI.
  guard merged.to_json().stringify().length() < max_input_units else {
    raise LimitExceeded(
      path="$.runs",
      detail="merged history exceeds the supported JSON size",
    )
  }
  merged
}
