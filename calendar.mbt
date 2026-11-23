///|
fn utc_moment(minute : Int64) -> @moondate.Moment {
  @moondate.Moment::of_epoch(minute * 60L, zone=@moondate.Utc)
}

///|
fn utc_text(minute : Int64) -> String {
  utc_moment(minute).strftime("%Y-%m-%dT%H:%M:00Z")
}

///|
fn parse_utc(text : String, path : String) -> Int64 raise ReviewError {
  parse_utc_timestamp(text, path, minute_aligned=true) / 60L
}

///|
fn parse_utc_timestamp(
  text : String,
  path : String,
  minute_aligned~ : Bool,
) -> Int64 raise ReviewError {
  let detail = if minute_aligned {
    "expected a UTC minute in YYYY-MM-DDTHH:MM:00Z (1970–2099)"
  } else {
    "expected a UTC timestamp in YYYY-MM-DDTHH:MM:SSZ (1970–2099)"
  }
  guard text.length() == 20 && (!minute_aligned || text[16:] == ":00Z") else {
    raise InvalidInput(path~, detail~)
  }
  let shape = "0000-00-00T00:00:00Z"
  for index in 0..<shape.length() {
    let code = text[index].to_int()
    if shape[index].to_int() == 48 {
      guard code >= 48 && code <= 57 else { raise InvalidInput(path~, detail~) }
    } else if text[index] != shape[index] {
      raise InvalidInput(path~, detail~)
    }
  }
  guard text[0:4] >= "1970" && text[0:4] <= "2099" else {
    raise InvalidInput(path~, detail~)
  }
  let moment = @moondate.parse(text[:]) catch {
    _ => raise InvalidInput(path~, detail~)
  }
  guard moment.epoch() is Some(second) else {
    raise InvalidInput(path~, detail~)
  }
  let canonical = @moondate.Moment::of_epoch(second, zone=@moondate.Utc).strftime(
    "%Y-%m-%dT%H:%M:%SZ",
  )
  guard canonical == text else { raise InvalidInput(path~, detail~) }
  second
}

///|
fn parse_schedule(
  expression : String,
  path : String,
) -> @cron.Cron raise ReviewError {
  // Constrain numeric runs before the upstream parser accumulates them.
  guard expression.length() <= 128 else {
    raise InvalidInput(path~, detail="cron exceeds 128 characters")
  }
  let mut fields = 0
  let mut in_field = false
  let mut digits = 0
  for unit in expression {
    if unit == ' ' || unit == '\t' {
      in_field = false
      digits = 0
      continue
    }
    if !in_field {
      fields += 1
      in_field = true
    }
    match unit {
      '0'..<='9' => {
        digits += 1
        guard digits <= 2 else {
          raise InvalidInput(
            path~,
            detail="cron numbers must have at most two digits",
          )
        }
      }
      '*' | ',' | '-' | '/' => digits = 0
      _ =>
        raise InvalidInput(
          path~,
          detail="expected a numeric five-field UTC cron",
        )
    }
  }
  guard fields == 5 else {
    raise InvalidInput(
      path~,
      detail="expected five cron fields (minute through weekday)",
    )
  }
  @cron.parse(expression[:]) catch {
    error => raise InvalidInput(path~, detail=error.to_string())
  }
}
