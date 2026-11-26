///|
let review_evidence_schema = "batchcontour.review-evidence.v1"

///|
let max_evidence_units : Int32 = 32 * 1024 * 1024

///|
/// Compute a complete report and package it with the exact normalized input.
pub fn archive_capacity_review(input : ReviewInput) -> Json raise ReviewError {
  let report = compare_capacity(input)
  {
    "schema": Json::string(review_evidence_schema),
    "input": input.to_json(),
    "report": report.to_json(),
  }
}

///|
fn check_evidence_value(
  actual : Json,
  expected : Json,
  path : String,
) -> Unit raise ReviewError {
  match (actual, expected) {
    (Object(actual_keys), Object(expected_keys)) => {
      for key, _ in actual_keys {
        guard expected_keys.contains(key) else {
          raise InvalidInput(
            path~,
            detail="unexpected field " + Json::string(key).stringify(),
          )
        }
      }
      for key, wanted in expected_keys {
        let child_path = path + "." + key
        guard actual_keys.get(key) is Some(found) else {
          raise InvalidInput(
            path=child_path,
            detail="required evidence field is missing",
          )
        }
        check_evidence_value(found, wanted, child_path)
      }
    }
    (Array(actual_items), Array(expected_items)) => {
      guard actual_items.length() == expected_items.length() else {
        raise InvalidInput(path~, detail="evidence entry count differs")
      }
      for index, wanted in expected_items {
        check_evidence_value(actual_items[index], wanted, path + "[\{index}]")
      }
    }
    (Number(_, repr=Some(lexeme)), Number(_, ..)) => {
      guard lexeme == expected.stringify() else {
        raise InvalidInput(
          path~,
          detail="number differs from the canonical result",
        )
      }
    }
    _ => {
      guard actual == expected else {
        raise InvalidInput(
          path~,
          detail="value differs from the canonical result",
        )
      }
    }
  }
}

///|
fn parse_evidence(evidence : String) -> Json raise ReviewError {
  guard evidence.length() <= max_evidence_units else {
    raise LimitExceeded(
      path="$",
      detail="archive exceeds 32 Mi UTF-16 code units",
    )
  }
  parse_bounded_json(evidence, 16)
}

///|
/// Verify an archive against caller-provided trusted input and a fresh review.
/// Every field, contributor and exact numeric literal must match.
pub fn verify_capacity_evidence(
  input : ReviewInput,
  evidence : String,
) -> CapacityReport raise ReviewError {
  let root = read_object(
    parse_evidence(evidence),
    ["schema", "input", "report"],
    "$",
  )
  guard root["schema"] == Json::string(review_evidence_schema) else {
    raise InvalidInput(
      path="$.schema",
      detail="expected " + review_evidence_schema,
    )
  }
  check_evidence_value(root["input"], input.to_json(), "$.input")
  let report = compare_capacity(input)
  check_evidence_value(root["report"], report.to_json(), "$.report")
  report
}

///|
let gate_evidence_schema = "batchcontour.gate-evidence.v1"

///|
/// Archive the normalized policy and review with both the verdict and its evidence.
pub fn archive_capacity_gate(
  input : ReviewInput,
  policy : CapacityPolicy,
) -> Json raise ReviewError {
  let gate = check_capacity_policy(input, policy)
  {
    "schema": Json::string(gate_evidence_schema),
    "input": input.to_json(),
    "policy": policy.to_json(),
    "gate": gate.to_json(),
    "report": gate.report().to_json(),
  }
}

///|
/// Recompute and verify a gate archive against trusted inputs from the caller.
pub fn verify_gate_evidence(
  input : ReviewInput,
  policy : CapacityPolicy,
  evidence : String,
) -> CapacityGate raise ReviewError {
  let root = read_object(
    parse_evidence(evidence),
    ["schema", "input", "policy", "gate", "report"],
    "$",
  )
  guard root["schema"] == Json::string(gate_evidence_schema) else {
    raise InvalidInput(
      path="$.schema",
      detail="expected " + gate_evidence_schema,
    )
  }
  check_evidence_value(root["input"], input.to_json(), "$.input")
  check_evidence_value(root["policy"], policy.to_json(), "$.policy")
  let gate = check_capacity_policy(input, policy)
  check_evidence_value(root["gate"], gate.to_json(), "$.gate")
  check_evidence_value(root["report"], gate.report().to_json(), "$.report")
  gate
}
