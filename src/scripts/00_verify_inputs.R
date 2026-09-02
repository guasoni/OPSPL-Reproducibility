args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate src/scripts/00_verify_inputs.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)
require_packages(c("data.table", "digest", "jsonlite"))
config <- read_config(root, args)
public_only <- arg_flag(args, "--public-only")

private_results <- list()
failed_private <- 0L
if (!public_only) {
  contract <- data.table::fread(
    file.path(root, "expected", "raw_input_contract.csv"),
    colClasses = "character",
    showProgress = FALSE
  )
  for (i in seq_len(nrow(contract))) {
    field <- contract$config_field[[i]]
    configured <- config[[field]]
    path <- resolve_from_root(root, configured)
    exists <- !is.null(path) && file.exists(path)
    expected_header <- strsplit(contract$required_columns[[i]], "|", fixed = TRUE)[[1L]]
    actual_header <- if (exists) {
      names(data.table::fread(path, nrows = 0L, showProgress = FALSE))
    } else {
      character()
    }
    allowed_names <- contract$required_filename[[i]]
    if (identical(config$data_mode, "paper-vintage")) {
      allowed_names <- c(allowed_names, contract$paper_vintage_filename[[i]])
    }
    filename_pass <- exists && basename(path) %in% allowed_names
    schema_pass <- exists && identical(actual_header, expected_header)
    passes <- exists && filename_pass && schema_pass
    private_results[[field]] <- list(
      configured_path = path,
      exists = exists,
      allowed_filenames = allowed_names,
      actual_filename = if (exists) basename(path) else NULL,
      expected_columns = expected_header,
      actual_columns = actual_header,
      filename_pass = filename_pass,
      schema_pass = schema_pass,
      passes = passes
    )
    if (!passes) failed_private <- failed_private + 1L
    log_message(
      "%s private input %s: file=%s; schema=%s",
      if (passes) "PASS" else "FAIL",
      field,
      if (filename_pass) "pass" else "fail",
      if (schema_pass) "pass" else "fail"
    )
  }
} else {
  log_message("Private OptionMetrics preflight deferred (--public-only).")
}

public_dir <- file.path(root, "data", "public")
provenance <- data.table::fread(file.path(public_dir, "provenance.csv"), showProgress = FALSE)
included <- provenance[status != "planned-not-included" & nzchar(sha256)]
results <- list()
for (i in seq_len(nrow(included))) {
  path <- file.path(public_dir, included$file[[i]])
  exists <- file.exists(path)
  actual <- if (exists) sha256_file(path) else NA_character_
  passes <- exists && identical(tolower(actual), tolower(included$sha256[[i]]))
  results[[included$file[[i]]]] <- list(
    exists = exists,
    expected_sha256 = included$sha256[[i]],
    actual_sha256 = actual,
    passes = passes
  )
  log_message("%s %s", if (passes) "PASS" else "FAIL", included$file[[i]])
}

oxford_path <- resolve_from_root(root, config$public_oxford_man_realized)
if (is.null(oxford_path)) {
  oxford_path <- file.path(public_dir, "oxford_man_realized_5min.csv")
}
assert_file(oxford_path, "Oxford-Man realized-volatility subset")
oxford <- data.table::fread(oxford_path, showProgress = FALSE)
schema_checks <- list(
  oxford_columns = identical(names(oxford), c("Symbol", "Date", "rv5", "close_price")),
  oxford_rows = nrow(oxford) == 15769L,
  oxford_symbols = setequal(unique(oxford$Symbol), c(".SPX", ".IXIC", ".DJI")),
  oxford_complete = !anyNA(oxford)
)

if (!public_only) {
  yahoo_path <- resolve_from_root(root, config$public_yahoo_daily)
  djia_path <- resolve_from_root(root, config$public_djia_daily)
  vxd_path <- resolve_from_root(root, config$public_vxd_daily)
  assert_file(yahoo_path, "Downloaded Yahoo daily series")
  assert_file(djia_path, "Downloaded CRAN DJIA series")
  assert_file(vxd_path, "Downloaded FRED VXD series")

  yahoo <- data.table::fread(yahoo_path, showProgress = FALSE)
  djia <- data.table::fread(djia_path, showProgress = FALSE)
  vxd <- data.table::fread(vxd_path, showProgress = FALSE)
  yahoo[, Date := as.Date(Date)]
  djia[, Date := as.Date(Date)]
  vxd[, Date := as.Date(Date)]
  source_checks <- list(
    yahoo_columns = identical(
      names(yahoo),
      c("Ticker", "Date", "Open", "High", "Low", "Close", "Adjusted", "Volume")
    ),
    yahoo_tickers = setequal(
      unique(yahoo$Ticker),
      c("^GSPC", "SPY", "^NDX", "^IXIC", "QQQ", "^DJI", "DIA", "^RUT", "^VIX", "^VXN")
    ),
    yahoo_required_coverage = min(yahoo[Ticker == "^GSPC", Date]) <= as.Date("1927-12-30") &&
      max(yahoo[Ticker == "^GSPC", Date]) >= as.Date("2021-05-28"),
    djia_columns = identical(names(djia), c("Date", "DJI")),
    djia_required_coverage = min(djia$Date) <= as.Date("1927-12-30") &&
      max(djia$Date) >= as.Date("2021-05-28"),
    vxd_columns = identical(names(vxd), c("Date", "VXD")),
    vxd_required_coverage = min(vxd$Date) <= as.Date("1997-10-07") &&
      max(vxd$Date) >= as.Date("2021-05-28")
  )
  schema_checks <- c(schema_checks, source_checks)

  supplemental_path <- resolve_from_root(root, config$supplemental_closes)
  if (!is.null(supplemental_path)) {
    assert_file(supplemental_path, "Generated January 2021 supplemental closes")
    supplemental <- data.table::fread(supplemental_path, showProgress = FALSE)
    schema_checks$supplemental_closes <- nrow(supplemental) == 4L &&
      all(c("SecurityID", "Date", "ClosePrice") %in% names(supplemental))
  }
}
results$schema_checks <- schema_checks

failed_hashes <- sum(!vapply(results[names(results) != "schema_checks"], `[[`, "passes", FUN.VALUE = logical(1L)))
failed_schema <- sum(!unlist(schema_checks, use.names = FALSE))
report <- list(
  verified_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  mode = if (public_only) "public-only" else "full-preflight",
  private_files = private_results,
  public_files = results,
  failed_private_inputs = failed_private,
  failed_hashes = failed_hashes,
  failed_schema_checks = failed_schema,
  passes = failed_private == 0L && failed_hashes == 0L && failed_schema == 0L
)
write_json(report, file.path(root, "outputs", "public_input_verification.json"))
if (!report$passes) stop("Input verification failed.")
log_message("All distributed and acquired auxiliary inputs passed fingerprint and schema validation.")
