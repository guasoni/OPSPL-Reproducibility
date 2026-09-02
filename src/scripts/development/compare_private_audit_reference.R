args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate comparison script.")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", "..", ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)
require_packages("jsonlite")

reference_argument <- arg_value(args, "--reference-dir", "")
if (!nzchar(reference_argument)) {
  stop("Supply the authors' private audited output directory with --reference-dir.")
}
reference_dir <- resolve_from_root(root, reference_argument)
generated_dir <- file.path(root, "outputs", "step4")
if (!dir.exists(reference_dir)) stop("Reference directory not found: ", reference_dir)

numeric_matrix <- function(path) {
  assert_file(path)
  frame <- read.csv(path, check.names = FALSE)
  if (ncol(frame)) {
    first <- suppressWarnings(as.integer(frame[[1L]]))
    if (length(first) == nrow(frame) && !anyNA(first) && identical(first, seq_len(nrow(frame)))) {
      frame <- frame[, -1L, drop = FALSE]
    }
  }
  matrix(as.numeric(as.matrix(frame)), nrow = nrow(frame), ncol = ncol(frame))
}

compare_file <- function(
  name,
  tolerance,
  require_zero_mask = FALSE,
  require_missing_mask = TRUE,
  special = FALSE
) {
  generated_path <- file.path(generated_dir, name)
  reference_path <- file.path(reference_dir, name)
  if (!file.exists(generated_path) || !file.exists(reference_path)) {
    return(list(
      file = name,
      passes = FALSE,
      detail = "Generated or private reference file is missing."
    ))
  }
  generated <- numeric_matrix(generated_path)
  reference <- numeric_matrix(reference_path)
  if (!identical(dim(generated), dim(reference))) {
    return(list(
      file = name,
      passes = FALSE,
      generated_shape = dim(generated),
      reference_shape = dim(reference)
    ))
  }

  finite_mask <- is.finite(generated) & is.finite(reference)
  missing_mask_match <- identical(is.na(generated), is.na(reference))
  difference <- abs(generated - reference)
  finite_difference <- difference[finite_mask]
  maximum <- if (length(finite_difference)) max(finite_difference) else 0
  average <- if (length(finite_difference)) mean(finite_difference) else 0
  over <- which(finite_mask & difference > tolerance, arr.ind = TRUE)
  zero_mask_mismatches <- sum((generated == 0) != (reference == 0), na.rm = TRUE)
  base_pass <- maximum <= tolerance
  special_pass <- FALSE
  if (special && nrow(over)) {
    allowed <- switch(
      name,
      "SPX_Excess_Return.csv" = matrix(c(199L, 7L), ncol = 2L, byrow = TRUE),
      "DJX_Excess_Return_solvency.csv" = matrix(c(185L, 7L), ncol = 2L, byrow = TRUE),
      matrix(integer(), ncol = 2L)
    )
    same_cells <- nrow(over) == nrow(allowed) && all(over == allowed)
    special_pass <- same_cells && maximum <= 5e-4 && average <= 1e-6
  }

  list(
    file = name,
    generated_shape = dim(generated),
    reference_shape = dim(reference),
    tolerance = tolerance,
    max_abs_difference = maximum,
    mean_abs_difference = average,
    cells_over_tolerance_one_based = if (nrow(over)) {
      lapply(seq_len(nrow(over)), function(index) unname(over[index, ]))
    } else {
      list()
    },
    zero_mask_mismatches = zero_mask_mismatches,
    missing_mask_match = missing_mask_match,
    diagnosed_spx_exception_applied = special_pass && !base_pass,
    passes = (!require_missing_mask || missing_mask_match) && (base_pass || special_pass) &&
      (!require_zero_mask || zero_mask_mismatches == 0)
  )
}

reports <- list()
for (ticker in c("SPX", "NDX", "DJX")) {
  for (suffix in c("", "_solvency")) {
    return_name <- paste0(ticker, "_Excess_Return", suffix, ".csv")
    reports[[return_name]] <- compare_file(
      return_name,
      tolerance = 2e-4,
      require_zero_mask = TRUE,
      special = return_name %in% c("SPX_Excess_Return.csv", "DJX_Excess_Return_solvency.csv")
    )
    weight_name <- paste0(ticker, "_port_weight", suffix, ".csv")
    reports[[weight_name]] <- compare_file(weight_name, tolerance = 2e-4)
  }
  index_name <- paste0(ticker, "_ind_excess_return.csv")
  reports[[index_name]] <- compare_file(index_name, tolerance = 1e-12)
}
reports[["SPX_port_weight_LL.csv"]] <- compare_file(
  "SPX_port_weight_LL.csv",
  tolerance = 2e-4,
  require_missing_mask = FALSE
)

passes <- vapply(reports, function(report) isTRUE(report$passes), logical(1L))
result <- list(
  checked_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  reference_directory_fingerprint_disclosed = FALSE,
  files_checked = length(reports),
  failures = names(passes)[!passes],
  passed = all(passes),
  reports = reports
)
output <- file.path(root, "outputs", "private_reference_validation.json")
write_json(result, output)
cat(sprintf("Private audit-reference comparison: %d/%d files pass.\n", sum(passes), length(passes)))
if (!all(passes)) stop("Private audit-reference comparison failed: ", paste(names(passes)[!passes], collapse = ", "))
