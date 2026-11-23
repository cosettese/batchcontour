///|
test "summary preserves the regression when total overload falls" {
  let old = job("backup", "0 0 * * *", 4, 4, demands="{\"db\":15}")
  let new = job("backup", "5 0 * * *", 1, 3, demands="{\"db\":12}")
  let plan = @batchcontour.ReviewInput::from_json(
    sample_input("[\{old}]", "[\{new}]", capacities="{\"db\":10,\"gpu\":8}"),
  )
  let report = @batchcontour.compare_capacity(plan)
  let rows = report.summaries()
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].resource, "db")
  assert_eq(rows[0].baseline.guaranteed_minutes, 4L)
  assert_eq(rows[0].baseline.possible_minutes, 4L)
  assert_eq(rows[0].baseline.minimum_excess_unit_minutes, 20L)
  assert_eq(rows[0].candidate.guaranteed_minutes, 1L)
  assert_eq(rows[0].candidate.possible_minutes, 3L)
  assert_eq(rows[0].candidate.peak_minimum_excess, 2L)
  assert_eq(rows[0].candidate.peak_maximum_excess, 2L)
  assert_eq(rows[0].candidate.minimum_excess_unit_minutes, 2L)
  assert_eq(rows[0].candidate.maximum_excess_unit_minutes, 6L)
  assert_eq(rows[0].regression_minutes, 3L)
  assert_true(report.has_regressions())
  assert_true(
    report.summary_json().stringify().contains("\"verdict\":\"blocked\""),
  )
}

///|
test "summary counts adjacent capacity bands once and retains per-resource units" {
  let load = job("job-a", "0 0 * * *", 4, 4, demands="{\"db\":9,\"gpu\":6}")
  let request = sample_input(
    "[\{load}]",
    "[\{load}]",
    capacities="{\"gpu\":2,\"db\":15}",
  )
  let first = override_at("00", "02", 8)
  let second = override_at("02", "04", 7)
  let source = with_overrides(request, "[\{second},\{first}]")
  let input = @batchcontour.ReviewInput::from_json(source)
  let report = @batchcontour.compare_capacity(input)
  let rows = report.summaries()
  assert_eq(rows.length(), 2)
  assert_eq((rows[0].resource, rows[1].resource), ("db", "gpu"))
  assert_eq(
    (
      rows[0].candidate.maximum_excess_unit_minutes,
      rows[1].candidate.maximum_excess_unit_minutes,
    ),
    (6L, 16L),
  )
  assert_eq(
    (rows[0].candidate.possible_minutes, rows[1].candidate.possible_minutes),
    (4L, 4L),
  )
  assert_eq(rows[0].regression_minutes, 0L)
  assert_false(report.has_regressions())
  let reversed = @batchcontour.ReviewInput::from_json(
    with_overrides(request, "[\{first},\{second}]"),
  )
  assert_eq(
    @batchcontour.compare_capacity(reversed).summary_json().stringify(),
    report.summary_json().stringify(),
  )
}

///|
test "fully budgeted reviews have an empty summary and existing detailed report" {
  let job = job("job-a", "0 0 * * *", 1, 1, demands="{\"db\":10}")
  let input = @batchcontour.ReviewInput::from_json(
    sample_input("[]", "[\{job}]"),
  )
  let report = @batchcontour.compare_capacity(input)
  assert_eq(report.summaries().length(), 0)
  assert_true(report.summary_json().stringify().contains("\"resources\":[]"))
  assert_true(report.to_json().stringify().contains("\"findings\":[]"))
}
