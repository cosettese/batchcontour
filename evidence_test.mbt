///|
fn review_sample() -> @batchcontour.ReviewInput raise {
  let task = job("batch", "0 0 * * *", 1, 2, demands="{\"db\":11}")
  @batchcontour.ReviewInput::from_json(sample_input("[]", "[\{task}]"))
}

///|
fn verify_rejected(
  input : @batchcontour.ReviewInput,
  evidence : String,
  field : String,
) -> Unit raise {
  let path = try {
    ignore(@batchcontour.verify_capacity_evidence(input, evidence))
    None
  } catch {
    @batchcontour.InvalidInput(path~, ..) => Some(path)
    error => raise error
  }
  assert_eq(path, Some(field))
}

///|
test "archive round trips with an exact recomputation even when review blocks" {
  let input = review_sample()
  let archived = @batchcontour.archive_capacity_review(input).stringify(
    indent=2,
  )
  let verified = @batchcontour.verify_capacity_evidence(input, archived)
  assert_true(verified.has_regressions())
  assert_eq(
    verified.to_json().stringify(),
    @batchcontour.compare_capacity(input).to_json().stringify(),
  )
  let same_input = @batchcontour.ReviewInput::from_json(
    input.to_json().stringify(),
  )
  assert_eq(
    @batchcontour.archive_capacity_review(same_input).stringify(indent=2),
    archived,
  )
}

///|
test "archive verification rejects changed input, findings and numeric spellings" {
  let input = review_sample()
  let source = @batchcontour.archive_capacity_review(input).stringify()
  verify_rejected(
    input,
    source.replace(old="\"db\":10", new="\"db\":11"),
    "$.input.capacities.db",
  )
  verify_rejected(
    input,
    source.replace(old="\"capacity\":10", new="\"capacity\":9"),
    "$.report.findings[0].capacity",
  )
  verify_rejected(
    input,
    source.replace(
      old="\"capacity\":10",
      new="\"capacity\":10.0000000000000001",
    ),
    "$.report.findings[0].capacity",
  )
  verify_rejected(
    input,
    source.replace(old="\"verdict\":\"blocked\"", new="\"verdict\":\"passed\""),
    "$.report.verdict",
  )
  let changed = @batchcontour.ReviewInput::from_json(
    input.to_json().stringify().replace(old="\"db\":10", new="\"db\":13"),
  )
  let consistent_but_wrong = @batchcontour.archive_capacity_review(changed).stringify()
  verify_rejected(input, consistent_but_wrong, "$.input.capacities.db")
}

///|
test "archive verification rejects missing, unknown and duplicate data then recovers" {
  let input = review_sample()
  let source = @batchcontour.archive_capacity_review(input).stringify()
  verify_rejected(
    input,
    source.replace(old="\"verdict\":\"blocked\",", new=""),
    "$.report.verdict",
  )
  verify_rejected(
    input,
    source.replace(
      old="\"job\":\"batch\"",
      new="\"job\":\"batch\",\"other\":true",
    ),
    "$.report.findings[0].candidate.contributors[0]",
  )
  verify_rejected(
    input,
    source.replace(
      old="\"resource\":\"db\"",
      new="\"resource\":\"gpu\",\"resource\":\"db\"",
    ),
    "$",
  )
  verify_rejected(input, "{", "$")
  assert_true(
    @batchcontour.verify_capacity_evidence(input, source).has_regressions(),
  )
}
