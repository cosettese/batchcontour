# Review a schedule change from MoonBit

This fixture deliberately overlaps two runs with different start times. The
candidate consumes 12 connections during minutes 3 through 5 in a pool of 10.
From minute 5 through minute 8 only the upper bound exceeds the capacity.

```mbt check
///|
test "review a schedule change and inspect its first finding" {
  let source =
    #|{"schema":"batchcontour.input.v1",
    #|"window":{"start":"1970-01-01T00:00:00Z","end":"1970-01-01T00:10:00Z"},
    #|"capacities":{"connections":10},
    #|"baseline":[],
    #|"candidate":[
    #|{"id":"backup","cron":"0 0 * * *","min_minutes":5,"max_minutes":8,"demand":{"connections":7}},
    #|{"id":"etl","cron":"3 0 * * *","min_minutes":5,"max_minutes":5,"demand":{"connections":5}}
    #|]}
  let input = @batchcontour.ReviewInput::from_json(source)
  let report = @batchcontour.compare_capacity(input)
  assert_true(report.has_regressions())
  let first = report.findings()[0]
  assert_eq(first.from_minute, 3L)
  assert_eq(first.until_minute, 5L)
  assert_eq(first.candidate.minimum_excess, 2L)
  assert_eq(first.candidate.maximum_excess, 2L)
}
```
