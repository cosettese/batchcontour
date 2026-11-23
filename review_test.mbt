///|
fn sample_input(
  before : String,
  after : String,
  capacities~ : String = "{\"db\":10}",
  start~ : String = "1970-01-01T00:00:00Z",
  end~ : String = "1970-01-01T00:10:00Z",
) -> String {
  let source =
    $|{"schema":"batchcontour.input.v1","window":{"start":"\{start}","end":"\{end}"},"capacities":\{capacities},"baseline":\{before},"candidate":\{after}}
  source
}

///|
fn job(
  id : String,
  cron : String,
  low : Int32,
  high : Int32,
  demands~ : String = "{\"db\":6}",
) -> String {
  let source =
    $|{"id":"\{id}","cron":"\{cron}","min_minutes":\{low},"max_minutes":\{high},"demand":\{demands}}
  source
}

///|
test "staggered starts span guaranteed and possible overload" {
  let backup = job("backup", "0 0 * * *", 5, 8)
  let etl = job("etl", "3 0 * * *", 5, 5)
  let source = sample_input("[\{backup}]", "[\{etl},\{backup}]")
  let report = @batchcontour.compare_capacity(
    @batchcontour.ReviewInput::from_json(source),
  )
  assert_true(report.has_regressions())
  let spans = report.findings()
  assert_eq(spans.length(), 2)
  assert_eq((spans[0].from_minute, spans[0].until_minute), (3L, 5L))
  assert_eq(
    (spans[0].candidate.minimum_excess, spans[0].candidate.maximum_excess),
    (2L, 2L),
  )
  assert_eq((spans[1].from_minute, spans[1].until_minute), (5L, 8L))
  assert_eq(
    (spans[1].candidate.minimum_excess, spans[1].candidate.maximum_excess),
    (0L, 2L),
  )
  assert_eq(spans[1].candidate.contributors[0].job_id, "backup")
  assert_false(spans[1].candidate.contributors[0].guaranteed)
  assert_true(spans[1].candidate.contributors[1].guaranteed)
}

///|
test "lookback carries a previous day instance with its original start" {
  let before_epoch = job("nightly", "58 23 * * *", 1, 4)
  let new_job = job("report", "0 0 * * *", 3, 3)
  let source = sample_input("[\{before_epoch}]", "[\{before_epoch},\{new_job}]")
  let report = @batchcontour.compare_capacity(
    @batchcontour.ReviewInput::from_json(source),
  )
  let spans = report.findings()
  assert_eq(spans.length(), 1)
  assert_eq((spans[0].from_minute, spans[0].until_minute), (0L, 2L))
  assert_eq(spans[0].candidate.contributors[0].start_minute, -2L)
  assert_false(spans[0].candidate.contributors[0].guaranteed)
  assert_true(report.to_json().stringify().contains("1969-12-31T23:58:00Z"))
}

///|
test "touching intervals and exact capacity do not count as overload" {
  let first = job("first", "0 0 * * *", 5, 5, demands="{\"db\":10}")
  let second = job("second", "5 0 * * *", 5, 5, demands="{\"db\":10}")
  let outside = job("outside", "10 0 * * *", 1, 10, demands="{\"db\":20}")
  let finished_at_start = job(
    "carry",
    "59 23 * * *",
    1,
    1,
    demands="{\"db\":20}",
  )
  let source = sample_input(
    "[]",
    "[\{first},\{second},\{outside},\{finished_at_start}]",
  )
  let report = @batchcontour.compare_capacity(
    @batchcontour.ReviewInput::from_json(source),
  )
  assert_eq(report.findings().length(), 0)
  assert_false(report.has_regressions())
}

///|
test "unchanged excess stays visible and only new or aggravated intervals block" {
  let old = job("load", "0 0 * * *", 5, 5, demands="{\"db\":12}")
  let extended = job("load", "0 0 * * *", 5, 6, demands="{\"db\":12}")
  let same = sample_input("[\{old}]", "[\{old}]")
  let report = @batchcontour.compare_capacity(
    @batchcontour.ReviewInput::from_json(same),
  )
  assert_false(report.has_regressions())
  assert_eq(report.findings().length(), 1)
  assert_eq(report.findings()[0].candidate.minimum_excess, 2L)
  let increase = sample_input("[\{old}]", "[\{extended}]")
  let report = @batchcontour.compare_capacity(
    @batchcontour.ReviewInput::from_json(increase),
  )
  assert_eq(report.findings().length(), 2)
  assert_false(report.findings()[0].regression)
  assert_true(report.findings()[1].regression)
  assert_eq(report.findings()[1].from_minute, 5L)
  let improvement = sample_input("[\{extended}]", "[\{old}]")
  let report = @batchcontour.compare_capacity(
    @batchcontour.ReviewInput::from_json(improvement),
  )
  assert_false(report.has_regressions())
  assert_eq(report.findings()[1].candidate.maximum_excess, 0L)
}

///|
test "round trip preserves data and source order does not affect output" {
  let a = job("a", "0\t0 * * *", 3, 3, demands="{\"db\":12,\"gpu\":2}")
  // The JSON representation needs an escaped tab, which decodes to a cron separator.
  let a = a.replace(old="\t", new="\\t")
  let b = job("b", "1 0 * * *", 2, 3, demands="{\"gpu\":8,\"db\":7}")
  let input = @batchcontour.ReviewInput::from_json(
    sample_input("[]", "[\{a},\{b}]", capacities="{\"gpu\":4,\"db\":10}"),
  )
  let reordered = @batchcontour.ReviewInput::from_json(
    sample_input("[]", "[\{b},\{a}]", capacities="{\"db\":10,\"gpu\":4}"),
  )
  let canonical = input.to_json().stringify()
  let decoded = @batchcontour.ReviewInput::from_json(canonical)
  assert_eq(decoded.to_json().stringify(), canonical)
  assert_eq(reordered.to_json().stringify(), canonical)
  assert_true(canonical.contains("0\\t0 * * *"))
  let report = @batchcontour.compare_capacity(input)
  assert_eq(
    report.to_json().stringify(),
    @batchcontour.compare_capacity(reordered).to_json().stringify(),
  )
  assert_eq(report.findings()[0].resource, "db")
  assert_eq(report.findings()[report.findings().length() - 1].resource, "gpu")
}

///|
fn rejected(source : String, path : String) -> Unit raise {
  let problem = try {
    ignore(@batchcontour.ReviewInput::from_json(source))
    None
  } catch {
    @batchcontour.InvalidInput(path~, detail~) => Some((path, detail))
    error => raise error
  }
  guard problem is Some((actual, detail)) else {
    fail("accepted invalid input")
  }
  assert_eq(actual, path)
  assert_true(!detail.is_empty())
}

///|
test "reject unknown, duplicate and missing fields and recover" {
  let valid = sample_input("[]", "[]")
  rejected("{", "$")
  rejected(
    valid.replace(old="\"schema\":", new="\"unknown\":true,\"schema\":"),
    "$",
  )
  rejected(valid.replace(old="\"capacities\":", new="\"capacitiez\":"), "$")
  rejected(
    valid.replace(old="{\"db\":10}", new="{\"db\":10,\"\\u0064b\":0}"),
    "$",
  )
  rejected(
    sample_input("[]", "[{\"id\":\"no-duration\"}]"),
    "$.candidate[0].cron",
  )
  let example = job("repeat", "* * * * *", 1, 1)
  rejected(sample_input("[]", "[\{example},\{example}]"), "$.candidate[1].id")
  assert_false(
    @batchcontour.compare_capacity(@batchcontour.ReviewInput::from_json(valid)).has_regressions(),
  )
}

///|
test "reject unsupported numbers, resource names and cron dialects" {
  for value in ["1.0", "1e0", "1.00000000000000001", "-0", "1000001", "\"10\""] {
    rejected(
      sample_input("[]", "[]", capacities="{\"db\":\{value}}"),
      "$.capacities.db",
    )
  }
  for
    cron in [
      "0 0 0 * * *", "@hourly", "0 0 ? * *", "0 0 1 JAN *", "*/2147483647 * * * *",
      "60 0 * * *", "*/0 * * * *", "1,,2 * * * *",
    ] {
    let example = job("test", cron, 1, 1)
    rejected(sample_input("[]", "[\{example}]"), "$.candidate[0].cron")
  }
  let missing = job("test", "* * * * *", 1, 1, demands="{\"missing\":1}")
  rejected(sample_input("[]", "[\{missing}]"), "$.candidate[0].demand")
  let inverted = job("test", "* * * * *", 4, 2)
  rejected(sample_input("[]", "[\{inverted}]"), "$.candidate[0].max_minutes")
}

///|
test "strict UTC dates cover leap days, the maximum window and invalid bounds" {
  for
    date in [
      "2023-02-29T00:00:00Z", "2024-02-30T00:00:00Z", "2024-01-01T24:00:00Z", "2024-01-01T00:00:01Z",
      "2024-01-01T00:00:00+00:00", "2100-01-01T00:00:00Z",
    ] {
    rejected(sample_input("[]", "[]", start=date), "$.window.start")
  }
  rejected(
    sample_input(
      "[]",
      "[]",
      start="2024-02-01T00:00:00Z",
      end="2024-03-03T00:01:00Z",
    ),
    "$.window",
  )
  rejected(sample_input("[]", "[]", end="1970-01-01T00:00:00Z"), "$.window")
  let leap = job("leap", "0 0 29 2 *", 1, 1)
  let source = sample_input(
    "[]",
    "[\{leap}]",
    start="2024-02-01T00:00:00Z",
    end="2024-03-03T00:00:00Z",
    capacities="{\"db\":0}",
  )
  let report = @batchcontour.compare_capacity(
    @batchcontour.ReviewInput::from_json(source),
  )
  assert_eq(report.findings().length(), 1)
  assert_true(report.to_json().stringify().contains("2024-02-29T00:00:00Z"))
}

///|
test "day of month or weekday fires on either restricted field" {
  let friday_or_thirteenth = job("run", "0 0 13 * 5", 1, 1)
  let source = sample_input(
    "[]",
    "[\{friday_or_thirteenth}]",
    start="2024-05-10T00:00:00Z",
    end="2024-05-15T00:00:00Z",
    capacities="{\"db\":0}",
  )
  let report = @batchcontour.compare_capacity(
    @batchcontour.ReviewInput::from_json(source),
  )
  assert_eq(report.findings().length(), 2)
  let encoded = report.to_json().stringify()
  assert_true(encoded.contains("2024-05-10T00:01:00Z"))
  assert_true(encoded.contains("2024-05-13T00:00:00Z"))
}

///|
test "event and evidence limits reject oversized comparisons without poisoning subsequent calls" {
  let dense = job("dense", "* * * * *", 1, 2)
  let long = sample_input(
    "[]",
    "[\{dense}]",
    start="2024-01-01T00:00:00Z",
    end="2024-02-01T00:00:00Z",
  )
  let bounded = @batchcontour.ReviewInput::from_json(long)
  let event_failed = try {
    ignore(@batchcontour.compare_capacity(bounded))
    false
  } catch {
    @batchcontour.LimitExceeded(path="$.candidate", ..) => true
    error => raise error
  }
  assert_true(event_failed)
  let many_witnesses = job("dense", "* * * * *", 30, 31)
  let within_event_cap = sample_input(
    "[]",
    "[\{many_witnesses}]",
    start="2024-01-01T00:00:00Z",
    end="2024-01-04T00:00:00Z",
  )
  let evidence_failed = try {
    ignore(
      @batchcontour.compare_capacity(
        @batchcontour.ReviewInput::from_json(within_event_cap),
      ),
    )
    false
  } catch {
    @batchcontour.LimitExceeded(path="$.report", ..) => true
    error => raise error
  }
  assert_true(evidence_failed)
  let short = sample_input("[]", "[\{dense}]")
  let report = @batchcontour.compare_capacity(
    @batchcontour.ReviewInput::from_json(short),
  )
  assert_true(report.has_regressions())
}

///|
// Independent minute oracle for these fixtures. All reviewed minutes and
// potential launches lie in the same UTC hour, so */n is integer divisibility.
fn minute_oracle(
  at : Int32,
  jobs : ArrayView[(String, Int32, Int32, Int32, Int32)],
) -> (Int64, Int64, Array[(String, Int64, Int32, Bool)]) {
  let mut minimum = 0L
  let mut maximum = 0L
  let active : Array[(String, Int64, Int32, Bool)] = []
  for record in jobs {
    let (id, period, low, high, units) = record
    for start in 0..<=at {
      let age = at - start
      if start % period == 0 && age < high {
        let guaranteed = age < low
        maximum += units.to_int64()
        if guaranteed {
          minimum += units.to_int64()
        }
        active.push((id, start.to_int64(), units, guaranteed))
      }
    }
  }
  (minimum, maximum, active)
}

///|
fn oracle_jobs(
  jobs : ArrayView[(String, Int32, Int32, Int32, Int32)],
) -> String {
  let entries = jobs.map(record => {
    let (id, period, low, high, units) = record
    job(id, "*/\{period} * * * *", low, high, demands="{\"db\":\{units}}")
  })
  "[" + entries.join(",") + "]"
}

///|
fn check_oracle(
  actual : @batchcontour.Load,
  expected : (Int64, Int64, Array[(String, Int64, Int32, Bool)]),
  budget : Int64,
) -> Unit raise {
  let (low, high, active) = expected
  assert_eq((actual.minimum, actual.maximum), (low, high))
  assert_eq(actual.minimum_excess, if low > budget { low - budget } else { 0L })
  assert_eq(
    actual.maximum_excess,
    if high > budget {
      high - budget
    } else {
      0L
    },
  )
  assert_eq(
    actual.contributors.map(entry => {
      (entry.job_id, entry.start_minute, entry.units, entry.guaranteed)
    }),
    active,
  )
}

///|
test "event sweep agrees with a minute oracle for 60 plan and budget combinations" {
  for period in 2..<=6 {
    for high in 3..<=6 {
      for capacity in [1L, 8L, 15L] {
        let before = [("archive", 4, 2, 3, 2), ("sync", 5, 2, 3, 3)]
        let after = [("archive", 4, 2, 3, 2), ("sync", period, 2, high, 3)]
        let source = sample_input(
          oracle_jobs(before[:]),
          oracle_jobs(after[:]),
          capacities="{\"db\":\{capacity}}",
          start="1970-01-01T00:10:00Z",
          end="1970-01-01T00:40:00Z",
        )
        let report = @batchcontour.compare_capacity(
          @batchcontour.ReviewInput::from_json(source),
        )
        let mut blocked = false
        let spans = report.findings()
        for index, span in spans {
          assert_true(span.from_minute >= 10L)
          assert_true(span.until_minute <= 40L)
          assert_true(span.from_minute < span.until_minute)
          if index > 0 {
            assert_true(spans[index - 1].until_minute <= span.from_minute)
          }
        }
        for minute in 10..<40 {
          let before_expected = minute_oracle(minute, before[:])
          let after_expected = minute_oracle(minute, after[:])
          let (_, baseline_high, _) = before_expected
          let (_, candidate_high, _) = after_expected
          let found = spans.search_by(span => {
            let minute = minute.to_int64()
            span.from_minute <= minute && minute < span.until_minute
          })
          if baseline_high <= capacity && candidate_high <= capacity {
            assert_true(found is None)
          } else {
            guard found is Some(index) else {
              fail("missing review minute \{minute}")
            }
            let span = spans[index]
            check_oracle(span.baseline, before_expected, capacity)
            check_oracle(span.candidate, after_expected, capacity)
            let (baseline_low, _, _) = before_expected
            let (candidate_low, _, _) = after_expected
            let expected = (
                candidate_low > capacity && candidate_low > baseline_low
              ) ||
              (candidate_high > capacity && candidate_high > baseline_high)
            assert_eq(span.regression, expected)
            blocked = blocked || expected
          }
        }
        assert_eq(report.has_regressions(), blocked)
      }
    }
  }
}
