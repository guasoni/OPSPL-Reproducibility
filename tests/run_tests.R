script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate tests/run_tests.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)

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

step1_fingerprint_path <- file.path(root, "expected", "step1_paper_vintage_fingerprints.csv")
check(file.exists(step1_fingerprint_path), "Missing expected/step1_paper_vintage_fingerprints.csv")
if (file.exists(step1_fingerprint_path)) {
  step1_fingerprints <- read.csv(step1_fingerprint_path, stringsAsFactors = FALSE, check.names = FALSE)
  check(
    identical(
      names(step1_fingerprints),
      c("file", "rows", "canonical_bytes", "canonical_sha256", "legacy_bytes", "legacy_sha256")
    ),
    "Step 1 fingerprint contract does not distinguish canonical content from legacy bytes."
  )
  check(all(step1_fingerprints$rows > 0), "Step 1 fingerprint contract contains an invalid row count.")
  check(all(step1_fingerprints$canonical_bytes > 0), "Step 1 canonical byte counts are invalid.")
  check(
    all(grepl("^[0-9a-f]{64}$", step1_fingerprints$canonical_sha256)),
    "Step 1 canonical hashes are malformed."
  )
  check(
    all(grepl("^[0-9a-f]{64}$", step1_fingerprints$legacy_sha256)),
    "Step 1 legacy hashes are malformed."
  )
}

bom_fixture <- tempfile(fileext = ".csv")
writeBin(
  c(as.raw(c(0xEF, 0xBB, 0xBF)), charToRaw("SecurityID,Date\r\n108105,2020-01-01\r\n")),
  bom_fixture
)
bom_connection <- file(bom_fixture, open = "rb")
bom_lines <- readLines(bom_connection, warn = FALSE)
close(bom_connection)
unlink(bom_fixture)
bom_header <- strip_utf8_bom(bom_lines[[1L]])
bom_table <- data.table::fread(
  text = paste(c(bom_header, bom_lines[-1L]), collapse = "\n"),
  showProgress = FALSE
)
check(
  identical(bom_header, "SecurityID,Date") &&
    identical(names(bom_table), c("SecurityID", "Date")) &&
    nrow(bom_table) == 1L,
  "Binary CSV streaming does not handle a UTF-8 BOM under the C locale."
)

canonical_lf <- tempfile(fileext = ".csv")
canonical_crlf <- tempfile(fileext = ".csv")
canonical_perturbed <- tempfile(fileext = ".csv")
canonical_distinct <- tempfile(fileext = ".csv")
writeBin(charToRaw("value,label\n1,quoted\n"), canonical_lf)
writeBin(charToRaw("value,label\r\n1.0,quoted\r\n"), canonical_crlf)
writeBin(charToRaw("value,label\n1.0000000000004,quoted\n"), canonical_perturbed)
writeBin(charToRaw("value,label\n1.000000002,quoted\n"), canonical_distinct)
fingerprint_lf <- canonical_csv_fingerprint(canonical_lf)
fingerprint_crlf <- canonical_csv_fingerprint(canonical_crlf)
fingerprint_perturbed <- canonical_csv_fingerprint(canonical_perturbed)
fingerprint_distinct <- canonical_csv_fingerprint(canonical_distinct)
unlink(c(canonical_lf, canonical_crlf, canonical_perturbed, canonical_distinct))
check(
  identical(fingerprint_lf$sha256, fingerprint_crlf$sha256) &&
    identical(fingerprint_lf$sha256, fingerprint_perturbed$sha256),
  "Canonical CSV fingerprints depend on line endings or immaterial numeric serialization."
)
check(
  !identical(fingerprint_lf$sha256, fingerprint_distinct$sha256),
  "Canonical CSV fingerprints conceal a material numeric difference."
)

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
  check(
    grepl("Rscript src/scripts/bootstrap.R", launcher, fixed = TRUE),
    "The WSL2 launcher must restore locked packages before maintenance checks."
  )
  check(
    grepl("SUDO_UID", launcher, fixed = TRUE) && grepl("SUDO_GID", launcher, fixed = TRUE),
    "The WSL2 launcher must preserve the invoking user when run through sudo."
  )
}

acquisition_path <- file.path(root, "src", "scripts", "acquire_auxiliary_data.R")
if (file.exists(acquisition_path)) {
  acquisition <- paste(readLines(acquisition_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  check(
    grepl("--http1.1", acquisition, fixed = TRUE),
    "The FRED acquisition must provide an HTTP/1.1 transport fallback."
  )
  check(
    grepl("ClosePrice = round(c(", acquisition, fixed = TRUE),
    "Every supplemental January 2021 index close must be rounded to quoted precision."
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
run_check("tests/test_method_formulas.R", character())
run_check("src/scripts/06_validate_release.R", "--source-only")
run_check("src/scripts/07_audit_public_tree.R", character())

if (length(failures)) {
  cat(paste(sprintf("FAIL %s", failures), collapse = "\n"), "\n")
  quit(save = "no", status = 1L)
}
cat(sprintf("PASS public repository tests (%d R files parsed).\n", length(unique(r_files))))
