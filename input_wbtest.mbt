///|
test "JSON depth counts containers and skips escaped string contents" {
  let text =
    #|[{"value":"escaped quote: \" and escaped slash: \\ [{{["}]
  assert_true(parse_bounded_json(text, 2) is Array([Object(_)]))
  assert_true(parse_bounded_json("[[0]]", 2) is Array(_))
  let refused = try {
    ignore(parse_bounded_json("[[[0]]]", 2))
    false
  } catch {
    InvalidInput(path="$", detail="JSON nesting exceeds 2 containers") => true
    error => raise error
  }
  assert_true(refused)
  assert_true(parse_bounded_json("[0]", 2) is Array(_))
}
