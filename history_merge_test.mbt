///|
test "history merge is idempotent, ordered and keeps the same ID from both plans" {
  let old = runtime(
    "baseline", "export", "run", "2026-11-21T02:00:00Z", "2026-11-21T02:01:00Z",
  )
  let next = runtime(
    "candidate", "export", "run", "2026-11-22T02:00:00Z", "2026-11-22T02:03:00Z",
  )
  let first = @batchcontour.RunHistory::from_json(history_input([old]))
  let second = @batchcontour.RunHistory::from_json(history_input([next, old]))
  let merged = @batchcontour.merge_run_histories([first, second, second])
    .to_json()
    .stringify()
  assert_eq(merged, second.to_json().stringify())
  assert_eq(
    @batchcontour.merge_run_histories([second, first]).to_json().stringify(),
    merged,
  )
  assert_eq(
    @batchcontour.RunHistory::from_json(merged).to_json().stringify(),
    merged,
  )
}

///|
test "history merge refuses conflicting observations and sample requirements" {
  let earlier = runtime(
    "candidate", "hello", "job", "2026-11-26T07:36:00Z", "2026-11-26T07:37:25Z",
  )
  let later = earlier.replace(old="07:37:25Z", new="07:37:26Z")
  let first = @batchcontour.RunHistory::from_json(history_input([earlier]))
  let changed = @batchcontour.RunHistory::from_json(history_input([later]))
  let strict = @batchcontour.RunHistory::from_json(
    history_input([earlier], min_samples=2),
  )
  for
    entry in [
      (changed, "$.histories[1].runs[0]"),
      (strict, "$.histories[1].min_samples"),
    ] {
    let (other, expected_path) = entry
    let refused = try {
      ignore(@batchcontour.merge_run_histories([first, other]))
      false
    } catch {
      @batchcontour.InvalidInput(path~, ..) => path == expected_path
      error => raise error
    }
    assert_true(refused)
  }
  assert_eq(
    @batchcontour.merge_run_histories([first, first]).to_json().stringify(),
    first.to_json().stringify(),
  )
}
