args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate reproduce.R")
root <- normalizePath(
  dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")),
  winslash = "/"
)
invocation_directory <- normalizePath(getwd(), winslash = "/")

usage <- function() {
  cat(
    paste0(
      "Reproduce the currently covered paper results from licensed OptionMetrics exports.\n\n",
      "Usage:\n",
      "  Rscript reproduce.R --data-dir PATH [--cores N]\n",
      "  Rscript reproduce.R --config PATH [--cores N]\n",
      "  Rscript reproduce.R --synthetic [--cores N]\n\n",
      "Required files for --data-dir:\n",
      "  option_price_view_indices_2020.csv\n",
      "  security_price_indices_through_2021_01.csv\n",
      "  zero_curve_through_2020.csv\n\n",
      "Paper-vintage filenames are documented in config/config.paper-vintage.example.R.\n\n",
      "Options:\n",
      "  --synthetic                           Run the generated non-empirical integration fixture\n",
      "  --mode current-vintage|paper-vintage  Default: current-vintage\n",
      "  --cores N                            Parallel workers; default: 1\n",
      "  --skip-restore                       Do not run renv::restore()\n",
      "  --refresh-auxiliary                  Redownload Yahoo, CRAN DJIA, and FRED VXD sources\n",
      "  --check-inputs                       Validate files and exit before the long run\n",
      "  --skip-step1                         Reuse existing local Step 1 outputs\n",
      "  --skip-optimization                  Reuse existing local optimizer outputs\n",
      "  --help                               Show this message\n"
    )
  )
}

value_options <- c("--data-dir", "--config", "--mode", "--cores")
flag_options <- c(
  "--synthetic", "--skip-restore", "--refresh-auxiliary", "--check-inputs",
  "--skip-step1", "--skip-optimization", "--help"
)
values <- list()
flags <- character()
i <- 1L
while (i <= length(args)) {
  argument <- args[[i]]
  if (argument %in% value_options) {
    if (i == length(args)) stop(sprintf("Missing value after %s", argument))
    if (!is.null(values[[argument]])) stop(sprintf("Option supplied more than once: %s", argument))
    values[[argument]] <- args[[i + 1L]]
    i <- i + 2L
  } else if (argument %in% flag_options) {
    flags <- c(flags, argument)
    i <- i + 1L
  } else {
    stop(sprintf("Unknown argument: %s\nRun Rscript reproduce.R --help for usage.", argument))
  }
}

if ("--help" %in% flags) {
  usage()
  quit(save = "no", status = 0L)
}

if (!is.null(values[["--config"]]) && !is.null(values[["--data-dir"]])) {
  stop("Use either --config or --data-dir, not both.")
}
if (!is.null(values[["--config"]]) && !is.null(values[["--mode"]])) {
  stop("Do not combine --config and --mode; set data_mode inside the configuration file.")
}
synthetic <- "--synthetic" %in% flags
if (synthetic) {
  incompatible_values <- intersect(names(values), c("--data-dir", "--config", "--mode"))
  incompatible_flags <- intersect(
    flags,
    c("--refresh-auxiliary", "--check-inputs", "--skip-step1", "--skip-optimization")
  )
  incompatible <- c(incompatible_values, incompatible_flags)
  if (length(incompatible)) {
    stop(sprintf("Do not combine --synthetic with %s.", paste(incompatible, collapse = ", ")))
  }
}

cores <- suppressWarnings(as.integer(if (is.null(values[["--cores"]])) "1" else values[["--cores"]]))
if (is.na(cores) || cores < 1L) stop("--cores must be a positive integer.")

resolve_from_invocation <- function(path) {
  expanded <- path.expand(path)
  absolute <- grepl("^[A-Za-z]:[/\\\\]", expanded) || startsWith(expanded, "/")
  normalizePath(if (absolute) expanded else file.path(invocation_directory, expanded), winslash = "/", mustWork = FALSE)
}

if (synthetic) {
  config_path <- NULL
} else if (!is.null(values[["--config"]])) {
  config_path <- resolve_from_invocation(values[["--config"]])
  if (!file.exists(config_path)) stop(sprintf("Configuration file not found: %s", config_path))
} else {
  data_directory <- if (is.null(values[["--data-dir"]])) {
    file.path(root, "data", "private_raw")
  } else {
    resolve_from_invocation(values[["--data-dir"]])
  }
  if (!dir.exists(data_directory)) stop(sprintf("OptionMetrics export directory not found: %s", data_directory))

  data_mode <- if (is.null(values[["--mode"]])) "current-vintage" else values[["--mode"]]
  if (!data_mode %in% c("current-vintage", "paper-vintage")) {
    stop("--mode must be current-vintage or paper-vintage.")
  }

  private_files <- if (identical(data_mode, "paper-vintage")) {
    c(
      option_prices = "option_price_view_indices_2020.csv",
      security_prices = "closing_prices_2020.csv",
      zero_curve = "zero_curve_2020.csv"
    )
  } else {
    c(
      option_prices = "option_price_view_indices_2020.csv",
      security_prices = "security_price_indices_through_2021_01.csv",
      zero_curve = "zero_curve_through_2020.csv"
    )
  }
  private_paths <- file.path(data_directory, unname(private_files))
  missing <- private_files[!file.exists(private_paths)]
  if (length(missing)) {
    stop(
      sprintf(
        "Missing required OptionMetrics export(s) in %s:\n%s",
        data_directory,
        paste(sprintf("  - %s", unname(missing)), collapse = "\n")
      )
    )
  }

  config <- list(
    data_mode = data_mode,
    option_prices = private_paths[[1L]],
    security_prices = private_paths[[2L]],
    zero_curve = private_paths[[3L]],
    supplemental_closes = if (identical(data_mode, "paper-vintage")) {
      file.path(root, "work", "auxiliary", "index_closes_2021-01-13.csv")
    } else {
      NULL
    },
    acquire_auxiliary = TRUE,
    build_auxiliary = TRUE,
    auxiliary_data_mode = "source-current",
    public_yahoo_daily = file.path(root, "work", "auxiliary", "yahoo_daily.csv"),
    public_djia_daily = file.path(root, "work", "auxiliary", "djia_daily.csv"),
    public_vxd_daily = file.path(root, "work", "auxiliary", "vxd_daily.csv"),
    public_oxford_man_realized = file.path(root, "data", "public", "oxford_man_realized_5min.csv"),
    public_volatility_forecasts = file.path(root, "work", "auxiliary", "paper_volatility_forecasts.csv"),
    public_index_returns = file.path(root, "work", "auxiliary", "paper_index_return_history.csv"),
    supplemental_closes_generated = file.path(root, "work", "auxiliary", "index_closes_2021-01-13.csv"),
    auxiliary_acquisition_report = file.path(root, "work", "auxiliary", "acquisition_report.json"),
    auxiliary_build_report = file.path(root, "work", "auxiliary", "build_report.json"),
    output_root = "outputs",
    work_root = "work",
    workers = cores,
    chunk_lines = 250000L,
    reuse_step1_selection = TRUE
  )
  work_directory <- file.path(root, "work")
  if (!dir.exists(work_directory) && !dir.create(work_directory, recursive = TRUE)) {
    stop(sprintf("Cannot create work directory: %s", work_directory))
  }
  config_path <- file.path(work_directory, "reproduce_config.R")
  writeLines(c("config <-", capture.output(dput(config))), config_path, useBytes = TRUE)
}

old_directory <- setwd(root)
on.exit(setwd(old_directory), add = TRUE)
Sys.setenv(RENV_PROJECT = root)
source(file.path(root, "renv", "activate.R"), local = globalenv())
if (!requireNamespace("renv", quietly = TRUE)) {
  stop("renv could not be activated. Check network access and rerun the command.")
}
if (!("--skip-restore" %in% flags)) {
  cat("Restoring the locked R environment...\n")
  renv::restore(prompt = FALSE)
}

rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
if (synthetic) {
  synthetic_arguments <- c(
    shQuote(file.path(root, "src", "synthetic", "run_synthetic.R")),
    "--cores", as.character(cores)
  )
  status <- system2(rscript, args = synthetic_arguments, stdout = "", stderr = "")
  if (!identical(status, 0L)) stop(sprintf("Synthetic integration test failed with status %s.", status))
  cat("Synthetic integration test completed successfully. These values are non-empirical.\n")
  quit(save = "no", status = 0L)
}

if ("--check-inputs" %in% flags) {
  check_environment <- new.env(parent = baseenv())
  sys.source(config_path, envir = check_environment)
  check_config <- get("config", envir = check_environment, inherits = FALSE)
  if (!identical(check_config$acquire_auxiliary, FALSE)) {
    acquisition_arguments <- c(
      shQuote(file.path(root, "src", "scripts", "acquire_auxiliary_data.R")),
      "--config", shQuote(config_path)
    )
    if ("--refresh-auxiliary" %in% flags) acquisition_arguments <- c(acquisition_arguments, "--refresh")
    acquisition_status <- system2(rscript, args = acquisition_arguments, stdout = "", stderr = "")
    if (!identical(acquisition_status, 0L)) {
      stop(sprintf("Auxiliary-data acquisition failed with status %s.", acquisition_status))
    }
  }
  check_arguments <- c(
    shQuote(file.path(root, "src", "scripts", "00_verify_inputs.R")),
    "--config", shQuote(config_path)
  )
  status <- system2(rscript, args = check_arguments, stdout = "", stderr = "")
  if (!identical(status, 0L)) stop(sprintf("Input validation failed with status %s.", status))
  cat("All private schemas and distributed/acquired auxiliary checks passed.\n")
  quit(save = "no", status = 0L)
}

run_arguments <- c(
  shQuote(file.path(root, "src", "scripts", "run_all.R")),
  "--config", shQuote(config_path),
  "--cores", as.character(cores)
)
if ("--refresh-auxiliary" %in% flags) run_arguments <- c(run_arguments, "--refresh-auxiliary")
if ("--skip-step1" %in% flags) run_arguments <- c(run_arguments, "--skip-step1")
if ("--skip-optimization" %in% flags) run_arguments <- c(run_arguments, "--skip-optimization")

cat("Starting the R reproduction pipeline. Generated files remain under ignored outputs/ and work/ directories.\n")
status <- system2(rscript, args = run_arguments, stdout = "", stderr = "")
if (!identical(status, 0L)) stop(sprintf("Reproduction failed with status %s.", status))
cat("Reproduction and numerical validation completed successfully.\n")
