///|
let budget_schema = "batchcontour.budget.v1"

///|
let plan_schema = "batchcontour.plan.v1"

///|
/// Independently versioned inputs for reconstructing a review.
pub struct ReviewDocuments {
  budget : Json
  baseline : Json
  candidate : Json
}

///|
fn read_review_part(
  text : String,
  schema : String,
  fields : ArrayView[String],
  path : String,
) -> Map[String, Json] raise ReviewError {
  let value = parse_document(text) catch {
    InvalidInput(detail~, ..) => raise InvalidInput(path~, detail~)
    LimitExceeded(detail~, ..) => raise LimitExceeded(path~, detail~)
  }
  let object = read_object(value, fields, path)
  guard object["schema"] == Json::string(schema) else {
    raise InvalidInput(path=path + ".schema", detail="expected " + schema)
  }
  object
}

///|
/// Join separately versioned plans under one shared budget.
/// Budget and plan fields use the same validation as a v3 combined review.
pub fn assemble_review(
  budget : String,
  baseline : String,
  candidate : String,
) -> ReviewInput raise ReviewError {
  let fields = read_review_part(
    budget,
    budget_schema,
    ["schema", "window", "capacities", "capacity_overrides"],
    "$.budget",
  )
  let (start, end) = read_review_window(fields["window"], "$.budget.window")
  let capacities = read_capacities(
    fields["capacities"],
    path="$.budget.capacities",
  )
  read_capacity_overrides(
    fields["capacity_overrides"],
    capacities,
    start,
    end,
    path="$.budget.capacity_overrides",
  )
  let old = read_review_part(
    baseline,
    plan_schema,
    ["schema", "jobs"],
    "$.baseline",
  )
  let next = read_review_part(
    candidate,
    plan_schema,
    ["schema", "jobs"],
    "$.candidate",
  )
  let input : ReviewInput = {
    schema: launch_input_schema,
    start,
    end,
    capacities,
    baseline: read_jobs(
      old["jobs"],
      capacities,
      "$.baseline.jobs",
      launch_window=(start, end),
    ),
    candidate: read_jobs(
      next["jobs"],
      capacities,
      "$.candidate.jobs",
      launch_window=(start, end),
    ),
  }
  guard input.to_json().stringify().length() <= max_input_units else {
    raise LimitExceeded(
      path="$",
      detail="assembled review exceeds 1 Mi UTF-16 code units",
    )
  }
  input
}

///|
/// Serialize the budget and plans as independent JSON documents.
/// v1/v2 inputs gain empty launch-override arrays and keep their review behavior.
pub fn ReviewInput::split_documents(self : ReviewInput) -> ReviewDocuments {
  let capacities : Map[String, Json] = Map([])
  for capacity in self.capacities {
    capacities[capacity.resource] = Json::number(capacity.units.to_double())
  }
  {
    budget: {
      "schema": Json::string(budget_schema),
      "window": window_json(self.start, self.end),
      "capacities": Json::object(capacities),
      "capacity_overrides": overrides_json(self.capacities),
    },
    baseline: {
      "schema": Json::string(plan_schema),
      "jobs": Json::array(
        self.baseline.map(job => job_json(job, self.capacities, true)),
      ),
    },
    candidate: {
      "schema": Json::string(plan_schema),
      "jobs": Json::array(
        self.candidate.map(job => job_json(job, self.capacities, true)),
      ),
    },
  }
}
