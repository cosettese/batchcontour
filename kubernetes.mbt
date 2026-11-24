///|
fn kubernetes_object(
  value : Json?,
  path : String,
) -> Map[String, Json] raise ReviewError {
  guard value is Some(Object(fields)) else {
    raise InvalidInput(path~, detail="expected an object")
  }
  fields
}

///|
fn cronjob_owner(
  metadata : Map[String, Json],
  path : String,
) -> (String, String) raise ReviewError {
  guard metadata.get("ownerReferences") is Some(Array(refs)) else {
    raise InvalidInput(path~, detail="expected CronJob owner references")
  }
  let mut owner = None
  for index, reference in refs {
    let entry_path = "\{path}[\{index}]"
    let fields = kubernetes_object(Some(reference), entry_path)
    match fields.get("controller") {
      None | Some(False) => continue
      Some(True) => ()
      _ =>
        raise InvalidInput(
          path=entry_path + ".controller",
          detail="expected a boolean",
        )
    }
    guard owner is None &&
      fields.get("kind") == Some(Json::string("CronJob")) &&
      fields.get("apiVersion") == Some(Json::string("batch/v1")) else {
      raise InvalidInput(
        path=entry_path,
        detail="expected a single batch/v1 CronJob controller",
      )
    }
    let name = read_id(
      fields.get("name").unwrap_or(Json::null()),
      entry_path + ".name",
    )
    let uid = read_id(
      fields.get("uid").unwrap_or(Json::null()),
      entry_path + ".uid",
    )
    owner = Some((name, uid))
  }
  guard owner is Some(result) else {
    raise InvalidInput(path~, detail="expected a controlling CronJob")
  }
  result
}

///|
fn completed_job_status(
  status : Map[String, Json],
  path : String,
) -> Unit raise ReviewError {
  guard status.get("conditions") is Some(Array(conditions)) else {
    raise InvalidInput(path~, detail="expected a Complete=True condition")
  }
  let mut complete = false
  for index, condition in conditions {
    let entry_path = "\{path}[\{index}]"
    let fields = kubernetes_object(Some(condition), entry_path)
    let kind = read_string(
      fields.get("type").unwrap_or(Json::null()),
      entry_path + ".type",
    )
    let state = fields.get("status")
    guard state is Some(String("True" | "False" | "Unknown")) else {
      raise InvalidInput(
        path=entry_path + ".status",
        detail="expected True, False or Unknown",
      )
    }
    guard kind != "Suspended" else {
      raise InvalidInput(
        path=entry_path,
        detail="suspension may invalidate the original start time",
      )
    }
    if kind == "Complete" {
      guard !complete && state is Some(String("True")) else {
        raise InvalidInput(
          path=entry_path,
          detail="expected one Complete=True condition",
        )
      }
      complete = true
    } else if kind == "Failed" || kind == "FailureTarget" {
      raise InvalidInput(
        path=entry_path,
        detail="failed job history cannot be imported",
      )
    }
  }
  guard complete else {
    raise InvalidInput(path~, detail="expected a Complete=True condition")
  }
}

///|
/// Project a single namespace's successful CronJob Jobs into portable run history.
/// Refuse the entire export if any item cannot supply an unambiguous interval.
pub fn import_kubernetes_history(
  text : String,
  plan~ : String,
  namespace_name~ : String,
  min_samples~ : Int32 = 1,
) -> RunHistory raise ReviewError {
  guard plan == "baseline" || plan == "candidate" else {
    raise InvalidInput(path="plan", detail="expected baseline or candidate")
  }
  ignore(read_id(Json::string(namespace_name), "namespace"))
  guard min_samples >= 1 && min_samples <= max_history_runs else {
    raise InvalidInput(path="min_samples", detail="expected 1–4,096 samples")
  }
  let root = kubernetes_object(Some(parse_document(text, max_depth=48)), "$")
  let typed_list = match (root.get("apiVersion"), root.get("kind")) {
    (Some(String("batch/v1")), Some(String("JobList"))) => true
    (Some(String("v1")), Some(String("List"))) => false
    _ =>
      raise InvalidInput(
        path="$",
        detail="expected a Kubernetes v1 List or batch/v1 JobList",
      )
  }
  if root.get("metadata") is Some(meta) {
    let fields = kubernetes_object(Some(meta), "$.metadata")
    guard fields.get("continue") is (None | Some(String(""))) else {
      raise InvalidInput(
        path="$.metadata.continue",
        detail="export the complete list before importing",
      )
    }
  }
  guard root.get("items") is Some(Array(items)) else {
    raise InvalidInput(path="$.items", detail="expected an array of Jobs")
  }
  guard items.length() <= max_history_runs else {
    raise LimitExceeded(path="$.items", detail="expected at most 4,096 Jobs")
  }
  let ids : Map[String, Unit] = Map([])
  let owners : Map[String, String] = Map([])
  let runs : Array[Observation] = []
  for index, item in items {
    let path = "$.items[\{index}]"
    let fields = kubernetes_object(Some(item), path)
    guard (fields.get("apiVersion"), fields.get("kind"))
      is (Some(String("batch/v1")), Some(String("Job"))) ||
      (
        typed_list &&
        fields.get("apiVersion") is None &&
        fields.get("kind") is None
      ) else {
      raise InvalidInput(path~, detail="expected a batch/v1 Job")
    }
    let metadata_path = path + ".metadata"
    let metadata = kubernetes_object(fields.get("metadata"), metadata_path)
    guard metadata.get("namespace") == Some(Json::string(namespace_name)) else {
      raise InvalidInput(
        path=metadata_path + ".namespace",
        detail="expected " + namespace_name,
      )
    }
    let uid_path = metadata_path + ".uid"
    let run_id = read_id(metadata.get("uid").unwrap_or(Json::null()), uid_path)
    guard !ids.contains(run_id) else {
      raise InvalidInput(path=uid_path, detail="duplicate Job UID " + run_id)
    }
    ids[run_id] = ()
    let owner_path = metadata_path + ".ownerReferences"
    let (job_id, owner_uid) = cronjob_owner(metadata, owner_path)
    guard !(owners.get(job_id) is Some(uid) && uid != owner_uid) else {
      raise InvalidInput(
        path=owner_path,
        detail="CronJob " + job_id + " has multiple controller UIDs",
      )
    }
    owners[job_id] = owner_uid
    let status_path = path + ".status"
    let status = kubernetes_object(fields.get("status"), status_path)
    completed_job_status(status, status_path + ".conditions")
    let start_path = status_path + ".startTime"
    let end_path = status_path + ".completionTime"
    let started_at = read_string(
      status.get("startTime").unwrap_or(Json::null()),
      start_path,
    )
    let finished_at = read_string(
      status.get("completionTime").unwrap_or(Json::null()),
      end_path,
    )
    let (start, elapsed) = history_times(
      started_at, finished_at, start_path, end_path,
    )
    runs.push({
      plan,
      job_id,
      run_id,
      started_at,
      finished_at,
      start_second: start,
      elapsed_seconds: elapsed,
      source_index: index,
    })
  }
  normalized_history(min_samples, runs)
}
