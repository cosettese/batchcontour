///|
test "Actions import preserves long numeric identity and rejects incomplete and unsupported jobs" {
  let row =
    #|{"total_count":1,"jobs":[{"id":9007199254740995,"name":"unit / Linux","status":"completed","conclusion":"success","started_at":"2026-11-27T22:18:00Z","completed_at":"2026-11-27T22:18:32Z"}]}
  let aliases = "{\"unit / Linux\":\"linux\"}"
  for
    invalid in [
      row.replace(old="\"total_count\":1", new="\"total_count\":2"),
      row.replace(old="\"success\"", new="\"skipped\""),
      row.replace(old="unit / Linux", new="unknown"),
    ] {
    let refused = try {
      ignore(
        @batchcontour.import_actions_history(invalid, aliases, plan="candidate"),
      )
      false
    } catch {
      @batchcontour.InvalidInput(..) => true
      error => raise error
    }
    assert_true(refused)
  }
  let json = @batchcontour.import_actions_history(
      row,
      aliases,
      plan="candidate",
    )
    .to_json()
    .stringify()
  assert_true(json.contains("\"id\":\"9007199254740995\""))
  assert_eq(
    @batchcontour.RunHistory::from_json(json).to_json().stringify(),
    json,
  )
}
