script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate tests/run_tests.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), ".."),
  winslash = "/"
)

failures <- character()
check <- function(condition, message) {
  if (!isTRUE(condition)) failures <<- c(failures, message)
}

r_files <- c(
  file.path(root, "reproduce.R"),
  list.files(file.path(root, "src"), pattern = "[.]R$", recursive = TRUE, full.names = TRUE),
  list.files(file.path(root, "tests"), pattern = "[.]R$", recursive = TRUE, full.names = TRUE)
)
for (path in unique(r_files)) {
  tryCatch(parse(path), error = function(error) failures <<- c(failures, sprintf("R parse failure in %s: %s", path, error$message)))
}

contract_path <- file.path(root, "expected", "raw_input_contract.csv")
check(file.exists(contract_path), "Missing expected/raw_input_contract.csv")
if (file.exists(contract_path)) {
  contract <- read.csv(contract_path, stringsAsFactors = FALSE, check.names = FALSE)
  required_fields <- c(
    "option_prices" = "option_price_view_indices_2020.csv",
    "security_prices" = "security_price_indices_through_2021_01.csv",
    "zero_curve" = "zero_curve_through_2020.csv"
  )
  check(identical(contract$config_field, names(required_fields)), "Raw-input contract fields or order changed unexpectedly.")
  check(identical(contract$required_filename, unname(required_fields)), "Canonical OptionMetrics filenames do not match the public contract.")
  check(all(nzchar(contract$required_columns)), "Raw-input contract has an empty column specification.")
  check(all(grepl("^[0-9a-f]{64}$", contract$paper_vintage_sha256)), "Paper-vintage raw hashes are malformed.")
}

removed_auxiliary_archives <- file.path(
  root,
  "data",
  "public",
  c(
    "yahoo_daily_1919_2021.csv",
    "paper_index_return_history.csv",
    "paper_volatility_forecasts.csv",
    "index_closes_2021-01-13.csv"
  )
)
check(
  !any(file.exists(removed_auxiliary_archives)),
  "A Yahoo/Bloomberg/FRED-derived auxiliary archive was reintroduced under data/public."
)

dockerfile_path <- file.path(root, "Dockerfile")
launcher_path <- file.path(root, "run-container.sh")
dockerignore_path <- file.path(root, ".dockerignore")
check(file.exists(dockerfile_path), "Missing digest-pinned container definition.")
check(file.exists(launcher_path), "Missing WSL2 container launcher.")
check(file.exists(dockerignore_path), "Missing Docker build-context exclusion file.")
if (file.exists(dockerfile_path)) {
  dockerfile <- readLines(dockerfile_path, warn = FALSE, encoding = "UTF-8")
  check(
    any(grepl(
      "^FROM rocker/r-ver:4[.]3[.]2@sha256:[0-9a-f]{64}$",
      dockerfile
    )),
    "The container base must pin the exact Rocker R 4.3.2 manifest digest."
  )
  check(
    !any(grepl("^[[:space:]]*(COPY|ADD)[[:space:]]", dockerfile)),
    "The environment image must not copy the repository or data into a Docker layer."
  )
}
if (file.exists(launcher_path)) {
  launcher <- paste(readLines(launcher_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  check(
    grepl("dst=/optionmetrics,readonly", launcher, fixed = TRUE),
    "The WSL2 launcher must mount the licensed input directory read-only."
  )
}
if (file.exists(dockerignore_path)) {
  dockerignore <- trimws(readLines(dockerignore_path, warn = FALSE, encoding = "UTF-8"))
  check("**" %in% dockerignore, "The Docker build context must exclude the full repository by default.")
  check("!Dockerfile" %in% dockerignore, "Dockerfile must remain available to the minimal build context.")
}

oxford_path <- file.path(root, "data", "public", "oxford_man_realized_5min.csv")
check(file.exists(oxford_path), "Missing Oxford-Man minimum subset.")
if (file.exists(oxford_path)) {
  oxford <- read.csv(oxford_path, stringsAsFactors = FALSE, check.names = FALSE)
  check(
    identical(names(oxford), c("Symbol", "Date", "rv5", "close_price")),
    "Oxford-Man minimum subset schema changed."
  )
  check(nrow(oxford) == 15769L, "Oxford-Man minimum subset row count changed.")
  check(
    setequal(unique(oxford$Symbol), c(".SPX", ".IXIC", ".DJI")),
    "Oxford-Man minimum subset symbol set changed."
  )
}

example_environment <- new.env(parent = baseenv())
sys.source(file.path(root, "config", "config.example.R"), envir = example_environment)
example_config <- get("config", envir = example_environment, inherits = FALSE)
check(isTRUE(example_config$acquire_auxiliary), "Default configuration must acquire public-source data.")
check(isTRUE(example_config$build_auxiliary), "Default configuration must rebuild auxiliary inputs.")
check(
  identical(example_config$auxiliary_data_mode, "source-current"),
  "Default configuration must label the public auxiliary vintage as source-current."
)
check(
  all(grepl("^work/auxiliary/", c(
    example_config$public_yahoo_daily,
    example_config$public_djia_daily,
    example_config$public_vxd_daily,
    example_config$public_volatility_forecasts,
    example_config$public_index_returns
  ))),
  "Default acquired or derived auxiliary paths must remain under ignored work/auxiliary/."
)

manifest_path <- file.path(root, "expected", "exhibit_manifest.csv")
check(file.exists(manifest_path), "Missing expected/exhibit_manifest.csv")
if (file.exists(manifest_path)) {
  manifest <- read.csv(manifest_path, stringsAsFactors = FALSE, check.names = FALSE)
  covered <- manifest[manifest$status == "covered", , drop = FALSE]
  missing_targets <- covered$validation_target[!file.exists(file.path(root, covered$validation_target))]
  check(!length(missing_targets), paste("Missing exhibit validation targets:", paste(missing_targets, collapse = ", ")))
  check(!anyDuplicated(covered$exhibit_id), "Covered exhibit IDs are not unique.")
}

rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
run_check <- function(script, arguments) {
  status <- system2(
    rscript,
    args = c(shQuote(file.path(root, script)), arguments),
    stdout = "",
    stderr = ""
  )
  check(identical(status, 0L), sprintf("Command failed: Rscript %s %s", script, paste(arguments, collapse = " ")))
}

run_check("src/scripts/00_verify_inputs.R", c("--config", shQuote(file.path(root, "config", "config.example.R")), "--public-only"))
run_check("src/scripts/06_validate_release.R", "--source-only")
run_check("src/scripts/07_audit_public_tree.R", character())

if (length(failures)) {
  cat(paste(sprintf("FAIL %s", failures), collapse = "\n"), "\n")
  quit(save = "no", status = 1L)
}
cat(sprintf("PASS public repository tests (%d R files parsed).\n", length(unique(r_files))))
