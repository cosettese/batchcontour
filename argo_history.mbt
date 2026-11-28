///|
let argo_version = "argoproj.io/v1alpha1"

///|
let argo_cron_label = "workflows.argoproj.io/cron-workflow"

///|
/// Project terminal Argo Workflow intervals for one namespace and plan.
pub fn import_argo_history(
  text : String,
  plan~ : String,
  namespace_name~ : String,
  min_samples~ : Int32 = 1,
) -> RunHistory raise ReviewError {
  validate_import_context(plan, min_samples)
  ignore(read_id(Json::string(namespace_name), "namespace"))
  let root = history_object(Some(parse_document(text, max_depth=48)), "$")
  let typed_list = match (root.get("apiVersion"), root.get("kind")) {
    (Some(String(version)), Some(String("WorkflowList"))) if version ==
      argo_version => true
    (Some(String("v1")), Some(String("List"))) => false
    _ =>
      raise InvalidInput(
        path="$",
        detail="expected a kubectl List or Argo WorkflowList",
      )
  }
  if root.get("metadata") is Some(value) {
    let metadata = history_object(Some(value), "$.metadata")
    guard metadata.get("continue") is (None | Some(String(""))) else {
      raise InvalidInput(
        path="$.metadata.continue",
        detail="export all Workflow pages before import",
      )
    }
  }
  guard root.get("items") is Some(Array(items)) &&
    items.length() <= max_history_runs else {
    raise InvalidInput(path="$.items", detail="expected up to 4,096 Workflows")
  }
  let seen : Map[String, Unit] = Map([])
  let runs : Array[Observation] = []
  for index, item in items {
    let path = "$.items[\{index}]"
    let fields = history_object(Some(item), path)
    let version = fields.get("apiVersion")
    let kind = fields.get("kind")
    guard (
        version == Some(Json::string(argo_version)) &&
        kind is Some(String("Workflow"))
      ) ||
      (typed_list && version is None && kind is None) else {
      raise InvalidInput(path~, detail="expected an Argo Workflow")
    }
    let meta_path = path + ".metadata"
    let metadata = history_object(fields.get("metadata"), meta_path)
    guard metadata.get("namespace") == Some(Json::string(namespace_name)) else {
      raise InvalidInput(
        path=meta_path + ".namespace",
        detail="expected namespace " + namespace_name,
      )
    }
    let run_id = read_id(
      metadata.get("uid").unwrap_or(Json::null()),
      meta_path + ".uid",
    )
    guard !seen.contains(run_id) else {
      raise InvalidInput(
        path=meta_path + ".uid",
        detail="duplicate Workflow UID " + run_id,
      )
    }
    seen[run_id] = ()
    let labels = history_object(metadata.get("labels"), meta_path + ".labels")
    let job_id = read_id(
      labels.get(argo_cron_label).unwrap_or(Json::null()),
      meta_path + ".labels." + argo_cron_label,
    )
    let status_path = path + ".status"
    let status = history_object(fields.get("status"), status_path)
    guard status.get("phase") is Some(String("Succeeded" | "Failed" | "Error")) else {
      raise InvalidInput(
        path=status_path + ".phase",
        detail="expected a terminal Workflow phase",
      )
    }
    runs.push(
      imported_observation(
        plan, job_id, run_id, index, status, status_path, "startedAt", "finishedAt",
      ),
    )
  }
  let history = normalized_history(min_samples, runs)
  guard history.to_json().stringify().length() < max_input_units else {
    raise LimitExceeded(
      path="$.items",
      detail="normalized history exceeds the supported JSON size",
    )
  }
  history
}
