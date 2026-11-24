///|
fn scenario_input(entries : String) -> String {
  let document =
    $|{"schema":"batchcontour.capacity-scenarios.v1","scenarios":\{entries}}
  document
}

///|
test "scenario results equal separate reviews and are ordered by ID" {
  let task = job("worker", "* * * * *", 1, 2, demands="{\"db\":1}")
  let base = sample_input("[]", "[\{task}]", capacities="{\"db\":9}")
  let input = @batchcontour.ReviewInput::from_json(base)
  let calm = "{\"id\":\"normal\",\"capacities\":{\"db\":2},\"capacity_overrides\":[]}"
  let reduction = override_at("03", "05", 1)
  let maintenance =
    $|{"id":"maintenance","capacities":{"db":2},"capacity_overrides":[\{reduction}]}
  let matrix = @batchcontour.compare_capacity_scenarios(
    input,
    scenario_input("[\{calm},\{maintenance}]"),
  )
  assert_true(matrix.has_regressions())
  let results = matrix.results()
  assert_eq((results[0].id, results[1].id), ("maintenance", "normal"))
  assert_eq(results[1].regression_count, 0)
  assert_eq(results[1].resources.length(), 0)
  let standalone = with_overrides(
    base.replace(old="\"db\":9", new="\"db\":2"),
    "[\{reduction}]",
  )
  let report = @batchcontour.compare_capacity(
    @batchcontour.ReviewInput::from_json(standalone),
  )
  assert_eq(results[0].regression_count, report.findings().length())
  assert_eq(results[0].resources[0].regression_minutes, 2L)
  assert_eq(
    results[0].resources[0].candidate.maximum_excess_unit_minutes,
    report.summaries()[0].candidate.maximum_excess_unit_minutes,
  )
  let reordered = @batchcontour.compare_capacity_scenarios(
    input,
    scenario_input("[\{maintenance},\{calm}]"),
  )
  assert_eq(reordered.to_json().stringify(), matrix.to_json().stringify())
}

///|
test "require complete budgets and explicit overrides, then accept valid data" {
  let input = @batchcontour.ReviewInput::from_json(
    sample_input("[]", "[]", capacities="{\"gpu\":1,\"db\":1}"),
  )
  let valid = "{\"id\":\"one\",\"capacities\":{\"gpu\":0,\"db\":0},\"capacity_overrides\":[]}"
  for
    invalid in [
      "[]",
      "[{\"id\":\"missing\",\"capacities\":{\"db\":1},\"capacity_overrides\":[]}]",
      "[{\"id\":\"extra\",\"capacities\":{\"gpu\":1,\"db\":1,\"api\":1},\"capacity_overrides\":[]}]",
      "[{\"id\":\"bad\",\"capacities\":{\"gpu\":1,\"db\":1}}]",
      "[\{valid},\{valid}]",
    ] {
    let rejected = try {
      ignore(
        @batchcontour.compare_capacity_scenarios(input, scenario_input(invalid)),
      )
      false
    } catch {
      @batchcontour.InvalidInput(..) => true
      error => raise error
    }
    assert_true(rejected)
  }
  assert_false(
    @batchcontour.compare_capacity_scenarios(
      input,
      scenario_input("[\{valid}]"),
    ).has_regressions(),
  )
}

///|
test "an uncomputable scenario rejects the whole batch and names its budget" {
  let dense = job("dense", "* * * * *", 30, 31)
  let input = @batchcontour.ReviewInput::from_json(
    sample_input(
      "[]",
      "[\{dense}]",
      start="2024-01-01T00:00:00Z",
      end="2024-01-04T00:00:00Z",
    ),
  )
  let calm = "{\"id\":\"safe\",\"capacities\":{\"db\":1000},\"capacity_overrides\":[]}"
  let costly = "{\"id\":\"z-outage\",\"capacities\":{\"db\":0},\"capacity_overrides\":[]}"
  let refused = try {
    ignore(
      @batchcontour.compare_capacity_scenarios(
        input,
        scenario_input("[\{calm},\{costly}]"),
      ),
    )
    false
  } catch {
    @batchcontour.LimitExceeded(path="$.report", detail~) =>
      detail.contains("z-outage")
    error => raise error
  }
  assert_true(refused)
  assert_false(
    @batchcontour.compare_capacity_scenarios(input, scenario_input("[\{calm}]")).has_regressions(),
  )
}
