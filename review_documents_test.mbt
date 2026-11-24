///|
test "split and assemble preserve a v3 review with temporary capacity and launch changes" {
  let base = launch_job("[]")
  let next = launch_job(
    "[{\"at\":\"2026-11-23T01:59:00Z\",\"run\":true},{\"at\":\"2026-11-23T02:00:00Z\",\"run\":false}]",
  )
  let review = launch_review("[\{base}]", "[\{next}]").replace(
    old="\"capacity_overrides\":[]",
    new="\"capacity_overrides\":[{\"resource\":\"db\",\"start\":\"2026-11-23T02:00:00Z\",\"end\":\"2026-11-23T02:01:00Z\",\"units\":5}]",
  )
  let input = @batchcontour.ReviewInput::from_json(review)
  let parts = input.split_documents()
  let result = @batchcontour.assemble_review(
    parts.budget.stringify(),
    parts.baseline.stringify(),
    parts.candidate.stringify(),
  )
  assert_eq(result.to_json().stringify(), input.to_json().stringify())
  assert_eq(
    @batchcontour.compare_capacity(result).to_json().stringify(),
    @batchcontour.compare_capacity(input).to_json().stringify(),
  )
}

///|
test "assembly fails closed on an unknown resource and new budget using old launch dates" {
  let next = launch_job("[{\"at\":\"2026-11-23T02:01:00Z\",\"run\":true}]")
  let input = @batchcontour.ReviewInput::from_json(
    launch_review("[]", "[\{next}]"),
  )
  let parts = input.split_documents()
  let budget = parts.budget.stringify()
  let candidate = parts.candidate.stringify()
  let baseline = parts.baseline.stringify()
  for
    entry in [
      (budget, candidate.replace(old="\"db\"", new="\"gpu\""), ".demand"),
      (budget.replace(old="02:00:00Z", new="02:03:00Z"), candidate, ".at"),
      (
        budget,
        candidate.replace(old="\"jobs\":", new="\"unexpected\":[] ,\"jobs\":"),
        "$.candidate",
      ),
      (
        budget,
        candidate.replace(old="\"jobs\":", new="\"jobs\":[],\"jobs\":"),
        "$.candidate",
      ),
    ] {
    let (budget_text, candidate_text, field) = entry
    let invalid = try {
      ignore(
        @batchcontour.assemble_review(budget_text, baseline, candidate_text),
      )
      false
    } catch {
      @batchcontour.InvalidInput(path~, ..) => path.has_suffix(field)
      error => raise error
    }
    assert_true(invalid)
  }
  assert_eq(
    @batchcontour.assemble_review(budget, baseline, candidate)
    .to_json()
    .stringify(),
    input.to_json().stringify(),
  )
}
