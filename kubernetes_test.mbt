///|
fn exported_job(
  uid : String,
  owner~ : String = "owner-1",
  status~ : String = "Complete",
) -> String {
  let text =
    $|{"apiVersion":"batch/v1","kind":"Job","metadata":{"namespace":"nightly","uid":"\{uid}","ownerReferences":[{"apiVersion":"batch/v1","kind":"CronJob","name":"hello","uid":"\{owner}","controller":true}]},"status":{"conditions":[{"type":"\{status}","status":"True"}],"startTime":"2026-11-23T02:01:15Z","completionTime":"2026-11-23T02:02:32Z"}}
  text
}

///|
fn job_export(items : ArrayView[String]) -> String {
  (
    $|{"apiVersion":"v1","kind":"List","items":[\{items.to_owned().join(",")}]}
  )
}

///|
test "Kubernetes imports preserve controller identity and run times in canonical history" {
  let first = exported_job("job-1")
  let second = exported_job("job-2")
  let normalized = @batchcontour.import_kubernetes_history(
      job_export([second, first]),
      plan="candidate",
      namespace_name="nightly",
      min_samples=2,
    )
    .to_json()
    .stringify()
  let expected = @batchcontour.RunHistory::from_json(
      history_input(
        [
          runtime(
            "candidate", "hello", "job-1", "2026-11-23T02:01:15Z", "2026-11-23T02:02:32Z",
          ),
          runtime(
            "candidate", "hello", "job-2", "2026-11-23T02:01:15Z", "2026-11-23T02:02:32Z",
          ),
        ],
        min_samples=2,
      ),
    )
    .to_json()
    .stringify()
  assert_eq(normalized, expected)
  assert_eq(
    @batchcontour.import_kubernetes_history(
      job_export([first, second]),
      plan="candidate",
      namespace_name="nightly",
      min_samples=2,
    )
    .to_json()
    .stringify(),
    normalized,
  )
}

///|
test "Kubernetes import rejects ambiguous controller, unfinished rows and partial lists" {
  let good = exported_job("job-1")
  let cases = [
    (job_export([good, good]), ".uid"),
    (
      job_export([good, exported_job("job-2", owner="owner-2")]),
      ".ownerReferences",
    ),
    (job_export([exported_job("job-2", status="Failed")]), ".conditions[0]"),
    (job_export([exported_job("job-2", status="Suspended")]), ".conditions[0]"),
    (
      job_export([good.replace(old="\"nightly\"", new="\"other\"")]),
      ".namespace",
    ),
    (
      job_export([good.replace(old="02:02:32Z", new="02:01:14Z")]),
      ".completionTime",
    ),
    (
      "{\"apiVersion\":\"batch/v1\",\"kind\":\"JobList\",\"metadata\":{\"continue\":\"token\"},\"items\":[]}",
      ".continue",
    ),
  ]
  for entry in cases {
    let (source, field) = entry
    let refused = try {
      ignore(
        @batchcontour.import_kubernetes_history(
          source,
          plan="baseline",
          namespace_name="nightly",
        ),
      )
      false
    } catch {
      @batchcontour.InvalidInput(path~, ..) => path.has_suffix(field)
      error => raise error
    }
    assert_true(refused)
  }
  let typed = good.replace(
    old="\"apiVersion\":\"batch/v1\",\"kind\":\"Job\",",
    new="",
  )
  let recovered =
    $|{"apiVersion":"batch/v1","kind":"JobList","metadata":{"continue":""},"items":[\{typed}]}
  assert_true(
    @batchcontour.import_kubernetes_history(
      recovered,
      plan="baseline",
      namespace_name="nightly",
    )
    .to_json()
    .stringify()
    .contains("\"id\":\"job-1\""),
  )
}
