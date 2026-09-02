args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate src/scripts/03_attach_forecasts.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)
require_packages(c("data.table", "jsonlite"))

config <- read_config(root, args)
forecast_path <- resolve_from_root(root, config$public_volatility_forecasts)
if (is.null(forecast_path)) forecast_path <- file.path(root, "work", "auxiliary", "paper_volatility_forecasts.csv")
assert_file(forecast_path, "Rebuilt public-source volatility forecasts")

forecasts <- data.table::fread(forecast_path, showProgress = FALSE)
forecasts[, Date := normalize_iso_date(Date)]
output_root <- pipeline_output_root(root, config)
input_dir <- file.path(output_root, "step2")
output_dir <- file.path(output_root, "step3")
ensure_directory(output_dir)

reports <- list()
for (ticker in c("SPX", "NDX", "DJX")) {
  input_path <- file.path(input_dir, paste0(ticker, "_filtered1.csv"))
  assert_file(input_path, paste(ticker, "Step 2 file"))
  options <- data.table::fread(input_path, showProgress = FALSE)
  removable <- intersect(names(options), c("", "V1", "X", "X.1"))
  if (length(removable)) options[, (removable) := NULL]
  options[, Date := normalize_iso_date(Date)]
  options[, source_order__ := .I]

  vol_column <- paste0(ticker, "_Vol_Pred")
  additions <- forecasts[, .(
    Date,
    BizDays,
    VolPred = get(vol_column)
  )]
  biz_lookup <- stats::setNames(additions$BizDays, additions$Date)
  vol_lookup <- stats::setNames(additions$VolPred, additions$Date)
  options[, BizDays := unname(biz_lookup[Date])]
  options[, VolPred := unname(vol_lookup[Date])]
  data.table::setorder(options, Date, source_order__)
  options[, source_order__ := NULL]
  data.table::setcolorder(options, c("Date", setdiff(names(options), "Date")))

  output_path <- file.path(output_dir, paste0(ticker, "_filtered.csv"))
  write.csv(as.data.frame(options), output_path, row.names = TRUE, na = "NA", quote = TRUE, eol = "\n")
  reports[[ticker]] <- list(
    rows = nrow(options),
    dates = data.table::uniqueN(options$Date),
    missing_business_days = sum(is.na(options$BizDays)),
    missing_volatility_forecasts = sum(is.na(options$VolPred))
  )
  log_message("%s Step 3 complete: %d rows", ticker, nrow(options))
}

write_json(reports, file.path(output_dir, "step3_report.json"))
log_message("Step 3 complete. Outputs: %s", output_dir)
