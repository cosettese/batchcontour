///|
fn with_overrides(source : String, overrides : String) -> String {
  source.replace(
    old="\"schema\":\"batchcontour.input.v1\"",
    new="\"schema\":\"batchcontour.input.v2\",\"capacity_overrides\":\{overrides}",
  )
}

///|
fn override_at(
  start : String,
  end : String,
  units : Int32,
  resource~ : String = "db",
) -> String {
  let value =
    $|{"resource":"\{resource}","start":"1970-01-01T00:\{start}:00Z","end":"1970-01-01T00:\{end}:00Z","units":\{units}}
  value
}

///|
test "adjacent capacity windows split live demand and restore the default" {
  let backup = job("backup", "0 0 * * *", 6, 6, demands="{\"db\":6,\"gpu\":2}")
  let etl = job("etl", "0 0 * * *", 6, 6, demands="{\"db\":2}")
  let fixed = sample_input(
    "[\{backup}]",
    "[\{backup},\{etl}]",
    capacities="{\"db\":10,\"gpu\":2}",
  )
  let shutdown = override_at("02", "03", 0)
  let reduced = override_at("03", "04", 7)
  let unrelated = override_at("02", "04", 3, resource="gpu")
  let source = with_overrides(fixed, "[\{reduced},\{unrelated},\{shutdown}]")
  let input = @batchcontour.ReviewInput::from_json(source)
  let report = @batchcontour.compare_capacity(input)
  let spans = report.findings()
  assert_eq(spans.length(), 2)
  assert_eq(
    (
      spans[0].resource,
      spans[0].from_minute,
      spans[0].until_minute,
      spans[0].capacity,
    ),
    ("db", 2L, 3L, 0),
  )
  assert_eq(
    (spans[0].baseline.minimum_excess, spans[0].candidate.minimum_excess),
    (6L, 8L),
  )
  assert_eq(
    (
      spans[1].resource,
      spans[1].from_minute,
      spans[1].until_minute,
      spans[1].capacity,
    ),
    ("db", 3L, 4L, 7),
  )
  assert_eq(
    (spans[1].baseline.maximum_excess, spans[1].candidate.maximum_excess),
    (0L, 1L),
  )
  assert_true(spans[0].regression)
  assert_true(spans[1].regression)
  let reordered = @batchcontour.ReviewInput::from_json(
    with_overrides(fixed, "[\{shutdown},\{unrelated},\{reduced}]"),
  )
  let encoded = input.to_json().stringify()
  assert_eq(reordered.to_json().stringify(), encoded)
  let reparsed = @batchcontour.ReviewInput::from_json(encoded)
  assert_eq(reparsed.to_json().stringify(), encoded)
  assert_eq(
    @batchcontour.compare_capacity(reparsed).to_json().stringify(),
    report.to_json().stringify(),
  )
}

///|
test "capacity edges at the same minute as job events respect half-open intervals" {
  let finishes_at_shutdown = job("first", "59 23 * * *", 2, 2)
  let starts_at_restore = job("second", "3 0 * * *", 2, 2)
  let fixture = sample_input(
    "[]",
    "[\{finishes_at_shutdown},\{starts_at_restore}]",
  )
  let shutdown = override_at("01", "03", 0)
  let input = @batchcontour.ReviewInput::from_json(
    with_overrides(fixture, "[\{shutdown}]"),
  )
  let report = @batchcontour.compare_capacity(input)
  assert_eq(report.findings().length(), 0)
}

///|
test "reject ambiguous or unrepresentable overrides and accept a valid retry" {
  let fixed = sample_input("[]", "[]")
  let first = override_at("00", "05", 3)
  let overlapping = override_at("04", "06", 5)
  let unknown = override_at("00", "05", 2, resource="ghost")
  let outside = override_at("08", "11", 2)
  let empty = override_at("01", "01", 2)
  rejected(
    with_overrides(fixed, "[\{overlapping},\{first}]"),
    "$.capacity_overrides[0]",
  )
  rejected(
    with_overrides(fixed, "[\{unknown}]"),
    "$.capacity_overrides[0].resource",
  )
  rejected(with_overrides(fixed, "[\{outside}]"), "$.capacity_overrides[0]")
  rejected(with_overrides(fixed, "[\{empty}]"), "$.capacity_overrides[0]")
  rejected(
    with_overrides(fixed, "[\{first}]").replace(
      old="\"units\":3",
      new="\"units\":1.5",
    ),
    "$.capacity_overrides[0].units",
  )
  rejected(with_overrides(fixed, "null"), "$.capacity_overrides")
  rejected(
    fixed.replace(old="batchcontour.input.v1", new="batchcontour.input.v2"),
    "$.capacity_overrides",
  )
  rejected(
    with_overrides(fixed, "[]").replace(
      old="batchcontour.input.v2",
      new="batchcontour.input.v1",
    ),
    "$",
  )
  let over_limit = "[" + Array::make(513, first).join(",") + "]"
  let refused_limit = try {
    ignore(
      @batchcontour.ReviewInput::from_json(with_overrides(fixed, over_limit)),
    )
    false
  } catch {
    @batchcontour.LimitExceeded(path="$.capacity_overrides", ..) => true
    error => raise error
  }
  assert_true(refused_limit)
  let input = @batchcontour.ReviewInput::from_json(
    with_overrides(fixed, "[\{first}]"),
  )
  assert_false(@batchcontour.compare_capacity(input).has_regressions())
}

///|
test "an empty override timeline matches the prior fixed-budget report" {
  let load = job("run", "0 0 * * *", 3, 5, demands="{\"db\":11}")
  let fixed = sample_input("[]", "[\{load}]")
  let v1 = @batchcontour.ReviewInput::from_json(fixed)
  let v2 = @batchcontour.ReviewInput::from_json(with_overrides(fixed, "[]"))
  assert_true(v2.to_json().stringify().contains("\"capacity_overrides\":[]"))
  assert_eq(
    @batchcontour.compare_capacity(v1).to_json().stringify(),
    @batchcontour.compare_capacity(v2).to_json().stringify(),
  )
}
