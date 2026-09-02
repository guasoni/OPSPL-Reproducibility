args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate src/scripts/run_all.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)
config <- read_config(root, args)
config_path <- attr(config, "path")
workers <- as.integer(arg_value(args, "--cores", if (is.null(config$workers)) "1" else as.character(config$workers)))
if (is.na(workers) || workers < 1L) stop("--cores must be a positive integer")
skip_step1 <- arg_flag(args, "--skip-step1")
skip_optimization <- arg_flag(args, "--skip-optimization")
refresh_auxiliary <- arg_flag(args, "--refresh-auxiliary")
if (refresh_auxiliary && skip_optimization) {
  stop("Do not combine --refresh-auxiliary with --skip-optimization; refreshed inputs require new portfolios.")
}

rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")

run_script <- function(relative_script, extra_args = character()) {
  path <- file.path(root, relative_script)
  assert_file(path, "Pipeline script")
  command_args <- c(
    shQuote(path),
    "--config",
    shQuote(config_path),
    extra_args
  )
  log_message("> Rscript %s", paste(command_args, collapse = " "))
  status <- system2(rscript, args = command_args, stdout = "", stderr = "")
  if (!identical(status, 0L)) stop(sprintf("Pipeline stage failed: %s", relative_script))
}

if (!identical(config$acquire_auxiliary, FALSE)) {
  run_script(
    "src/scripts/acquire_auxiliary_data.R",
    if (refresh_auxiliary) "--refresh" else character()
  )
}
run_script("src/scripts/00_verify_inputs.R")
if (!skip_step1) run_script("src/scripts/01_build_step1.R")
run_script("src/scripts/02_filter_options.R")
if (!identical(config$build_auxiliary, FALSE)) {
  run_script("src/scripts/03_build_auxiliary_inputs.R")
}
run_script("src/scripts/03_attach_forecasts.R")

if (!skip_optimization) {
  for (ticker in c("SPX", "NDX", "DJX")) {
    for (mode in c("unconstrained", "solvency")) {
      run_script(
        "src/scripts/04_optimize_portfolios.R",
        c("--ticker", ticker, "--mode", mode, "--cores", as.character(workers))
      )
    }
  }
  # The paper reports the analytical small-position-limit benchmark for SPX
  # only, so the initial-release workflow does not compute unused NDX/DJX files.
  run_script(
    "src/scripts/04_optimize_portfolios.R",
    c("--ticker", "SPX", "--mode", "small", "--gamma", "1", "--cores", as.character(workers))
  )
  run_script(
    "src/scripts/04_optimize_portfolios.R",
    c("--ticker", "SPX", "--mode", "unconstrained", "--pricing", "midprice", "--cores", as.character(workers))
  )
}

run_script("src/scripts/05_generate_outputs.R")
run_script("src/scripts/06_validate_release.R")
log_message("Reproduction completed. Results: %s", pipeline_output_root(root, config))
