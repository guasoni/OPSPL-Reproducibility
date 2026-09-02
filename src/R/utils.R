script_path <- function() {
  hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(hit) != 1L) stop("Cannot determine the current R script path.")
  normalizePath(sub("^--file=", "", hit), winslash = "/", mustWork = TRUE)
}

repository_root <- function() {
  normalizePath(file.path(dirname(script_path()), "..", ".."), winslash = "/", mustWork = TRUE)
}

arg_value <- function(args, name, default = NULL) {
  hit <- which(args == name)
  if (length(hit) == 0L) return(default)
  if (hit[[1L]] == length(args)) stop(sprintf("Missing value after %s", name))
  args[[hit[[1L]] + 1L]]
}

arg_flag <- function(args, name) {
  name %in% args
}

resolve_from_root <- function(root, path) {
  if (is.null(path) || !nzchar(path)) return(NULL)
  expanded <- path.expand(path)
  is_absolute <- grepl("^[A-Za-z]:[/\\\\]", expanded) || startsWith(expanded, "/")
  candidate <- if (is_absolute) expanded else file.path(root, expanded)
  normalizePath(candidate, winslash = "/", mustWork = FALSE)
}

pipeline_output_root <- function(root, config) {
  path <- if (is.null(config$output_root)) "outputs" else config$output_root
  resolve_from_root(root, path)
}

pipeline_work_root <- function(root, config) {
  path <- if (is.null(config$work_root)) "work" else config$work_root
  resolve_from_root(root, path)
}

read_config <- function(root, args) {
  config_argument <- arg_value(args, "--config", "config/config.R")
  config_path <- resolve_from_root(root, config_argument)
  if (!file.exists(config_path)) {
    stop(
      sprintf(
        "Configuration file not found: %s\nCopy config/config.example.R to config/config.R and edit the input paths.",
        config_path
      )
    )
  }
  environment <- new.env(parent = baseenv())
  sys.source(config_path, envir = environment)
  if (!exists("config", envir = environment, inherits = FALSE)) {
    stop("The configuration file must define a list named `config`.")
  }
  config <- get("config", envir = environment, inherits = FALSE)
  if (!is.list(config)) stop("`config` must be a list.")
  attr(config, "path") <- config_path
  config
}

require_packages <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1L))]
  if (length(missing)) {
    stop(
      sprintf(
        "Missing R package(s): %s. Run Rscript src/scripts/bootstrap.R before reproducing the paper.",
        paste(missing, collapse = ", ")
      )
    )
  }
}

ensure_directory <- function(path) {
  if (!dir.exists(path) && !dir.create(path, recursive = TRUE, showWarnings = FALSE)) {
    stop(sprintf("Cannot create directory: %s", path))
  }
  invisible(path)
}

assert_file <- function(path, label = "Input") {
  if (is.null(path) || !file.exists(path)) stop(sprintf("%s not found: %s", label, path))
  invisible(path)
}

log_message <- function(...) {
  cat(sprintf(...), "\n", sep = "")
  flush.console()
}

normalize_iso_date <- function(x) {
  value <- as.character(x)
  value[is.na(x)] <- NA_character_
  substr(value, 1L, 10L)
}

sha256_file <- function(path) {
  require_packages("digest")
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

file_fingerprint <- function(path, include_hash = TRUE) {
  info <- file.info(path)
  list(
    path = normalizePath(path, winslash = "/", mustWork = TRUE),
    bytes = unname(info$size),
    modified_utc = format(info$mtime, tz = "UTC", usetz = TRUE),
    sha256 = if (isTRUE(include_hash)) sha256_file(path) else NULL
  )
}

write_json <- function(value, path) {
  require_packages("jsonlite")
  ensure_directory(dirname(path))
  jsonlite::write_json(
    value,
    path = path,
    pretty = TRUE,
    auto_unbox = TRUE,
    digits = NA,
    null = "null",
    na = "null"
  )
  cat("\n", file = path, append = TRUE)
  invisible(path)
}
