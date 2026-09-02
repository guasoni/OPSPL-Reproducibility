args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate src/synthetic/validate_synthetic.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)
require_packages(c("data.table", "digest", "jsonlite"))

config <- read_config(root, args)
if (!identical(config$data_mode, "synthetic")) stop("Synthetic validation requires config$data_mode = 'synthetic'.")
output_root <- pipeline_output_root(root, config)
manifest_path <- file.path(root, "work", "synthetic", "manifest.json")
assert_file(manifest_path, "Synthetic manifest")
manifest <- jsonlite::read_json(manifest_path, simplifyVector = TRUE)

checks <- list()
add_check <- function(name, passes, detail) {
  checks[[length(checks) + 1L]] <<- list(name = name, passes = isTRUE(passes), detail = detail)
}

read_numeric_matrix <- function(path) {
  assert_file(path)
  frame <- data.table::fread(path, check.names = FALSE, showProgress = FALSE)
  as.matrix(data.frame(lapply(frame, as.numeric), check.names = FALSE))
}

generated_input_paths <- c(
  resolve_from_root(root, config$option_prices),
  resolve_from_root(root, config$security_prices),
  resolve_from_root(root, config$zero_curve),
  resolve_from_root(root, config$public_yahoo_daily),
  resolve_from_root(root, config$public_volatility_forecasts),
  resolve_from_root(root, config$public_index_returns)
)
for (path in generated_input_paths) {
  filename <- basename(path)
  observed_rows <- if (file.exists(path)) nrow(data.table::fread(path, showProgress = FALSE)) else NA_integer_
  observed_hash <- if (file.exists(path)) sha256_file(path) else NA_character_
  expected_rows_for_file <- as.integer(manifest$input_rows[[filename]])
  expected_hash <- as.character(manifest$input_sha256[[filename]])
  add_check(
    paste0("generated_input_integrity_", filename),
    !is.na(observed_rows) && observed_rows == expected_rows_for_file && identical(observed_hash, expected_hash),
    sprintf("rows=%s; sha256=%s", observed_rows, observed_hash)
  )
}

contract <- data.table::fread(
  file.path(root, "expected", "raw_input_contract.csv"),
  colClasses = "character",
  showProgress = FALSE
)
for (i in seq_len(nrow(contract))) {
  field <- contract$config_field[[i]]
  path <- resolve_from_root(root, config[[field]])
  expected_columns <- strsplit(contract$required_columns[[i]], "|", fixed = TRUE)[[1L]]
  observed_columns <- if (file.exists(path)) names(data.table::fread(path, nrows = 0L, showProgress = FALSE)) else character()
  add_check(
    paste0("raw_schema_", field),
    file.exists(path) && identical(basename(path), contract$required_filename[[i]]) && identical(observed_columns, expected_columns),
    sprintf("file=%s; columns=%d", basename(path), length(observed_columns))
  )
}

raw_options <- data.table::fread(resolve_from_root(root, config$option_prices), showProgress = FALSE)
raw_options[, SecurityID := as.integer(SecurityID)]
add_check(
  "four_security_ids",
  setequal(unique(raw_options$SecurityID), as.integer(manifest$security_ids)),
  paste(sort(unique(raw_options$SecurityID)), collapse = ",")
)
add_check(
  "calls_and_puts",
  setequal(unique(raw_options$CallPut), c("C", "P")),
  paste(sort(unique(raw_options$CallPut)), collapse = ",")
)
add_check(
  "raw_saturday_expirations",
  all(as.POSIXlt(as.Date(raw_options$Expiration))$wday == 6L),
  sprintf("Saturday rows=%d/%d", sum(as.POSIXlt(as.Date(raw_options$Expiration))$wday == 6L), nrow(raw_options))
)
spxw_rows <- sum(grepl("SPXW", raw_options$Symbol, fixed = TRUE))
add_check(
  "spxw_fixture_present",
  spxw_rows == as.integer(manifest$expected_spxw_rows_excluded),
  sprintf("SPXW rows=%d", spxw_rows)
)
selected_symbols <- grepl("_SYN_M", raw_options$Symbol, fixed = TRUE) &
  !grepl("SPXW", raw_options$Symbol, fixed = TRUE)
add_check(
  "five_selected_strikes_per_type",
  all(raw_options[selected_symbols, data.table::uniqueN(Strike), by = .(SecurityID, Expiration, CallPut)]$V1 == 5L),
  "Every intended monthly contract contains five call strikes and five put strikes."
)
add_check(
  "competing_expiry_fixture_present",
  nrow(raw_options[grepl("_SYN_ALT_", Symbol, fixed = TRUE)]) > 0L,
  "Lower-volume competing monthly expirations are present."
)

curve <- data.table::fread(resolve_from_root(root, config$zero_curve), showProgress = FALSE)
add_check(
  "multiple_curve_maturities",
  all(curve[, .N, by = Date]$N >= 3L),
  sprintf("maturities per date: %s", paste(sort(unique(curve[, .N, by = Date]$N)), collapse = ","))
)

yahoo <- data.table::fread(resolve_from_root(root, config$public_yahoo_daily), showProgress = FALSE)
forecasts <- data.table::fread(resolve_from_root(root, config$public_volatility_forecasts), showProgress = FALSE)
returns <- data.table::fread(resolve_from_root(root, config$public_index_returns), showProgress = FALSE)
add_check(
  "synthetic_auxiliary_contract",
  setequal(unique(yahoo$Ticker), c("^GSPC", "SPY", "^NDX", "^IXIC", "QQQ", "^DJI", "DIA", "^VIX", "^VXN")) &&
    nrow(forecasts) == as.integer(manifest$usable_monthly_periods) &&
    all(c("Date", "SPXReturn", "NDXReturn", "DJXReturn", "Days_between") %in% names(returns)),
  sprintf("Yahoo tickers=%d; forecasts=%d; return history=%d", data.table::uniqueN(yahoo$Ticker), nrow(forecasts), nrow(returns))
)

step1_report_path <- file.path(output_root, "step1", "step1_report.json")
assert_file(step1_report_path, "Synthetic Step 1 report")
step1_report <- jsonlite::read_json(step1_report_path, simplifyVector = TRUE)
add_check(
  "monthly_selection",
  step1_report$selection$selected_pair_count == as.integer(manifest$expected_selected_pairs) &&
    step1_report$selection$selected_expiration_count == as.integer(manifest$raw_expiration_months) &&
    step1_report$selection$monthly_maximum_tie_groups == 0L,
  sprintf(
    "pairs=%d; expirations=%d; ties=%d",
    step1_report$selection$selected_pair_count,
    step1_report$selection$selected_expiration_count,
    step1_report$selection$monthly_maximum_tie_groups
  )
)
add_check(
  "spxw_excluded",
  step1_report$selection$excluded_spxw_rows == as.integer(manifest$expected_spxw_rows_excluded),
  sprintf("excluded=%d", step1_report$selection$excluded_spxw_rows)
)

expected_rows <- as.integer(manifest$expected_step1_rows_per_ticker)
for (ticker in c("SPX", "NDX", "DJX", "RUT")) {
  path <- file.path(output_root, "step1", paste0(ticker, "final.csv"))
  assert_file(path, paste(ticker, "synthetic Step 1 output"))
  frame <- data.table::fread(path, showProgress = FALSE)
  add_check(
    paste0("step1_shape_", ticker),
    nrow(frame) == expected_rows && data.table::uniqueN(frame$Date) == as.integer(manifest$usable_monthly_periods),
    sprintf("rows=%d; dates=%d", nrow(frame), data.table::uniqueN(frame$Date))
  )
  add_check(
    paste0("step1_complete_", ticker),
    !anyNA(frame[, .(PriceExp, PriceDate, Days, Rate, Maturity, MidPrice)]) &&
      all(as.POSIXlt(as.Date(frame$Expiration))$wday == 5L) &&
      all(as.Date(frame$Maturity) == as.Date(frame$Expiration)),
    "Prices and rates are complete; Saturday expirations became Fridays; the exact curve maturity was selected."
  )
}

for (ticker in c("SPX", "NDX", "DJX")) {
  path <- file.path(output_root, "step3", paste0(ticker, "_filtered.csv"))
  assert_file(path, paste(ticker, "synthetic Step 3 output"))
  frame <- data.table::fread(path, showProgress = FALSE)
  add_check(
    paste0("step3_shape_", ticker),
    nrow(frame) == expected_rows && data.table::uniqueN(frame$Date) == as.integer(manifest$usable_monthly_periods),
    sprintf("rows=%d; dates=%d", nrow(frame), data.table::uniqueN(frame$Date))
  )
  add_check(
    paste0("step3_complete_", ticker),
    !anyNA(frame[, .(Implied_Price, BizDays, VolPred)]) && all(frame$BestBid > 0),
    "Put-call-parity prices and forecast fields are complete; bids are positive."
  )
}

matrix_specs <- list(
  SPX_Excess_Return.csv = c(12L, 9L),
  SPX_Excess_Return_solvency.csv = c(12L, 9L),
  SPX_Excess_Return_LL.csv = c(12L, 3L),
  SPX_Excess_Return_midprice.csv = c(12L, 9L),
  NDX_Excess_Return.csv = c(12L, 9L),
  NDX_Excess_Return_solvency.csv = c(12L, 9L),
  DJX_Excess_Return.csv = c(12L, 9L),
  DJX_Excess_Return_solvency.csv = c(12L, 9L)
)
for (filename in names(matrix_specs)) {
  matrix <- read_numeric_matrix(file.path(output_root, "step4", filename))
  expected_shape <- matrix_specs[[filename]]
  add_check(
    paste0("optimizer_", sub("[.]csv$", "", filename)),
    identical(dim(matrix), unname(expected_shape)) && all(is.finite(matrix)),
    sprintf("shape=%dx%d; finite=%s", nrow(matrix), ncol(matrix), all(is.finite(matrix)))
  )
}

for (ticker in c("SPX", "NDX", "DJX")) {
  audit_path <- file.path(output_root, "step4", paste0(ticker, "_margin_audit_solvency.csv"))
  audit <- data.table::fread(audit_path, showProgress = FALSE)
  minimum <- suppressWarnings(as.numeric(audit$minimum_in_sample_option_return))
  add_check(
    paste0("solvency_constraint_", ticker),
    all(is.finite(minimum)) && min(minimum) >= -1 - 1e-8,
    sprintf("minimum in-sample option return=%.12g", min(minimum))
  )
}

spx_margin <- data.table::fread(file.path(output_root, "step4", "SPX_margin_audit.csv"), showProgress = FALSE)
add_check(
  "spx_margin_diagnostics_finite",
  all(is.finite(spx_margin$margin)) && all(is.finite(spx_margin$capital_required)),
  sprintf("rows=%d", nrow(spx_margin))
)

metric_files <- c(
  SPX_unconstrained_return_sum = "SPX_Excess_Return.csv",
  SPX_solvency_return_sum = "SPX_Excess_Return_solvency.csv",
  SPX_small_return_sum = "SPX_Excess_Return_LL.csv",
  SPX_midprice_return_sum = "SPX_Excess_Return_midprice.csv",
  NDX_unconstrained_return_sum = "NDX_Excess_Return.csv",
  NDX_solvency_return_sum = "NDX_Excess_Return_solvency.csv",
  DJX_unconstrained_return_sum = "DJX_Excess_Return.csv",
  DJX_solvency_return_sum = "DJX_Excess_Return_solvency.csv"
)
observed <- data.table::data.table(
  metric = names(metric_files),
  observed = vapply(
    metric_files,
    function(filename) sum(read_numeric_matrix(file.path(output_root, "step4", filename))),
    numeric(1L)
  )
)
step1_spx <- data.table::fread(file.path(output_root, "step1", "SPXfinal.csv"), showProgress = FALSE)
observed <- data.table::rbindlist(list(
  observed,
  data.table::data.table(metric = "SPX_step1_mean_midprice", observed = mean(step1_spx$MidPrice))
))
observed_path <- file.path(root, "work", "synthetic", "observed_checkpoints.csv")
data.table::fwrite(observed, observed_path)

expected_path <- file.path(root, "expected", "synthetic_checkpoints.csv")
if (file.exists(expected_path)) {
  expected <- data.table::fread(expected_path, showProgress = FALSE)
  comparison <- merge(expected, observed, by = "metric", all = TRUE, sort = FALSE)
  comparison[, absolute_error := abs(observed - expected)]
  comparison[, allowed_error := tolerance + abs(expected) * tolerance]
  passes <- !anyNA(comparison[, .(expected, tolerance, observed)]) &&
    !anyDuplicated(comparison$metric) && all(comparison$absolute_error <= comparison$allowed_error)
  add_check(
    "numerical_regression_checkpoints",
    passes,
    sprintf("%d deterministic checkpoints; maximum absolute error=%.12g", nrow(comparison), max(comparison$absolute_error))
  )
} else {
  add_check(
    "numerical_regression_checkpoints",
    FALSE,
    sprintf("Missing expected/synthetic_checkpoints.csv; candidate observations written to %s", observed_path)
  )
}

failed <- vapply(checks, function(check) !check$passes, logical(1L))
result <- list(
  fixture = "deterministic non-empirical integration test",
  checked_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  passed = sum(!failed),
  failed = sum(failed),
  checks = checks
)
report_path <- file.path(output_root, "synthetic_validation.json")
write_json(result, report_path)
for (check in checks) {
  cat(sprintf("%s %s: %s\n", if (check$passes) "PASS" else "FAIL", check$name, check$detail))
}
if (any(failed)) stop(sprintf("Synthetic validation failed %d check(s). See %s", sum(failed), report_path))
log_message("Synthetic validation passed.")
