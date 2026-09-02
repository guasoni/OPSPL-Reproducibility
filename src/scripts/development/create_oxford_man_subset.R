args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate create_oxford_man_subset.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", "..", ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)
require_packages(c("data.table", "digest"))

input <- arg_value(args, "--input")
if (is.null(input)) {
  stop("Usage: Rscript src/scripts/development/create_oxford_man_subset.R --input /path/to/rvdf.csv")
}
input <- normalizePath(path.expand(input), winslash = "/", mustWork = TRUE)
output <- resolve_from_root(
  root,
  arg_value(args, "--output", "data/public/oxford_man_realized_5min.csv")
)

expected_source_sha256 <- "a65def29a0c907d83b2595d6c0a4f6a4ab5c43e5ee52c23eb2ce901c25dc4f53"
actual_source_sha256 <- sha256_file(input)
if (!identical(tolower(actual_source_sha256), expected_source_sha256)) {
  stop(
    sprintf(
      "Oxford-Man archive checksum mismatch: expected %s, observed %s",
      expected_source_sha256,
      actual_source_sha256
    )
  )
}

subset <- data.table::fread(
  input,
  select = c("Symbol", "Date", "rv5", "close_price"),
  showProgress = FALSE
)
subset[, Date := as.Date(Date)]
subset <- subset[
  Symbol %in% c(".SPX", ".IXIC", ".DJI") &
    Date >= as.Date("1989-12-28") & Date < as.Date("2020-12-21")
]
data.table::setorder(subset, Symbol, Date)
if (nrow(subset) != 15769L || anyNA(subset) ||
    !setequal(unique(subset$Symbol), c(".SPX", ".IXIC", ".DJI"))) {
  stop("Oxford-Man subset failed its expected row, symbol, or completeness checks.")
}
ensure_directory(dirname(output))
data.table::fwrite(subset, output, na = "NA", quote = TRUE)
log_message("Oxford-Man subset written: %s", output)
log_message("Rows: %d; SHA-256: %s", nrow(subset), sha256_file(output))
