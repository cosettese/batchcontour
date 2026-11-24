///|
fn launch_review(before : String, after : String) -> String {
  with_overrides(
    sample_input(
      before,
      after,
      start="2026-11-23T02:00:00Z",
      end="2026-11-23T02:05:00Z",
    ),
    "[]",
  ).replace(old="batchcontour.input.v2", new="batchcontour.input.v3")
}

///|
fn launch_job(overrides : String) -> String {
  let source =
    $|{"id":"hello","cron":"0 2 * * *","min_minutes":1,"max_minutes":2,"demand":{"db":6},"launch_overrides":\{overrides}}
  source
}

///|
test "an explicit backfill carries into review and an exception removes the cron run" {
  let backfill = "{\"at\":\"2026-11-23T01:59:00Z\",\"run\":true}"
  let cancel = "{\"at\":\"2026-11-23T02:00:00Z\",\"run\":false}"
  let base = launch_job("[]")
  let add = launch_job("[\{backfill}]")
  let input = @batchcontour.ReviewInput::from_json(
    launch_review("[\{base}]", "[\{add}]"),
  )
  let finding = @batchcontour.compare_capacity(input).findings()[0]
  assert_eq(finding.candidate.maximum, 12L)
  assert_eq(finding.candidate.minimum, 6L)
  let replaced = launch_job("[\{cancel},\{backfill}]")
  let recovered = @batchcontour.ReviewInput::from_json(
    launch_review("[\{base}]", "[\{replaced}]"),
  )
  assert_false(@batchcontour.compare_capacity(recovered).has_regressions())
  let artifact = @batchcontour.archive_capacity_review(recovered).stringify()
  assert_false(
    @batchcontour.verify_capacity_evidence(recovered, artifact).has_regressions(),
  )
  let canonical = recovered.to_json().stringify()
  let reversed = launch_job("[\{backfill},\{cancel}]")
  let reordered = @batchcontour.ReviewInput::from_json(
    launch_review("[\{base}]", "[\{reversed}]"),
  )
  assert_eq(reordered.to_json().stringify(), canonical)
  assert_eq(
    @batchcontour.ReviewInput::from_json(canonical).to_json().stringify(),
    canonical,
  )
}

///|
test "enabling an already scheduled minute coalesces with its cron launch" {
  let task = launch_job("[{\"at\":\"2026-11-23T02:00:00Z\",\"run\":true}]")
  let input = @batchcontour.ReviewInput::from_json(
    launch_review("[]", "[\{task}]"),
  )
  assert_eq(@batchcontour.compare_capacity(input).findings().length(), 0)
}

///|
test "reject repeated or irrelevant override minutes and unsupported actions" {
  let active = "{\"at\":\"2026-11-23T02:00:00Z\",\"run\":true}"
  for
    overrides in [
      "[\{active},\{active}]",
      "[{\"at\":\"2026-11-23T01:58:00Z\",\"run\":true}]",
      "[{\"at\":\"2026-11-23T02:05:00Z\",\"run\":true}]",
      "[{\"at\":\"2026-11-23T02:00:00Z\",\"run\":\"yes\"}]",
      "[{\"at\":\"2026-11-23T02:00:00Z\",\"run\":true,\"other\":0}]",
    ] {
    let task = launch_job(overrides)
    let refused = try {
      ignore(
        @batchcontour.ReviewInput::from_json(launch_review("[]", "[\{task}]")),
      )
      false
    } catch {
      @batchcontour.InvalidInput(path~, ..) =>
        path.has_prefix("$.candidate[0].launch_overrides")
      error => raise error
    }
    assert_true(refused)
  }
  let valid = launch_job("[\{active}]")
  let legacy = launch_review("[]", "[\{valid}]").replace(
    old="batchcontour.input.v3",
    new="batchcontour.input.v2",
  )
  rejected(legacy, "$.candidate[0]")
}
