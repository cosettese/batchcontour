///|
fn history_input(runs : ArrayView[String], min_samples~ : Int32 = 1) -> String {
  let entries = runs.to_owned().join(",")
  let text =
    $|{"schema":"batchcontour.history.v1","min_samples":\{min_samples},"runs":[\{entries}]}
  text
}

///|
fn runtime(
  plan : String,
  job : String,
  id : String,
  start : String,
  finish : String,
) -> String {
  let text =
    $|{"plan":"\{plan}","job":"\{job}","id":"\{id}","started_at":"\{start}","finished_at":"\{finish}"}
  text
}

///|
test "duration checks keep history separated by job and plan and name the outliers" {
  let old = job("export", "0 0 * * *", 1, 2)
  let new = job("export", "0 0 * * *", 2, 4)
  let new_job = job("new-job", "0 0 * * *", 1, 1)
  let input = @batchcontour.ReviewInput::from_json(
    sample_input("[\{old}]", "[\{new},\{new_job}]"),
  )
  let observations = [
    runtime(
      "baseline", "export", "first", "2024-02-29T23:59:30Z", "2024-03-01T00:00:30Z",
    ),
    runtime(
      "baseline", "export", "early", "2024-02-29T04:00:00Z", "2024-02-29T04:00:59Z",
    ),
    runtime(
      "candidate", "export", "late", "2024-02-29T04:00:00Z", "2024-02-29T04:04:01Z",
    ),
  ]
  let history = @batchcontour.RunHistory::from_json(
    history_input(observations[:], min_samples=2),
  )
  let report = @batchcontour.check_durations(input, history)
  let checks = report.checks()
  assert_true(report.has_failures())
  assert_eq(checks.length(), 3)
  assert_eq(
    (checks[0].plan, checks[0].job_id, checks[0].sample_count),
    ("baseline", "export", 2),
  )
  assert_eq(checks[0].observed_minimum_seconds, Some(59L))
  assert_eq(checks[0].observed_maximum_seconds, Some(60L))
  assert_eq(
    (checks[0].violations[0].run_id, checks[0].violations[0].reason),
    ("early", "below_minimum"),
  )
  assert_eq(checks[1].violations[0].elapsed_seconds, 241L)
  assert_eq(checks[1].violations[0].reason, "above_maximum")
  assert_eq(checks[2].job_id, "new-job")
  assert_eq(checks[2].sample_count, 0)
  assert_eq(checks[2].observed_minimum_seconds, None)
  assert_true(
    report.to_json().stringify().contains("\"insufficient_samples\":true"),
  )
}

///|
test "inclusive duration extremes pass and history round-trips canonically" {
  let example = job("export", "0 0 * * *", 1, 2)
  let plan = @batchcontour.ReviewInput::from_json(
    sample_input("[\{example}]", "[\{example}]"),
  )
  let first = runtime(
    "baseline", "export", "same", "2024-02-28T01:00:30Z", "2024-02-28T01:01:30Z",
  )
  let second = runtime(
    "candidate", "export", "same", "2024-02-28T23:59:30Z", "2024-02-29T00:01:30Z",
  )
  let history = @batchcontour.RunHistory::from_json(
    history_input([second, first]),
  )
  let canonical = history.to_json().stringify()
  let reverse = @batchcontour.RunHistory::from_json(
    history_input([first, second]),
  )
  assert_eq(reverse.to_json().stringify(), canonical)
  let restored = @batchcontour.RunHistory::from_json(canonical)
  assert_eq(restored.to_json().stringify(), canonical)
  let report = @batchcontour.check_durations(plan, restored)
  assert_false(report.has_failures())
  assert_eq(report.checks()[0].observed_minimum_seconds, Some(60L))
  assert_eq(report.checks()[1].observed_maximum_seconds, Some(120L))
  assert_eq(
    @batchcontour.check_durations(plan, reverse).to_json().stringify(),
    report.to_json().stringify(),
  )
}

///|
test "sample count gates a job even when all observed runs fit" {
  let example = job("export", "0 0 * * *", 1, 1)
  let plan = @batchcontour.ReviewInput::from_json(
    sample_input("[]", "[\{example}]"),
  )
  let run = runtime(
    "candidate", "export", "one", "2024-01-01T00:00:00Z", "2024-01-01T00:01:00Z",
  )
  let history = @batchcontour.RunHistory::from_json(
    history_input([run], min_samples=2),
  )
  let report = @batchcontour.check_durations(plan, history)
  assert_true(report.has_failures())
  assert_eq(report.min_samples(), 2)
  assert_eq(report.checks()[0].violations.length(), 0)
  assert_true(
    report.to_json().stringify().contains("\"insufficient_samples\":true"),
  )
}

///|
fn history_rejected(text : String, expected_path : String) -> Unit raise {
  let path = try {
    ignore(@batchcontour.RunHistory::from_json(text))
    None
  } catch {
    @batchcontour.InvalidInput(path~, ..) => Some(path)
    error => raise error
  }
  assert_eq(path, Some(expected_path))
}

///|
test "reject malformed history, duplicate run identities and oversized input" {
  let start = "2024-02-29T10:00:02Z"
  let finish = "2024-02-29T10:01:02Z"
  let good = runtime("baseline", "export", "run-x", start, finish)
  let reversed = runtime("baseline", "export", "run-x", finish, start)
  history_rejected(history_input([reversed]), "$.runs[0].finished_at")
  for
    invalid in [
      "2024-02-29T10:01:60Z", "2023-02-29T10:01:00Z", "2024-02-29T10:01:00.1Z", "2024-02-29T10:01:00+00:00",
    ] {
    history_rejected(
      history_input([runtime("baseline", "export", "run", start, invalid)]),
      "$.runs[0].finished_at",
    )
  }
  history_rejected(
    history_input([runtime("staging", "export", "run", start, finish)]),
    "$.runs[0].plan",
  )
  history_rejected(history_input([good, good]), "$.runs[1].id")
  history_rejected(history_input([good], min_samples=0), "$.min_samples")
  history_rejected(
    history_input([good]).replace(old="\"id\":", new="\"extra\":true,\"id\":"),
    "$.runs[0]",
  )
  history_rejected(
    history_input([good]).replace(old="\"id\":", new="\"id\":\"copy\",\"id\":"),
    "$",
  )
  let too_many = Array::make(4097, "null")
  let limit = try {
    ignore(@batchcontour.RunHistory::from_json(history_input(too_many[:])))
    false
  } catch {
    @batchcontour.LimitExceeded(path="$.runs", ..) => true
    error => raise error
  }
  assert_true(limit)
  let valid = @batchcontour.RunHistory::from_json(history_input([good]))
  assert_true(valid.to_json().stringify().contains(finish))
}

///|
test "reject observations for a job absent from the labelled plan and recover" {
  let example = job("export", "0 0 * * *", 1, 2)
  let plan = @batchcontour.ReviewInput::from_json(
    sample_input("[]", "[\{example}]"),
  )
  let old = runtime(
    "baseline", "export", "one", "2024-01-01T03:30:00Z", "2024-01-01T03:32:00Z",
  )
  let history = @batchcontour.RunHistory::from_json(history_input([old]))
  let rejected = try {
    ignore(@batchcontour.check_durations(plan, history))
    false
  } catch {
    @batchcontour.InvalidInput(path="$.runs[0].job", ..) => true
    error => raise error
  }
  assert_true(rejected)
  let run = old.replace(old="\"baseline\"", new="\"candidate\"")
  let valid = @batchcontour.RunHistory::from_json(history_input([run]))
  assert_false(@batchcontour.check_durations(plan, valid).has_failures())
}
