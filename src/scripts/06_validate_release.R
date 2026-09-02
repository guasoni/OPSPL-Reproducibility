args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate src/scripts/06_validate_release.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)
require_packages(c("data.table", "jsonlite"))
public_release <- arg_flag(args, "--public-release")
source_only <- arg_flag(args, "--source-only")
validation_config <- if (source_only) list(output_root = "outputs") else read_config(root, args)
analysis_output_root <- pipeline_output_root(root, validation_config)

checks <- list()
add_check <- function(name, passes, detail) {
  checks[[length(checks) + 1L]] <<- list(name = name, passes = isTRUE(passes), detail = detail)
}

required <- c(
  "README.md", "CONTRIBUTING.md", "DATA_LICENSE_NOTICE.md", "LICENSE.txt", "CITATION.cff",
  ".zenodo.json", "VERSION", "CHANGELOG.md", "renv.lock", ".dockerignore",
  "Dockerfile", "run-container.sh",
  ".github/workflows/source-checks.yml",
  ".github/ISSUE_TEMPLATE/bug_report.yml",
  ".github/ISSUE_TEMPLATE/config.yml", ".github/pull_request_template.md",
  "reproduce.R", "config/config.example.R", "config/config.paper-vintage.example.R",
  "expected/raw_input_contract.csv", "tests/run_tests.R", "tests/README.md",
  "expected/paper_vintage_raw_fingerprints.csv",
  "expected/step1_paper_vintage_fingerprints.csv",
  "expected/paper_values/SPX_midprice_corrected.csv",
  "sql/optionmetrics_extract.sql", "docs/DATA_EXTRACTION.md",
  "docs/REPRODUCTION_POLICY.md", "docs/COVERAGE.md",
  "docs/CODE_PROVENANCE.md", "docs/DATA_SOURCES.md", "docs/RELEASE_CHECKLIST.md",
  "docs/SYNTHETIC_FIXTURE.md", "docs/METHOD_REUSE.md",
  "docs/RELEASES_AND_CITATION.md", "docs/CLEAN_ROOM_REPLICATION.md", "docs/WSL2.md",
  "docs/PROPRIETARY_DATA_AUDIT.md", "docs/AUXILIARY_SOURCE_COMPARISON.md",
  "data/public/oxford_man_realized_5min.csv",
  "src/scripts/00_verify_inputs.R", "src/scripts/06_validate_release.R",
  "src/scripts/07_audit_public_tree.R",
  "src/scripts/01_build_step1.R", "src/scripts/02_filter_options.R",
  "src/scripts/acquire_auxiliary_data.R", "src/scripts/03_build_auxiliary_inputs.R",
  "src/scripts/03_attach_forecasts.R", "src/scripts/04_optimize_portfolios.R",
  "src/scripts/05_generate_outputs.R", "src/scripts/run_all.R",
  "src/synthetic/generate_synthetic_inputs.R", "src/synthetic/run_synthetic.R",
  "src/synthetic/validate_synthetic.R", "expected/synthetic_checkpoints.csv"
)

license_candidates <- file.path(root, c("LICENSE", "LICENSE.md", "LICENSE.txt"))
citation_lines <- readLines(file.path(root, "CITATION.cff"), warn = FALSE, encoding = "UTF-8")
citation_license_pending <- any(grepl('^license:[[:space:]]*["\047]?NOASSERTION', citation_lines))
add_check(
  "open_source_code_license",
  !public_release || (any(file.exists(license_candidates)) && !citation_license_pending),
  if (any(file.exists(license_candidates)) && !citation_license_pending) {
    "A code license is installed and reflected in CITATION.cff."
  } else {
    "Select and install the authors' code license before public release."
  }
)
missing_required <- required[!file.exists(file.path(root, required))]
add_check(
  "required_release_files",
  !length(missing_required),
  if (length(missing_required)) paste(missing_required, collapse = ", ") else "All required files are present."
)

raw_contract <- data.table::fread(
  file.path(root, "expected", "raw_input_contract.csv"),
  colClasses = "character",
  showProgress = FALSE
)
expected_private_names <- c(
  "option_price_view_indices_2020.csv",
  "security_price_indices_through_2021_01.csv",
  "zero_curve_through_2020.csv"
)
contract_pass <-
  identical(raw_contract$config_field, c("option_prices", "security_prices", "zero_curve")) &&
  identical(raw_contract$required_filename, expected_private_names) &&
  all(nzchar(raw_contract$required_columns)) &&
  all(grepl("^[0-9a-fA-F]{64}$", raw_contract$paper_vintage_sha256))
add_check(
  "machine_readable_raw_input_contract",
  contract_pass,
  if (contract_pass) "Canonical filenames, schemas, date coverage, and paper-vintage fingerprints are present." else "The raw-input contract is incomplete or inconsistent."
)

if (source_only) {
  add_check("auxiliary_source_acquisition", TRUE, "Deferred in source-only validation.")
  add_check("auxiliary_input_reconstruction", TRUE, "Deferred in source-only validation.")
} else {
  acquisition_report_path <- resolve_from_root(
    root,
    if (is.null(validation_config$auxiliary_acquisition_report)) {
      "work/auxiliary/acquisition_report.json"
    } else {
      validation_config$auxiliary_acquisition_report
    }
  )
  build_report_path <- resolve_from_root(
    root,
    if (is.null(validation_config$auxiliary_build_report)) {
      "work/auxiliary/build_report.json"
    } else {
      validation_config$auxiliary_build_report
    }
  )
  acquisition_exists <- file.exists(acquisition_report_path)
  acquisition <- if (acquisition_exists) {
    jsonlite::read_json(acquisition_report_path, simplifyVector = TRUE)
  } else {
    NULL
  }
  acquisition_pass <- acquisition_exists &&
    identical(
      tolower(as.character(acquisition$djia$archive_sha256_expected)),
      tolower(as.character(acquisition$djia$archive_sha256_observed))
    ) &&
    as.Date(acquisition$yahoo$ranges$`^GSPC`$first_date) <= as.Date("1927-12-30") &&
    as.Date(acquisition$djia$output_range$first_date) <= as.Date("1927-12-30") &&
    as.Date(acquisition$vxd$output_range$first_date) <= as.Date("1997-10-07")
  add_check(
    "auxiliary_source_acquisition",
    acquisition_pass,
    if (acquisition_pass) {
      "Yahoo, checksum-pinned CRAN DJIA, and FRED VXD acquisition reports cover the required dates."
    } else {
      sprintf("Missing or invalid auxiliary acquisition report: %s", acquisition_report_path)
    }
  )

  build_exists <- file.exists(build_report_path)
  build <- if (build_exists) jsonlite::read_json(build_report_path, simplifyVector = TRUE) else NULL
  forecast_path <- resolve_from_root(root, validation_config$public_volatility_forecasts)
  returns_path <- resolve_from_root(root, validation_config$public_index_returns)
  outputs_exist <- file.exists(forecast_path) && file.exists(returns_path)
  build_pass <- build_exists && outputs_exist && as.integer(build$option_calendar$rows) == 300L
  if (build_pass) {
    forecasts <- data.table::fread(forecast_path, showProgress = FALSE)
    returns <- data.table::fread(returns_path, showProgress = FALSE)
    build_pass <- nrow(forecasts) == 300L && nrow(returns) == 23443L &&
      all(c("Date", "BizDays", "SPX_Vol_Pred", "NDX_Vol_Pred", "DJX_Vol_Pred") %in% names(forecasts)) &&
      all(c("Date", "SPXReturn", "NDXReturn", "DJXReturn", "Days_between") %in% names(returns))
  }
  add_check(
    "auxiliary_input_reconstruction",
    build_pass,
    if (build_pass) {
      "The R stage rebuilt 300 forecast rows and 23,443 historical-return rows."
    } else {
      sprintf("Missing or invalid auxiliary build outputs/report: %s", build_report_path)
    }
  )
}

step1_report <- file.path(analysis_output_root, "step1", "step1_report.json")
if (source_only) {
  add_check("paper_vintage_step1", TRUE, "Deferred in source-only validation.")
} else if (file.exists(step1_report)) {
  report <- jsonlite::read_json(step1_report, simplifyVector = TRUE)
  expected_step1 <- data.table::fread(
    file.path(root, "expected", "step1_paper_vintage_fingerprints.csv"),
    showProgress = FALSE
  )
  actual_rows <- unlist(report$output_rows[expected_step1$file], use.names = FALSE)
  actual_paths <- file.path(analysis_output_root, "step1", expected_step1$file)
  actual_exists <- file.exists(actual_paths)
  actual_bytes <- file.info(actual_paths)$size
  actual_hashes <- vapply(
    seq_along(actual_paths),
    function(index) if (actual_exists[[index]]) sha256_file(actual_paths[[index]]) else NA_character_,
    character(1L)
  )
  matches <-
    actual_exists &
    as.numeric(actual_rows) == expected_step1$rows &
    as.numeric(actual_bytes) == expected_step1$bytes &
    tolower(actual_hashes) == tolower(expected_step1$sha256)
  if (identical(report$data_mode, "paper-vintage")) {
    expected_raw <- data.table::fread(
      file.path(root, "expected", "paper_vintage_raw_fingerprints.csv"),
      colClasses = c(bytes = "numeric"),
      showProgress = FALSE
    )
    raw_bytes <- vapply(
      expected_raw$config_field,
      function(field) as.numeric(report[[field]]$bytes),
      numeric(1L)
    )
    raw_hashes <- vapply(
      expected_raw$config_field,
      function(field) as.character(report[[field]]$sha256),
      character(1L)
    )
    raw_matches <-
      raw_bytes == expected_raw$bytes &
      tolower(raw_hashes) == tolower(expected_raw$sha256)
    add_check(
      "paper_vintage_step1",
      all(raw_matches) && all(matches),
      paste0(
        "raw inputs: ",
        paste(sprintf("%s sha256=%s", expected_raw$logical_file, raw_hashes), collapse = "; "),
        "; outputs: ",
        paste(sprintf("%s rows=%s sha256=%s", expected_step1$file, actual_rows, actual_hashes), collapse = "; ")
      )
    )
  } else {
    missing_values <- unlist(report$missing_values, use.names = TRUE)
    add_check(
      "current_vintage_step1",
      all(actual_exists) && all(as.numeric(actual_rows) > 0) && all(as.numeric(missing_values) == 0),
      paste0(
        "Current-vintage outputs are complete and intentionally not compared with paper-vintage hashes. ",
        paste(sprintf("%s rows=%s sha256=%s", expected_step1$file, actual_rows, actual_hashes), collapse = "; ")
      )
    )
  }
} else {
  add_check("paper_vintage_step1", FALSE, "Step 1 report has not been generated.")
}

table_summary_path <- file.path(analysis_output_root, "tables", "table_validation_summary.json")
if (source_only) {
  add_check("current_coverage_tables", TRUE, "Deferred in source-only validation.")
} else if (file.exists(table_summary_path)) {
  table_summary <- jsonlite::read_json(table_summary_path, simplifyVector = TRUE)
  add_check(
    "current_coverage_tables",
    isTRUE(table_summary$pipeline_pass),
    paste(capture.output(str(table_summary)), collapse = " ")
  )
} else {
  add_check("current_coverage_tables", FALSE, "Table validation has not completed.")
}

public_dir <- file.path(root, "data", "public")
public_csvs <- list.files(public_dir, pattern = "\\.csv$", full.names = TRUE)
for (path in public_csvs) {
  header <- names(data.table::fread(path, nrows = 0L, colClasses = "character", showProgress = FALSE))
  forbidden <- intersect(
    header,
    c(
      "BestBid", "BestOffer", "Strike", "OptionID", "OpenInterest",
      "ImpliedVolatility", "Rate_simplex", "ProfitLossBuy", "ProfitLossSell"
    )
  )
  if (basename(path) != "index_closes_2021-01-13.csv" && "SecurityID" %in% header) {
    forbidden <- c(forbidden, "SecurityID")
  }
  add_check(
    paste0("public_data_columns_", basename(path)),
    !length(forbidden),
    if (length(forbidden)) paste("Forbidden fields:", paste(forbidden, collapse = ", ")) else "No option-level fields."
  )
}

provenance_path <- file.path(public_dir, "provenance.csv")
provenance <- data.table::fread(provenance_path, showProgress = FALSE)
included <- provenance[status != "planned-not-included"]
pending <- included[status == "pending"]
incomplete_provenance <- included[
  !nzchar(file) | !nzchar(source) | !nzchar(access_or_archive_date) |
    !nzchar(redistribution_basis) | !nzchar(transformations) |
    !grepl("^[0-9a-fA-F]{64}$", sha256) |
    !status %in% c("documented", "author-approved", "pending")
]
add_check(
  "public_data_provenance_complete",
  !nrow(incomplete_provenance),
  if (nrow(incomplete_provenance)) {
    paste("Incomplete entries:", paste(incomplete_provenance$file, collapse = ", "))
  } else {
    "Every included public-data file has source, date, release assessment, transformation, checksum, and recognized status."
  }
)
add_check(
  "public_data_redistribution_review",
  !public_release || !nrow(pending),
  if (nrow(pending)) {
    paste(
      if (public_release) "Pending before public push:" else "Deferred until public-release validation; pending:",
      paste(pending$file, collapse = ", ")
    )
  } else {
    "All included public-data files have completed redistribution review."
  }
)

git_directory <- file.path(root, ".git")
if (dir.exists(git_directory)) {
  tracked <- system2("git", c("-C", shQuote(root), "ls-files"), stdout = TRUE, stderr = TRUE)
  tracked <- tracked[nzchar(tracked)]
  tracked_paths <- file.path(root, tracked)
  tracked_sizes <- file.info(tracked_paths)$size
  oversized <- tracked[!is.na(tracked_sizes) & tracked_sizes >= 100 * 1024^2]
  add_check(
    "github_file_size_limit",
    !length(oversized),
    if (length(oversized)) paste(oversized, collapse = ", ") else "No tracked file is 100 MB or larger."
  )

  forbidden_tracked <- tracked[
    grepl("^data/private_raw/", tracked) & tracked != "data/private_raw/README.md"
  ]
  forbidden_tracked <- c(
    forbidden_tracked,
    tracked[grepl("^(outputs|work|logs)/", tracked)],
    tracked[tracked == "config/config.R"]
  )
  forbidden_basenames <- c(
    "option_price_view_indices_2020.csv",
    "security_price_indices_through_2021_01.csv",
    "closing_prices_2020.csv",
    "zero_curve_through_2020.csv",
    "zero_curve_2020.csv",
    "SPXfinal.csv", "NDXfinal.csv", "DJXfinal.csv", "RUTfinal.csv",
    "optfinal.csv", "optfinal3.csv"
  )
  forbidden_tracked <- c(
    forbidden_tracked,
    tracked[basename(tracked) %in% forbidden_basenames]
  )
  add_check(
    "licensed_and_local_paths_untracked",
    !length(unique(forbidden_tracked)),
    if (length(forbidden_tracked)) paste(unique(forbidden_tracked), collapse = ", ") else "Private inputs, outputs, work files, and local configuration are untracked."
  )

  tracked_csvs <- tracked[grepl("\\.csv$", tracked, ignore.case = TRUE)]
  option_level_csvs <- character()
  for (relative in tracked_csvs) {
    header <- names(data.table::fread(
      file.path(root, relative),
      nrows = 0L,
      colClasses = "character",
      showProgress = FALSE
    ))
    sensitive <- intersect(
      header,
      c(
        "BestBid", "BestOffer", "Strike", "OptionID", "OpenInterest",
        "ImpliedVolatility", "Delta", "Gamma", "Vega", "Theta",
        "ContractSize", "ExpiryIndicator"
      )
    )
    if (
      "OptionID" %in% sensitive ||
      all(c("BestBid", "BestOffer", "Strike") %in% sensitive) ||
      length(sensitive) >= 4L
    ) {
      option_level_csvs <- c(option_level_csvs, relative)
    }
  }
  option_level_names <- tracked[grepl(
    "(^|/)(SPXfinal|NDXfinal|DJXfinal|RUTfinal|optfinal3?|option_price_view_indices_2020)[.]csv$",
    tracked,
    ignore.case = TRUE
  )]
  option_level_csvs <- unique(c(option_level_csvs, option_level_names))
  add_check(
    "no_optionmetrics_or_option_level_csvs",
    !length(option_level_csvs),
    if (length(option_level_csvs)) paste(option_level_csvs, collapse = ", ") else "No tracked CSV has an OptionMetrics or option-level schema."
  )

  text_files <- tracked[grepl("\\.(R|md|csv|json|sql|cff|yml|yaml|lock|txt)$", tracked, ignore.case = TRUE)]
  leaked_paths <- character()
  for (relative in text_files) {
    lines <- readLines(file.path(root, relative), warn = FALSE, encoding = "UTF-8")
    if (any(grepl("C:[/\\\\]Users[/\\\\]Paolo", lines, ignore.case = TRUE))) {
      leaked_paths <- c(leaked_paths, relative)
    }
  }
  add_check(
    "no_personal_absolute_paths",
    !length(leaked_paths),
    if (length(leaked_paths)) paste(leaked_paths, collapse = ", ") else "No tracked text file exposes a personal absolute path."
  )
} else {
  add_check(
    "git_index_scan",
    !public_release,
    if (public_release) {
      "A Git index is required for the exact public-release leak scan."
    } else {
      "No Git index is present (for example, a source archive); the numerical reproduction remains valid and the release-only leak scan is deferred."
    }
  )
}

failed <- vapply(checks, function(check) !check$passes, FUN.VALUE = logical(1L))
result <- list(
  mode = if (public_release) "public-release" else if (source_only) "source-only" else "local-release-candidate",
  checked_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  passed = sum(!failed),
  failed = sum(failed),
  checks = checks
)
output <- file.path(analysis_output_root, "release_validation.json")
write_json(result, output)
for (check in checks) {
  cat(sprintf("%s %s: %s\n", if (check$passes) "PASS" else "FAIL", check$name, check$detail))
}
if (any(failed)) stop(sprintf("Release validation failed %d check(s). See %s", sum(failed), output))
log_message("Release validation passed.")
