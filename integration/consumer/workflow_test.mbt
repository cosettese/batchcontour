///|
let external_review =
  #|{"schema":"batchcontour.input.v2",
  #|"window":{"start":"2026-11-23T02:00:00Z","end":"2026-11-23T02:05:00Z"},
  #|"capacities":{"workers":2},
  #|"capacity_overrides":[{"resource":"workers","start":"2026-11-23T02:02:00Z","end":"2026-11-23T02:04:00Z","units":1}],
  #|"baseline":[{"id":"hello","cron":"*/5 * * * *","min_minutes":1,"max_minutes":2,"demand":{"workers":1}}],
  #|"candidate":[{"id":"hello","cron":"* * * * *","min_minutes":1,"max_minutes":2,"demand":{"workers":1}}]}

///|
test "external module can review and verify its archived results" {
  let input = @batchcontour.ReviewInput::from_json(external_review)
  let artifact = @batchcontour.archive_capacity_review(input)
  let report = @batchcontour.verify_capacity_evidence(
    input,
    artifact.stringify(),
  )
  let rows = report.summaries()
  assert_true(report.has_regressions())
  assert_eq(rows[0].resource, "workers")
  assert_eq(rows[0].regression_minutes, 2L)
  assert_eq(rows[0].candidate.maximum_excess_unit_minutes, 2L)
  let policy = @batchcontour.CapacityPolicy::from_json(
    (
      #|{"schema":"batchcontour.capacity-policy.v1","resources":{"workers":{"possible_minutes":0}}}
    ),
  )
  let gate = @batchcontour.check_capacity_policy(input, policy)
  assert_true(gate.has_failures())
  assert_eq(gate.violations()[0].actual, 2L)
}

///|
test "external module can create a new review from runtime evidence" {
  let input = @batchcontour.ReviewInput::from_json(external_review)
  let history = @batchcontour.RunHistory::from_json(
    (
      #|{"schema":"batchcontour.history.v1","min_samples":1,"runs":[
      #|{"id":"old","plan":"baseline","job":"hello","started_at":"2026-11-20T02:00:00Z","finished_at":"2026-11-20T02:01:30Z"},
      #|{"id":"new","plan":"candidate","job":"hello","started_at":"2026-11-21T02:00:00Z","finished_at":"2026-11-21T02:02:23Z"}]}
    ),
  )
  assert_true(@batchcontour.check_durations(input, history).has_failures())
  let updated = @batchcontour.widen_duration_bounds(input, history)
  let reloaded = @batchcontour.ReviewInput::from_json(
    updated.to_json().stringify(),
  )
  assert_false(@batchcontour.check_durations(reloaded, history).has_failures())
  assert_true(@batchcontour.compare_capacity(reloaded).has_regressions())
}
