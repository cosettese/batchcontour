///|
fn contribution_json(entry : Contribution) -> Json {
  {
    "job": Json::string(entry.job_id),
    "start": Json::string(utc_text(entry.start_minute)),
    "units": Json::number(entry.units.to_double()),
    "guaranteed": Json::boolean(entry.guaranteed),
  }
}

///|
fn load_json(load : Load) -> Json {
  {
    "minimum": Json::number(load.minimum.to_double()),
    "maximum": Json::number(load.maximum.to_double()),
    "minimum_excess": Json::number(load.minimum_excess.to_double()),
    "maximum_excess": Json::number(load.maximum_excess.to_double()),
    "contributors": Json::array(load.contributors.map(contribution_json)),
  }
}

///|
fn finding_json(finding : Finding) -> Json {
  {
    "resource": Json::string(finding.resource),
    "capacity": Json::number(finding.capacity.to_double()),
    "window": window_json(finding.from_minute, finding.until_minute),
    "baseline": load_json(finding.baseline),
    "candidate": load_json(finding.candidate),
    "regression": Json::boolean(finding.regression),
  }
}

///|
/// Encode the complete report using the versioned JSON schema.
pub fn CapacityReport::to_json(self : CapacityReport) -> Json {
  {
    "schema": "batchcontour.report.v1",
    "window": window_json(self.start, self.end),
    "verdict": if self.has_regressions() {
      "blocked"
    } else {
      "passed"
    },
    "regression_count": Json::number(self.regression_count.to_double()),
    "findings": Json::array(self.findings.map(finding_json)),
  }
}
