///|
fn repair_options(entries : String) -> String {
  let source =
    $|{"schema":"batchcontour.launch-repairs.v1","job":"etl","options":\{entries}}
  source
}

///|
test "repair preserves launch count and emits the first eligible passing schedule" {
  let backup = job("backup", "0 0 * * *", 2, 2)
  let etl = job("etl", "0 0 * * *", 2, 2)
  let source = sample_input("[\{backup}]", "[\{backup},\{etl}]")
  let input = @batchcontour.ReviewInput::from_json(source)
  assert_true(@batchcontour.compare_capacity(input).has_regressions())
  let options = repair_options(
    "[{\"id\":\"unchanged\",\"cron\":\"0 0 * * *\"},{\"id\":\"drop\",\"cron\":\"11 0 * * *\"},{\"id\":\"z-first\",\"cron\":\"2 0 * * *\"},{\"id\":\"a-later\",\"cron\":\"3 0 * * *\"}]",
  )
  let report = @batchcontour.evaluate_launch_repairs(input, options)
  assert_eq(report.results()[0].regression_count, Some(1))
  assert_eq(report.results()[1].launch_count, 0)
  assert_eq(report.results()[1].regression_count, None)
  guard report.recommendation() is Some((id, proposal)) else {
    fail("expected feasible schedule")
  }
  assert_eq(id, "z-first")
  let encoded = proposal.to_json().stringify()
  let reloaded = @batchcontour.ReviewInput::from_json(encoded)
  assert_false(@batchcontour.compare_capacity(reloaded).has_regressions())
  assert_true(@batchcontour.compare_capacity(input).has_regressions())
  assert_eq(
    @batchcontour.evaluate_launch_repairs(input, options).to_json().stringify(),
    report.to_json().stringify(),
  )
}

///|
test "repair launch counting honors explicit cancellations" {
  let task = launch_job("[{\"at\":\"2026-11-23T02:02:00Z\",\"run\":false}]")
  let input = @batchcontour.ReviewInput::from_json(
    launch_review("[]", "[\{task}]"),
  )
  let options = repair_options(
    "[{\"id\":\"cancelled\",\"cron\":\"2 2 * * *\"}]",
  ).replace(old="\"job\":\"etl\"", new="\"job\":\"hello\"")
  let report = @batchcontour.evaluate_launch_repairs(input, options)
  assert_eq(report.results()[0].launch_count, 0)
  assert_true(report.recommendation() is None)
}

///|
test "invalid options fail before yielding recommendations" {
  let task = job("etl", "0 0 * * *", 2, 2)
  let input = @batchcontour.ReviewInput::from_json(
    sample_input("[]", "[\{task}]"),
  )
  for
    options in [
      "[]", "[{\"id\":\"one\",\"cron\":\"61 0 * * *\"}]", "[{\"id\":\"one\",\"cron\":\"0 0 * * *\"},{\"id\":\"one\",\"cron\":\"1 0 * * *\"}]",
    ] {
    let refused = try {
      ignore(
        @batchcontour.evaluate_launch_repairs(input, repair_options(options)),
      )
      false
    } catch {
      @batchcontour.InvalidInput(path~, ..) => path.has_prefix("$.options")
      error => raise error
    }
    assert_true(refused)
  }
  let valid = repair_options("[{\"id\":\"ok\",\"cron\":\"1 0 * * *\"}]")
  assert_true(
    @batchcontour.evaluate_launch_repairs(input, valid).recommendation()
    is Some(_),
  )
}

///|
test "repair uses gate ceilings to eliminate a non-regressing option" {
  let backup = job("backup", "0 0 * * *", 2, 2)
  let etl = job("etl", "0 0 * * *", 2, 2)
  let jobs = "[\{backup},\{etl}]"
  let input = @batchcontour.ReviewInput::from_json(sample_input(jobs, jobs))
  let policy = capacity_policy("{\"db\":{\"possible_minutes\":1}}")
  let options = repair_options(
    "[{\"id\":\"keep\",\"cron\":\"0 0 * * *\"},{\"id\":\"drop\",\"cron\":\"11 0 * * *\"},{\"id\":\"move\",\"cron\":\"2 0 * * *\"}]",
  )
  let legacy = @batchcontour.evaluate_launch_repairs(input, options)
  guard legacy.recommendation() is Some(("keep", _)) else {
    fail("expected regression-only mode to keep the schedule")
  }
  assert_true(legacy.policy_violations("keep") is None)
  let report = @batchcontour.evaluate_launch_repairs_with_policy(
    input, options, policy,
  )
  assert_eq(report.results()[0].regression_count, Some(0))
  guard report.policy_violations("keep") is Some([violation]) else {
    fail("expected the same ceiling violation as the gate")
  }
  let from_gate = @batchcontour.check_capacity_policy(input, policy).violations()[0]
  assert_eq(
    (violation.resource, violation.metric, violation.limit, violation.actual),
    (from_gate.resource, from_gate.metric, from_gate.limit, from_gate.actual),
  )
  assert_true(report.policy_violations("drop") is None)
  assert_true(report.policy_violations("move") is Some([]))
  guard report.recommendation() is Some(("move", proposal)) else {
    fail("expected the first policy-compliant schedule")
  }
  assert_false(
    @batchcontour.check_capacity_policy(proposal, policy).has_failures(),
  )
  let only_keep = repair_options("[{\"id\":\"keep\",\"cron\":\"0 0 * * *\"}]")
  assert_true(
    @batchcontour.evaluate_launch_repairs_with_policy(input, only_keep, policy).recommendation()
    is None,
  )
  assert_eq(
    @batchcontour.evaluate_launch_repairs_with_policy(input, options, policy)
    .to_json()
    .stringify(),
    report.to_json().stringify(),
  )
}
