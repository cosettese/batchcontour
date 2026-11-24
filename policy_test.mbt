///|
fn capacity_policy(resources : String) -> @batchcontour.CapacityPolicy raise {
  let source =
    $|{"schema":"batchcontour.capacity-policy.v1","resources":\{resources}}
  @batchcontour.CapacityPolicy::from_json(source)
}

///|
test "an absolute ceiling can block pre-existing overload" {
  let task = job("sync", "0 0 * * *", 1, 3, demands="{\"db\":12}")
  let plan = @batchcontour.ReviewInput::from_json(
    sample_input("[\{task}]", "[\{task}]"),
  )
  let policy = capacity_policy(
    "{\"db\":{\"possible_minutes\":2,\"guaranteed_minutes\":1,\"peak_maximum_excess\":2,\"maximum_excess_unit_minutes\":5}}",
  )
  let gate = @batchcontour.check_capacity_policy(plan, policy)
  assert_false(gate.regression_blocked())
  assert_true(gate.has_failures())
  let findings = gate.violations()
  assert_eq(findings.length(), 2)
  assert_eq(
    (
      findings[0].resource,
      findings[0].metric,
      findings[0].limit,
      findings[0].actual,
    ),
    ("db", "possible_minutes", 2L, 3L),
  )
  assert_eq(
    (findings[1].metric, findings[1].limit, findings[1].actual),
    ("maximum_excess_unit_minutes", 5L, 6L),
  )
  let equal = capacity_policy(
    "{\"db\":{\"possible_minutes\":3,\"guaranteed_minutes\":1,\"peak_maximum_excess\":2,\"maximum_excess_unit_minutes\":6}}",
  )
  assert_false(@batchcontour.check_capacity_policy(plan, equal).has_failures())
}

///|
test "ceilings cannot suppress a regression and safe resources have zero metrics" {
  let task = job("sync", "0 0 * * *", 1, 3, demands="{\"db\":12}")
  let plan = @batchcontour.ReviewInput::from_json(
    sample_input("[]", "[\{task}]", capacities="{\"gpu\":0,\"db\":10}"),
  )
  let policy = capacity_policy(
    "{\"gpu\":{\"possible_minutes\":0},\"db\":{\"maximum_excess_unit_minutes\":6}}",
  )
  let gate = @batchcontour.check_capacity_policy(plan, policy)
  assert_true(gate.regression_blocked())
  assert_true(gate.has_failures())
  assert_eq(gate.violations().length(), 0)
}

///|
test "round trip preserves exact policy maxima, order and explicit zero" {
  let first = capacity_policy(
    "{\"zz\":{\"possible_minutes\":0},\"aa\":{\"maximum_excess_unit_minutes\":9007199254740991,\"guaranteed_minutes\":2}}",
  )
  let second = capacity_policy(
    "{\"aa\":{\"guaranteed_minutes\":2,\"maximum_excess_unit_minutes\":9007199254740991},\"zz\":{\"possible_minutes\":0}}",
  )
  let canon = first.to_json().stringify()
  assert_true(
    canon.contains("\"maximum_excess_unit_minutes\":9007199254740991"),
  )
  assert_true(canon.contains("\"possible_minutes\":0"))
  assert_eq(second.to_json().stringify(), canon)
  assert_eq(
    @batchcontour.CapacityPolicy::from_json(canon).to_json().stringify(),
    canon,
  )
}

///|
test "malformed ceilings and unknown resources fail without poisoning later checks" {
  for
    invalid in [
      "{}", "{\"db\":{}}", "{\"db\":{\"possible\":0}}", "{\"db\":{\"possible_minutes\":1e0}}",
      "{\"db\":{\"possible_minutes\":-1}}", "{\"db\":{\"possible_minutes\":9007199254740992}}",
      "{\"db\":{\"possible_minutes\":1,\"possible_minutes\":2}}",
    ] {
    let refused = try {
      ignore(capacity_policy(invalid))
      false
    } catch {
      @batchcontour.InvalidInput(..) => true
      error => raise error
    }
    assert_true(refused)
  }
  let plan = @batchcontour.ReviewInput::from_json(sample_input("[]", "[]"))
  let wrong = capacity_policy("{\"gpu\":{\"possible_minutes\":0}}")
  let refused = try {
    ignore(@batchcontour.check_capacity_policy(plan, wrong))
    false
  } catch {
    @batchcontour.InvalidInput(path="$.resources.gpu", ..) => true
    error => raise error
  }
  assert_true(refused)
  let valid = capacity_policy("{\"db\":{\"possible_minutes\":0}}")
  assert_false(@batchcontour.check_capacity_policy(plan, valid).has_failures())
}
