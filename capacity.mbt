///|
fn read_capacity_overrides(
  value : Json,
  capacities : Array[Capacity],
  window_start : Int64,
  window_end : Int64,
  path~ : String = "$.capacity_overrides",
) -> Unit raise ReviewError {
  guard value is Array(entries) else {
    raise InvalidInput(path~, detail="expected an array of capacity overrides")
  }
  guard entries.length() <= max_capacity_overrides else {
    raise LimitExceeded(path~, detail="expected at most 512 capacity overrides")
  }
  let by_resource : Array[Array[(Int32, CapacityOverride)]] = Array::makei(
    capacities.length(),
    _ => [],
  )
  for index, entry in entries {
    let entry_path = path + "[\{index}]"
    let fields = read_object(
      entry,
      ["resource", "start", "end", "units"],
      entry_path,
    )
    let resource = read_string(fields["resource"], entry_path + ".resource")
    guard capacities.search_by(budget => budget.resource == resource)
      is Some(resource_index) else {
      raise InvalidInput(
        path=entry_path + ".resource",
        detail="no capacity declared for " + Json::string(resource).stringify(),
      )
    }
    let start = parse_utc(
      read_string(fields["start"], entry_path + ".start"),
      entry_path + ".start",
    )
    let end = parse_utc(
      read_string(fields["end"], entry_path + ".end"),
      entry_path + ".end",
    )
    guard start >= window_start && start < end && end <= window_end else {
      raise InvalidInput(
        path=entry_path,
        detail="override must have positive length and fit inside the review window",
      )
    }
    let units = read_integer(
      fields["units"],
      0,
      max_units,
      entry_path + ".units",
    )
    by_resource[resource_index].push((index, { start, end, units, }))
  }
  for resource_index, entries in by_resource {
    entries.sort_by((a, b) => {
      let by_start = a.1.start.compare(b.1.start)
      if by_start == 0 {
        a.0.compare(b.0)
      } else {
        by_start
      }
    })
    let budget = capacities[resource_index]
    let mut previous_end = window_start
    for entry in entries {
      let (source_index, period) = entry
      guard period.start >= previous_end else {
        raise InvalidInput(
          path=path + "[\{source_index}]",
          detail="overlapping capacity overrides for " + budget.resource,
        )
      }
      budget.overrides.push(period)
      previous_end = period.end
    }
  }
}

///|
fn overrides_json(capacities : Array[Capacity]) -> Json {
  let entries : Array[Json] = []
  for capacity in capacities {
    for period in capacity.overrides {
      entries.push({
        "resource": Json::string(capacity.resource),
        "start": Json::string(utc_text(period.start)),
        "end": Json::string(utc_text(period.end)),
        "units": Json::number(period.units.to_double()),
      })
    }
  }
  Json::array(entries)
}
