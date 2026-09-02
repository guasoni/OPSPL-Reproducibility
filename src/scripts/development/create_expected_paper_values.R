args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate create_expected_paper_values.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", "..", ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)
require_packages("data.table")

source_dir <- arg_value(args, "--audit-tables")
if (is.null(source_dir)) stop("Pass the audited table directory with --audit-tables PATH")
source_dir <- normalizePath(source_dir, winslash = "/", mustWork = TRUE)
output_dir <- file.path(root, "expected", "paper_values")
ensure_directory(output_dir)

extract <- function(source_name, columns, output_name) {
  frame <- data.table::fread(file.path(source_dir, source_name), showProgress = FALSE)
  missing <- setdiff(columns, names(frame))
  if (length(missing)) stop(sprintf("%s lacks: %s", source_name, paste(missing, collapse = ", ")))
  data.table::fwrite(frame[, ..columns], file.path(output_dir, output_name), na = "NA", quote = TRUE)
}

extract(
  "accepted_paper_cell_comparison.csv",
  c(
    "ticker", "panel", "leverage_pct", "gamma", "statistic", "paper",
    "diagnosed_numerical_exception", "exception_reason"
  ),
  "performance_cells.csv"
)
extract(
  "SPX_margin_violation_comparison.csv",
  c("panel", "leverage_pct", "gamma", "paper_infeasible_pct"),
  "SPX_margin_cells.csv"
)
extract(
  "effective_position_comparison.csv",
  c("ticker", "panel", "leverage_pct", "gamma", "statistic", "paper"),
  "effective_position_cells.csv"
)
extract(
  "index_summary_option_comparison.csv",
  c("ticker", "statistic", "paper", "display_decimals"),
  "index_summary_option_cells.csv"
)
extract(
  "SPX_five_year_cell_comparison.csv",
  c(
    "period", "asset", "leverage_pct", "gamma", "statistic", "paper",
    "diagnosed_numerical_exception", "exception_reason"
  ),
  "SPX_five_year_cells.csv"
)

log_message("Expected paper values written to %s", output_dir)
