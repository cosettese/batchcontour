///|
test "proposal rounds both bounds outward and preserves evidence and timed capacity" {
  let example = job("export", "0 0 * * *", 2, 2)
  let input = @batchcontour.ReviewInput::from_json(
    with_overrides(
      sample_input("[\{example}]", "[\{example}]"),
      "[" + override_at("01", "03", 2) + "]",
    ),
  )
  let before = input.to_json().stringify()
  let base = runtime(
    "baseline", "export", "base", "2024-01-01T00:00:00Z", "2024-01-01T00:02:00Z",
  )
  let fast = runtime(
    "candidate", "export", "fast", "2024-01-01T00:00:00Z", "2024-01-01T00:01:01Z",
  )
  let slow = runtime(
    "candidate", "export", "slow", "2024-01-01T00:00:00Z", "2024-01-01T00:02:23Z",
  )
  let history = @batchcontour.RunHistory::from_json(
    history_input([fast, slow, base]),
  )
  let original = @batchcontour.check_durations(input, history)
  assert_true(original.has_failures())
  let proposed = @batchcontour.widen_duration_bounds(input, history)
  let text = proposed.to_json().stringify()
  assert_eq(input.to_json().stringify(), before)
  assert_eq(
    text,
    before.replace(
      old="\"candidate\":[{\"id\":\"export\",\"cron\":\"0 0 * * *\",\"min_minutes\":2,\"max_minutes\":2",
      new="\"candidate\":[{\"id\":\"export\",\"cron\":\"0 0 * * *\",\"min_minutes\":1,\"max_minutes\":3",
    ),
  )
  assert_true(text != before)
  let reloaded = @batchcontour.ReviewInput::from_json(text)
  assert_false(@batchcontour.check_durations(reloaded, history).has_failures())
  assert_eq(
    @batchcontour.widen_duration_bounds(reloaded, history).to_json().stringify(),
    text,
  )
  let reordered = @batchcontour.RunHistory::from_json(
    history_input([base, slow, fast]),
  )
  assert_eq(
    @batchcontour.widen_duration_bounds(input, reordered).to_json().stringify(),
    text,
  )
  let report = @batchcontour.compare_capacity(reloaded)
  assert_true(report.has_regressions())
}

///|
test "in-range evidence preserves the existing longer bounds" {
  let example = job("export", "0 0 * * *", 1, 10)
  let input = @batchcontour.ReviewInput::from_json(
    sample_input("[]", "[\{example}]"),
  )
  let run = runtime(
    "candidate", "export", "one", "2024-01-01T00:00:00Z", "2024-01-01T00:04:59Z",
  )
  let history = @batchcontour.RunHistory::from_json(history_input([run]))
  assert_eq(
    @batchcontour.widen_duration_bounds(input, history).to_json().stringify(),
    input.to_json().stringify(),
  )
}

///|
test "unrepresentable or insufficient evidence prevents a complete proposal" {
  let example = job("export", "0 0 * * *", 2, 2)
  let input = @batchcontour.ReviewInput::from_json(
    sample_input("[\{example}]", "[\{example}]"),
  )
  let baseline = runtime(
    "baseline", "export", "base", "2024-01-01T00:00:00Z", "2024-01-01T00:03:01Z",
  )
  for
    evidence in [
      history_input([baseline]),
      history_input([
        baseline,
        runtime(
          "candidate", "export", "short", "2024-01-01T00:00:00Z", "2024-01-01T00:00:59Z",
        ),
      ]),
      history_input([
        baseline,
        runtime(
          "candidate", "export", "long", "2024-01-01T00:00:00Z", "2024-01-08T00:00:01Z",
        ),
      ]),
    ] {
    let history = @batchcontour.RunHistory::from_json(evidence)
    let refused = try {
      ignore(@batchcontour.widen_duration_bounds(input, history))
      false
    } catch {
      @batchcontour.InvalidInput(path="$.runs", detail~) =>
        detail.contains("candidate/export")
      error => raise error
    }
    assert_true(refused)
    // The baseline observation also requires a wider range. Refusal must not apply it.
    assert_true(
      @batchcontour.check_durations(input, history).checks()[0].violations.length() ==
      1,
    )
  }
}
