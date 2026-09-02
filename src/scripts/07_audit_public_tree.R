args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate src/scripts/07_audit_public_tree.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)
require_packages("jsonlite")

output <- resolve_from_root(
  root,
  arg_value(args, "--output", "outputs/proprietary_data_audit.json")
)

checks <- list()
add_check <- function(name, passes, detail) {
  checks[[length(checks) + 1L]] <<- list(
    name = name,
    passes = isTRUE(passes),
    detail = detail
  )
}

git_directory <- file.path(root, ".git")
has_git <- dir.exists(git_directory) || file.exists(git_directory)

git_run <- function(arguments, allow_failure = FALSE) {
  value <- suppressWarnings(system2(
    "git",
    c("-C", shQuote(root), arguments),
    stdout = TRUE,
    stderr = TRUE
  ))
  status <- attr(value, "status")
  if (is.null(status) || !length(status)) status <- 0L
  if (!allow_failure && status != 0L) {
    stop(sprintf("Git command failed: git %s\n%s", paste(arguments, collapse = " "), paste(value, collapse = "\n")))
  }
  value
}

read_raw_file <- function(path) {
  size <- file.info(path)$size
  connection <- file(path, open = "rb")
  on.exit(close(connection), add = TRUE)
  readBin(connection, what = "raw", n = size)
}

read_git_blob <- function(hash) {
  temporary <- tempfile("public-tree-blob-")
  on.exit(unlink(temporary, force = TRUE), add = TRUE)
  status <- suppressWarnings(system2(
    "git",
    c("-C", shQuote(root), "cat-file", "blob", hash),
    stdout = temporary,
    stderr = TRUE
  ))
  if (is.null(status) || !length(status)) status <- 0L
  if (status != 0L) stop(sprintf("Could not read Git blob %s", hash))
  read_raw_file(temporary)
}

starts_with_bytes <- function(value, signature) {
  length(value) >= length(signature) && identical(value[seq_along(signature)], as.raw(signature))
}

binary_magic <- function(value) {
  starts_with_bytes(value, c(0x50, 0x4b, 0x03, 0x04)) || # ZIP and Office containers
    starts_with_bytes(value, c(0x1f, 0x8b)) ||            # gzip
    starts_with_bytes(value, c(0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c)) || # 7z
    starts_with_bytes(value, c(0x52, 0x61, 0x72, 0x21)) || # RAR
    starts_with_bytes(value, c(0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66)) # SQLite
}

decode_text <- function(value) {
  if (any(value == as.raw(0)) || binary_magic(value)) return(NULL)
  text <- rawToChar(value)
  if (is.na(iconv(text, from = "UTF-8", to = "UTF-8"))) return(NULL)
  text
}

text_findings <- function(text) {
  if (is.null(text)) return("binary_or_non_utf8")
  findings <- character()
  if (grepl(
    "(?i)([A-Z]:[/\\\\]Users[/\\\\][^\\r\\n\\\"'<>]+|/(Users|home)/[^/[:space:]]+/)",
    text,
    perl = TRUE
  )) {
    findings <- c(findings, "personal_absolute_path")
  }
  secret_patterns <- c(
    "-----BEGIN [A-Z ]*PRIVATE KEY-----",
    "(?i)(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})",
    "AKIA[0-9A-Z]{16}",
    "xox[baprs]-[A-Za-z0-9-]{20,}",
    "(?i)(client[_-]?secret|api[_-]?key|access[_-]?token|password)[[:space:]]*[:=][[:space:]]*[\\\"']?[A-Za-z0-9+/=_-]{16,}"
  )
  if (any(vapply(secret_patterns, grepl, logical(1L), x = text, perl = TRUE))) {
    findings <- c(findings, "credential_signature")
  }
  if (grepl(
    "(?m)^[[:space:]]*[\\\"']?(108105|102434|102456|102480)[\\\"']?[,\\t][\\\"']?[0-9]{4}[-/][0-9]{2}[-/][0-9]{2}",
    text,
    perl = TRUE
  )) {
    findings <- c(findings, "optionmetrics_security_date_row")
  }
  unique(findings)
}

csv_header_findings <- function(text) {
  if (is.null(text)) return(character())
  first_line <- strsplit(text, "\\n", fixed = FALSE)[[1L]][[1L]]
  first_line <- sub("\\r$", "", first_line)
  header <- trimws(gsub("[\\\"']", "", strsplit(first_line, ",", fixed = TRUE)[[1L]]))
  findings <- character()
  option_fields <- c(
    "BestBid", "BestOffer", "Strike", "OptionID", "OpenInterest",
    "ImpliedVolatility", "Delta", "Gamma", "Vega", "Theta",
    "ContractSize", "ExpiryIndicator"
  )
  present_option <- intersect(header, option_fields)
  if (
    "OptionID" %in% present_option ||
      all(c("BestBid", "BestOffer", "Strike") %in% present_option) ||
      length(present_option) >= 4L
  ) {
    findings <- c(findings, "option_or_step1_schema")
  }
  security_price_fields <- c(
    "BidLow", "AskHigh", "TotalReturn", "AdjustmentFactor",
    "OpenPrice", "SharesOutstanding", "AdjustmentFactor2"
  )
  if (
    all(c("SecurityID", "Date", "ClosePrice") %in% header) &&
      length(intersect(header, security_price_fields)) >= 2L
  ) {
    findings <- c(findings, "security_price_schema")
  }
  if (all(c("Date", "Days", "Rate") %in% header) && length(header) <= 5L) {
    findings <- c(findings, "zero_curve_schema")
  }
  unique(findings)
}

forbidden_path <- function(path) {
  normalized <- gsub("\\\\", "/", path)
  basename_value <- basename(normalized)
  forbidden_basenames <- c(
    "option_price_view_indices_2020.csv",
    "security_price_indices_through_2021_01.csv",
    "closing_prices_2020.csv",
    "zero_curve_through_2020.csv",
    "zero_curve_2020.csv",
    "SPXfinal.csv", "NDXfinal.csv", "DJXfinal.csv", "RUTfinal.csv",
    "optfinal.csv", "optfinal3.csv"
  )
  (grepl("^data/private_raw/", normalized, ignore.case = TRUE) &&
     tolower(normalized) != "data/private_raw/readme.md") ||
    grepl("^(outputs|work|logs)/", normalized, ignore.case = TRUE) ||
    tolower(normalized) == "config/config.r" ||
    tolower(basename_value) %in% tolower(forbidden_basenames) ||
    grepl("[.](RData|rds|parquet|feather|sas7bdat|dta|zip|7z|tar|gz|bz2)$", normalized, ignore.case = TRUE)
}

scan_blob <- function(path, value) {
  text <- decode_text(value)
  findings <- text_findings(text)
  if (grepl("[.]csv$", path, ignore.case = TRUE)) {
    findings <- c(findings, csv_header_findings(text))
  }
  if (forbidden_path(path)) findings <- c(findings, "forbidden_path_or_type")
  if (length(value) >= 100 * 1024^2) findings <- c(findings, "github_oversize")
  unique(findings)
}

if (has_git) {
  index_lines <- git_run(c("ls-files", "--stage"))
  parsed <- regmatches(
    index_lines,
    regexec("^([0-9]+) ([0-9a-f]{40,64}) ([0-9]+)\\t(.*)$", index_lines)
  )
  if (!length(parsed) || any(lengths(parsed) != 5L)) stop("Could not parse the Git index.")
  modes <- vapply(parsed, `[[`, character(1L), 2L)
  hashes <- vapply(parsed, `[[`, character(1L), 3L)
  stages <- vapply(parsed, `[[`, character(1L), 4L)
  paths <- vapply(parsed, `[[`, character(1L), 5L)
} else {
  paths <- list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  paths <- gsub("\\\\", "/", paths)
  paths <- paths[!grepl("^(.git|outputs|work|logs|renv/library|renv/staging|renv/cache|renv/local)/", paths)]
  paths <- paths[paths != "config/config.R"]
  modes <- rep("source-archive", length(paths))
  hashes <- rep(NA_character_, length(paths))
  stages <- rep("0", length(paths))
}

if (!length(paths)) stop("No public source files were found.")
if (anyDuplicated(paths)) stop("The public source tree contains duplicate paths.")

sizes <- file.info(file.path(root, paths))$size
current_findings <- vector("list", length(paths))
names(current_findings) <- paths
worktree_hashes <- rep(NA_character_, length(paths))
for (index in seq_along(paths)) {
  path <- paths[[index]]
  full_path <- file.path(root, path)
  if (!file.exists(full_path) || dir.exists(full_path)) {
    current_findings[[index]] <- "missing_or_non_file"
    next
  }
  value <- read_raw_file(full_path)
  current_findings[[index]] <- scan_blob(path, value)
  if (has_git) {
    worktree_hashes[[index]] <- trimws(git_run(c("hash-object", "--", shQuote(path)))[[1L]])
  }
}

finding_paths <- function(finding, values = current_findings) {
  names(values)[vapply(values, function(entry) finding %in% entry, logical(1L))]
}

bad_modes <- paths[!modes %in% c("100644", "100755", "source-archive") | stages != "0"]
hash_mismatches <- if (has_git) paths[is.na(worktree_hashes) | worktree_hashes != hashes] else character()
forbidden_paths <- finding_paths("forbidden_path_or_type")
binary_paths <- finding_paths("binary_or_non_utf8")
oversized_paths <- finding_paths("github_oversize")
credential_paths <- finding_paths("credential_signature")
personal_paths <- finding_paths("personal_absolute_path")
vendor_row_paths <- finding_paths("optionmetrics_security_date_row")
vendor_schema_paths <- unique(c(
  finding_paths("option_or_step1_schema"),
  finding_paths("security_price_schema"),
  finding_paths("zero_curve_schema")
))

add_check(
  "public_tree_files_present",
  length(paths) > 0L && all(!is.na(sizes)),
  sprintf("Scanned %d files (%.0f bytes).", length(paths), sum(sizes, na.rm = TRUE))
)
add_check(
  "regular_git_index_entries",
  !length(bad_modes),
  if (length(bad_modes)) paste(bad_modes, collapse = ", ") else "All entries are ordinary files at index stage zero."
)
add_check(
  "worktree_matches_git_index",
  !has_git || !length(hash_mismatches),
  if (!has_git) {
    "Source archive has no Git index; content scanning completed and index equality is not applicable."
  } else if (length(hash_mismatches)) {
    paste(hash_mismatches, collapse = ", ")
  } else {
    "Every worktree file is byte-identical to its indexed blob."
  }
)
add_check(
  "no_forbidden_paths_or_archives",
  !length(forbidden_paths),
  if (length(forbidden_paths)) paste(forbidden_paths, collapse = ", ") else "No private path, raw filename, generated output, archive, or database file is included."
)
ignore_test_paths <- c(
  "data/private_raw/option_price_view_indices_2020.csv",
  "data/private_raw/security_price_indices_through_2021_01.csv",
  "data/private_raw/zero_curve_through_2020.csv",
  "accidental/option_price_view_indices_2020.csv",
  "accidental/SPXfinal.csv",
  "outputs/step1/SPXfinal.csv",
  "work/private/optfinal.csv",
  "config/config.R"
)
ignored <- rep(NA, length(ignore_test_paths))
if (has_git) {
  ignored <- vapply(ignore_test_paths, function(path) {
    status <- suppressWarnings(system2(
      "git",
      c("-C", shQuote(root), "check-ignore", "--no-index", "--quiet", "--", shQuote(path)),
      stdout = FALSE,
      stderr = FALSE
    ))
    is.null(status) || !length(status) || status == 0L
  }, logical(1L))
}
add_check(
  "private_paths_are_ignored",
  !has_git || all(ignored),
  if (!has_git) {
    "Source archive has no Git ignore engine; included-content checks still apply."
  } else if (any(!ignored)) {
    paste(ignore_test_paths[!ignored], collapse = ", ")
  } else {
    "Canonical private inputs, row-level outputs, and local configuration are protected by Git ignore rules."
  }
)
add_check(
  "text_only_public_tree",
  !length(binary_paths),
  if (length(binary_paths)) paste(binary_paths, collapse = ", ") else "Every included file is UTF-8 text with no binary signature or NUL byte."
)
add_check(
  "github_size_limit",
  !length(oversized_paths),
  if (length(oversized_paths)) paste(oversized_paths, collapse = ", ") else "No included file is 100 MB or larger."
)
add_check(
  "no_credentials",
  !length(credential_paths),
  if (length(credential_paths)) paste(credential_paths, collapse = ", ") else "No private-key or credential signature was found."
)
add_check(
  "no_personal_absolute_paths",
  !length(personal_paths),
  if (length(personal_paths)) paste(personal_paths, collapse = ", ") else "No personal home-directory path was found."
)
add_check(
  "no_optionmetrics_observation_rows",
  !length(vendor_row_paths),
  if (length(vendor_row_paths)) paste(vendor_row_paths, collapse = ", ") else "No row begins with a paper SecurityID and observation date."
)
add_check(
  "no_optionmetrics_or_step1_csv_schema",
  !length(vendor_schema_paths),
  if (length(vendor_schema_paths)) paste(vendor_schema_paths, collapse = ", ") else "No CSV has an OptionMetrics raw or row-level Step 1 schema."
)

commit_count <- 0L
reachable_blob_count <- 0L
reachable_findings <- list()
if (has_git) {
  commit_text <- git_run(c("rev-list", "--all", "--count"), allow_failure = TRUE)
  if (length(commit_text) && grepl("^[0-9]+$", trimws(commit_text[[1L]]))) {
    commit_count <- as.integer(trimws(commit_text[[1L]]))
  }
  object_lines <- git_run(c("rev-list", "--objects", "--all"), allow_failure = TRUE)
  object_lines <- object_lines[grepl("^[0-9a-f]{40,64}( |$)", object_lines)]
  if (length(object_lines)) {
    object_hashes <- sub(" .*", "", object_lines)
    object_paths <- ifelse(grepl(" ", object_lines, fixed = TRUE), sub("^[^ ]+ ", "", object_lines), "")
    object_types <- vapply(
      object_hashes,
      function(hash) trimws(git_run(c("cat-file", "-t", hash))[[1L]]),
      character(1L)
    )
    blob_rows <- which(object_types == "blob")
    reachable_blob_count <- length(unique(object_hashes[blob_rows]))
    for (row in blob_rows) {
      path <- object_paths[[row]]
      if (!nzchar(path)) path <- paste0("<blob:", object_hashes[[row]], ">")
      findings <- scan_blob(path, read_git_blob(object_hashes[[row]]))
      if (length(findings)) reachable_findings[[path]] <- unique(c(reachable_findings[[path]], findings))
    }
  }
}
add_check(
  "reachable_git_history_clean",
  !length(reachable_findings),
  if (!has_git) {
    "Source archive has no Git object database; history scanning is not applicable."
  } else if (length(reachable_findings)) {
    paste(names(reachable_findings), collapse = ", ")
  } else {
    sprintf("Scanned %d reachable commits and %d unique reachable blobs; no prohibited content was found.", commit_count, reachable_blob_count)
  }
)

unreachable_hashes <- character()
unreachable_bytes <- numeric()
unreachable_findings <- list()
if (has_git) {
  fsck <- git_run(c("fsck", "--full", "--unreachable", "--no-reflogs", "--cache"), allow_failure = TRUE)
  blob_lines <- fsck[grepl("^(dangling|unreachable) blob [0-9a-f]{40,64}$", fsck)]
  unreachable_hashes <- unique(sub("^(dangling|unreachable) blob ", "", blob_lines))
  if (length(unreachable_hashes)) {
    for (hash in unreachable_hashes) {
      value <- read_git_blob(hash)
      unreachable_bytes <- c(unreachable_bytes, length(value))
      findings <- text_findings(decode_text(value))
      if (length(value) >= 100 * 1024^2) findings <- c(findings, "github_oversize")
      if (length(findings)) unreachable_findings[[hash]] <- unique(findings)
    }
  }
}
add_check(
  "unreachable_local_git_blobs_clean",
  !length(unreachable_findings),
  if (!has_git) {
    "Source archive has no unreachable Git objects."
  } else if (length(unreachable_findings)) {
    paste(names(unreachable_findings), collapse = ", ")
  } else {
    sprintf(
      "Scanned %d unreachable local blobs (%.0f bytes); none contains a credential, personal path, binary payload, oversized payload, or vendor observation row.",
      length(unreachable_hashes),
      sum(unreachable_bytes)
    )
  }
)

failed <- vapply(checks, function(check) !check$passes, logical(1L))
result <- list(
  purpose = "Strict public-tree audit for OptionMetrics observations, row-level derivatives, credentials, and local paths",
  checked_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  source_mode = if (has_git) "git-index-and-object-database" else "source-archive",
  passed = sum(!failed),
  failed = sum(failed),
  current_tree = list(
    files = length(paths),
    bytes = sum(sizes, na.rm = TRUE),
    indexed_worktree_mismatches = unname(hash_mismatches)
  ),
  reachable_history = list(
    commits = commit_count,
    unique_blobs = reachable_blob_count,
    findings = reachable_findings
  ),
  unreachable_local_objects = list(
    blobs = length(unreachable_hashes),
    bytes = sum(unreachable_bytes),
    findings = unreachable_findings,
    note = "Unreachable objects are not transferred by an ordinary Git push; they are scanned as local release hygiene."
  ),
  checks = checks
)
write_json(result, output)
for (check in checks) {
  cat(sprintf("%s %s: %s\n", if (check$passes) "PASS" else "FAIL", check$name, check$detail))
}
if (any(failed)) stop(sprintf("Public-tree audit failed %d check(s). See %s", sum(failed), output))
log_message("Strict public-tree audit passed.")
