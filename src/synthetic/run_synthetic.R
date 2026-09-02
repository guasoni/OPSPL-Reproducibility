args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate src/synthetic/run_synthetic.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)

workers <- suppressWarnings(as.integer(arg_value(args, "--cores", "1")))
if (is.na(workers) || workers < 1L) stop("--cores must be a positive integer.")
rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")

run_script <- function(relative_script, extra_args = character()) {
  path <- file.path(root, relative_script)
  assert_file(path, "Synthetic-pipeline script")
  command_args <- c(shQuote(path), extra_args)
  log_message("> Rscript %s", paste(command_args, collapse = " "))
  status <- system2(rscript, args = command_args, stdout = "", stderr = "")
  if (!identical(status, 0L)) stop(sprintf("Synthetic-pipeline stage failed: %s", relative_script))
}

cat(paste0(
  "Running the deterministic synthetic integration test.\n",
  "These generated values are non-empirical and do not reproduce or validate the paper's estimates.\n"
))

run_script("src/synthetic/generate_synthetic_inputs.R")
config_path <- file.path(root, "work", "synthetic", "config.R")
config_args <- c("--config", shQuote(config_path))
run_script("src/scripts/01_build_step1.R", config_args)
run_script("src/scripts/02_filter_options.R", config_args)
run_script("src/scripts/03_attach_forecasts.R", config_args)

for (ticker in c("SPX", "NDX", "DJX")) {
  for (mode in c("unconstrained", "solvency")) {
    run_script(
      "src/scripts/04_optimize_portfolios.R",
      c(config_args, "--ticker", ticker, "--mode", mode, "--cores", as.character(workers))
    )
  }
}
run_script(
  "src/scripts/04_optimize_portfolios.R",
  c(config_args, "--ticker", "SPX", "--mode", "small", "--gamma", "1", "--cores", as.character(workers))
)
run_script(
  "src/scripts/04_optimize_portfolios.R",
  c(config_args, "--ticker", "SPX", "--mode", "unconstrained", "--pricing", "midprice", "--cores", as.character(workers))
)
run_script("src/synthetic/validate_synthetic.R", config_args)

log_message(
  "Synthetic integration test passed. Isolated results: %s",
  file.path(root, "work", "synthetic", "outputs")
)
