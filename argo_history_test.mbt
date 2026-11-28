///|
test "Argo import validates terminal status, namespace and pagination" {
  let row =
    #|{"apiVersion":"argoproj.io/v1alpha1","kind":"WorkflowList","metadata":{"continue":""},"items":[{"metadata":{"namespace":"demo","uid":"instance","labels":{"workflows.argoproj.io/cron-workflow":"nightly"}},"status":{"phase":"Failed","startedAt":"2026-11-27T22:18:00Z","finishedAt":"2026-11-27T22:18:32Z"}}]}
  for
    invalid in [
      row.replace(old="\"Failed\"", new="\"Running\""),
      row.replace(old="\"demo\"", new="\"other\""),
      row.replace(old="\"continue\":\"\"", new="\"continue\":\"page\""),
      row.replace(old="/cron-workflow", new="/other"),
    ] {
    let refused = try {
      ignore(
        @batchcontour.import_argo_history(
          invalid,
          plan="candidate",
          namespace_name="demo",
        ),
      )
      false
    } catch {
      @batchcontour.InvalidInput(..) => true
      error => raise error
    }
    assert_true(refused)
  }
  let json = @batchcontour.import_argo_history(
      row,
      plan="candidate",
      namespace_name="demo",
    )
    .to_json()
    .stringify()
  assert_true(json.contains("\"job\":\"nightly\""))
  assert_eq(
    @batchcontour.RunHistory::from_json(json).to_json().stringify(),
    json,
  )
}
