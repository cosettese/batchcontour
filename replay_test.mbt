///|
test "replay clips observations and splits at exact run and capacity boundaries" {
  let batch = job("batch", "0 0 * * *", 1, 2, demands="{\"db\":6,\"gpu\":1}")
  let source = sample_input(
    "[]",
    "[\{batch}]",
    start="1970-01-01T00:01:00Z",
    end="1970-01-01T00:04:00Z",
    capacities="{\"db\":10,\"gpu\":2}",
  )
  let reduced = override_at("02", "03", 4)
  let input = @batchcontour.ReviewInput::from_json(
    with_overrides(source, "[\{reduced}]"),
  )
  let carried = runtime(
    "candidate", "batch", "z", "1970-01-01T00:00:30Z", "1970-01-01T00:02:10Z",
  )
  let overlaps = runtime(
    "candidate", "batch", "alpha", "1970-01-01T00:01:50Z", "1970-01-01T00:04:10Z",
  )
  let history = @batchcontour.RunHistory::from_json(
    history_input([carried, overlaps]),
  )
  let report = @batchcontour.replay_history(input, history, "candidate")
  assert_true(report.has_failures())
  guard report.summaries() is [summary] else {
    fail("expected only the overloaded resource")
  }
  assert_eq(summary.resource, "db")
  assert_eq(summary.overload_seconds, 70L)
  assert_eq(summary.peak_excess_units, 8L)
  assert_eq(summary.excess_unit_seconds, 200L)
  assert_eq(report.coverage()[0].sample_count, 2)
  let spans = report.overloads()
  assert_eq(spans.length(), 3)
  assert_eq(
    (spans[0].from_second, spans[0].until_second, spans[0].capacity),
    (110L, 120L, 10),
  )
  assert_eq(
    (spans[1].from_second, spans[1].until_second, spans[1].capacity),
    (120L, 130L, 4),
  )
  assert_eq(
    (spans[2].from_second, spans[2].until_second, spans[2].capacity),
    (130L, 180L, 4),
  )
  assert_eq((spans[0].resource, spans[0].occupied_units), ("db", 12L))
  assert_eq(spans[1].run_ids.to_owned(), ["alpha", "z"])
  assert_eq(spans[2].run_ids.to_owned(), ["alpha"])
  let reordered = @batchcontour.RunHistory::from_json(
    history_input([overlaps, carried]),
  )
  let canonical = @batchcontour.RunHistory::from_json(
    reordered.to_json().stringify(),
  )
  assert_eq(
    @batchcontour.replay_history(input, canonical, "candidate")
    .to_json()
    .stringify(),
    report.to_json().stringify(),
  )
}

///|
test "adjacent runs fit, while zero duration and out-of-window rows do not satisfy coverage" {
  let batch = job("batch", "0 0 * * *", 1, 2)
  let input = @batchcontour.ReviewInput::from_json(
    sample_input(
      "[\{batch}]",
      "[\{batch}]",
      start="1970-01-01T00:01:00Z",
      end="1970-01-01T00:03:00Z",
    ),
  )
  let runs = [
    runtime(
      "candidate", "batch", "a", "1970-01-01T00:00:30Z", "1970-01-01T00:01:27Z",
    ),
    runtime(
      "candidate", "batch", "b", "1970-01-01T00:01:27Z", "1970-01-01T00:03:10Z",
    ),
    runtime(
      "candidate", "batch", "zero", "1970-01-01T00:02:00Z", "1970-01-01T00:02:00Z",
    ),
    runtime(
      "candidate", "batch", "past", "1970-01-01T00:00:30Z", "1970-01-01T00:01:00Z",
    ),
    runtime(
      "candidate", "batch", "next", "1970-01-01T00:03:00Z", "1970-01-01T00:03:30Z",
    ),
    runtime(
      "baseline", "batch", "a", "1970-01-01T00:01:15Z", "1970-01-01T00:02:15Z",
    ),
  ]
  let history = @batchcontour.RunHistory::from_json(
    history_input(runs[:], min_samples=2),
  )
  let candidate = @batchcontour.replay_history(input, history, "candidate")
  assert_eq(candidate.overloads().length(), 0)
  assert_eq(candidate.coverage()[0].sample_count, 2)
  assert_false(candidate.has_failures())
  let json = candidate.to_json().stringify()
  assert_true(json.contains("\"outside_window\":2"))
  assert_true(json.contains("\"zero_duration\":1"))
  assert_true(json.contains("\"other_plan\":1"))
  let baseline = @batchcontour.replay_history(input, history, "baseline")
  assert_eq(baseline.overloads().length(), 0)
  assert_eq(baseline.coverage()[0].sample_count, 1)
  assert_true(baseline.has_failures())
}

///|
test "replay rejects an unknown selected job even outside the window and permits a corrected retry" {
  let batch = job("batch", "0 0 * * *", 1, 2)
  let input = @batchcontour.ReviewInput::from_json(
    sample_input("[]", "[\{batch}]"),
  )
  let wrong = runtime(
    "candidate", "missing", "bad", "1970-01-01T00:10:00Z", "1970-01-01T00:11:00Z",
  )
  let good = runtime(
    "candidate", "batch", "ok", "1970-01-01T00:00:10Z", "1970-01-01T00:00:20Z",
  )
  let history = @batchcontour.RunHistory::from_json(
    history_input([good, wrong]),
  )
  let refused = try {
    ignore(@batchcontour.replay_history(input, history, "candidate"))
    false
  } catch {
    @batchcontour.InvalidInput(path~, ..) => path == "$.runs[1].job"
    error => raise error
  }
  assert_true(refused)
  let fixed = @batchcontour.RunHistory::from_json(history_input([good]))
  assert_false(
    @batchcontour.replay_history(input, fixed, "candidate").has_failures(),
  )
  let invalid_plan = try {
    ignore(@batchcontour.replay_history(input, fixed, "both"))
    false
  } catch {
    @batchcontour.InvalidInput(path~, ..) => path == "plan"
    error => raise error
  }
  assert_true(invalid_plan)
}
