///|
fn Job::runs_at(self : Job, minute : Int64, moment : @moondate.Moment) -> Bool {
  match self.launch_overrides.get(minute) {
    Some(run) => run
    None => self.cron.matches(moment)
  }
}

///|
fn read_launch_overrides(
  input : Json,
  earliest : Int64,
  end : Int64,
  path : String,
) -> Map[Int64, Bool] raise ReviewError {
  guard input is Array(entries) && entries.length() <= 128 else {
    raise InvalidInput(
      path~,
      detail="expected an array of at most 128 launch overrides",
    )
  }
  let overrides : Map[Int64, Bool] = Map([])
  for index, entry in entries {
    let entry_path = path + "[\{index}]"
    let fields = read_object(entry, ["at", "run"], entry_path)
    let at_path = entry_path + ".at"
    let at = parse_utc(read_string(fields["at"], at_path), at_path)
    guard earliest <= at && at < end else {
      raise InvalidInput(
        path=at_path,
        detail="launch cannot affect the review window",
      )
    }
    guard !overrides.contains(at) else {
      raise InvalidInput(path=at_path, detail="duplicate launch minute")
    }
    let run = match fields["run"] {
      True => true
      False => false
      _ =>
        raise InvalidInput(
          path=entry_path + ".run",
          detail="expected a boolean",
        )
    }
    overrides[at] = run
  }
  overrides
}

///|
fn launch_overrides_json(overrides : Map[Int64, Bool]) -> Json {
  let entries : Array[(Int64, Bool)] = []
  for at, run in overrides {
    entries.push((at, run))
  }
  entries.sort_by_key(entry => entry.0)
  Json::array(
    entries.map(entry => {
      let value : Json = {
        "at": Json::string(utc_text(entry.0)),
        "run": Json::boolean(entry.1),
      }
      value
    }),
  )
}
