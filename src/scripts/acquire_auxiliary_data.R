args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate src/scripts/acquire_auxiliary_data.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)
require_packages(c("data.table", "jsonlite", "digest"))

config <- read_config(root, args)
refresh <- arg_flag(args, "--refresh")

path_from_config <- function(field, fallback) {
  value <- config[[field]]
  resolve_from_root(root, if (is.null(value)) fallback else value)
}

yahoo_path <- path_from_config("public_yahoo_daily", "work/auxiliary/yahoo_daily.csv")
djia_path <- path_from_config("public_djia_daily", "work/auxiliary/djia_daily.csv")
vxd_path <- path_from_config("public_vxd_daily", "work/auxiliary/vxd_daily.csv")
supplemental_path <- path_from_config(
  "supplemental_closes_generated",
  "work/auxiliary/index_closes_2021-01-13.csv"
)
report_path <- path_from_config(
  "auxiliary_acquisition_report",
  "work/auxiliary/acquisition_report.json"
)
cache_dir <- file.path(dirname(report_path), "downloads")
ensure_directory(cache_dir)

start_date <- as.Date("1919-12-31")
end_date <- as.Date("2021-06-01") # Yahoo period2 is exclusive.
yahoo_tickers <- c(
  "^GSPC", "SPY", "^NDX", "^IXIC", "QQQ", "^DJI", "DIA", "^RUT", "^VIX", "^VXN"
)

unix_time <- function(date) as.numeric(as.POSIXct(date, tz = "UTC"))

numeric_json_array <- function(values) {
  vapply(
    values,
    function(value) if (is.null(value)) NA_real_ else as.numeric(value),
    FUN.VALUE = numeric(1L)
  )
}

download_yahoo_ticker <- function(ticker) {
  encoded <- utils::URLencode(ticker, reserved = TRUE)
  url <- sprintf(
    paste0(
      "https://query1.finance.yahoo.com/v8/finance/chart/%s",
      "?period1=%.0f&period2=%.0f&interval=1d&events=history&includeAdjustedClose=true"
    ),
    encoded,
    unix_time(start_date),
    unix_time(end_date)
  )
  log_message("Downloading Yahoo series %s", ticker)
  payload <- jsonlite::fromJSON(url, simplifyVector = FALSE)
  if (!is.null(payload$chart$error)) {
    stop(sprintf("Yahoo returned an error for %s: %s", ticker, payload$chart$error$description))
  }
  result <- payload$chart$result[[1L]]
  quote <- result$indicators$quote[[1L]]
  timestamps <- as.numeric(unlist(result$timestamp, use.names = FALSE))
  adjusted <- numeric_json_array(result$indicators$adjclose[[1L]]$adjclose)
  frame <- data.table::data.table(
    Ticker = ticker,
    Date = as.Date(as.POSIXct(timestamps, origin = "1970-01-01", tz = "UTC")),
    Open = numeric_json_array(quote$open),
    High = numeric_json_array(quote$high),
    Low = numeric_json_array(quote$low),
    Close = numeric_json_array(quote$close),
    Adjusted = adjusted,
    Volume = numeric_json_array(quote$volume)
  )
  if (!nrow(frame)) stop(sprintf("Yahoo returned no observations for %s.", ticker))
  frame
}

valid_yahoo_cache <- function(path) {
  if (!file.exists(path)) return(FALSE)
  header <- names(data.table::fread(path, nrows = 0L, showProgress = FALSE))
  if (!identical(header, c("Ticker", "Date", "Open", "High", "Low", "Close", "Adjusted", "Volume"))) {
    return(FALSE)
  }
  frame <- data.table::fread(path, select = c("Ticker", "Date"), showProgress = FALSE)
  setequal(unique(frame$Ticker), yahoo_tickers)
}

if (refresh || !valid_yahoo_cache(yahoo_path)) {
  yahoo <- data.table::rbindlist(lapply(yahoo_tickers, download_yahoo_ticker), use.names = TRUE, fill = TRUE)
  data.table::setorder(yahoo, Ticker, Date)
  ensure_directory(dirname(yahoo_path))
  data.table::fwrite(yahoo, yahoo_path, na = "NA", quote = TRUE)
} else {
  log_message("Reusing cached Yahoo series: %s", yahoo_path)
  yahoo <- data.table::fread(yahoo_path, showProgress = FALSE)
  yahoo[, Date := as.Date(Date)]
}

stevedata_version <- "1.8.0"
stevedata_sha256 <- "042bf29bfc46e86d7f3fe3bb0427397660dfe5f71122f87b69bf96072fed0380"
stevedata_archive <- file.path(cache_dir, sprintf("stevedata_%s.tar.gz", stevedata_version))
stevedata_urls <- c(
  sprintf("https://cran.r-project.org/src/contrib/stevedata_%s.tar.gz", stevedata_version),
  sprintf("https://cran.r-project.org/src/contrib/Archive/stevedata/stevedata_%s.tar.gz", stevedata_version)
)

download_first <- function(urls, destination) {
  errors <- character()
  for (url in urls) {
    temporary <- tempfile(tmpdir = dirname(destination), fileext = ".download")
    outcome <- tryCatch({
      utils::download.file(url, temporary, mode = "wb", quiet = TRUE)
      TRUE
    }, error = function(error) {
      errors <<- c(errors, sprintf("%s: %s", url, conditionMessage(error)))
      FALSE
    })
    if (outcome && file.exists(temporary) && file.info(temporary)$size > 0) {
      ensure_directory(dirname(destination))
      if (!file.copy(temporary, destination, overwrite = TRUE)) {
        stop(sprintf("Could not move the download into %s", destination))
      }
      unlink(temporary)
      return(url)
    }
    if (file.exists(temporary)) unlink(temporary)
  }
  stop(sprintf("Every download URL failed:\n%s", paste(errors, collapse = "\n")))
}

stevedata_url_used <- NA_character_
archive_valid <- file.exists(stevedata_archive) &&
  identical(tolower(sha256_file(stevedata_archive)), stevedata_sha256)
if (refresh || !archive_valid) {
  log_message("Downloading pinned CRAN DJIA source (stevedata %s)", stevedata_version)
  stevedata_url_used <- download_first(stevedata_urls, stevedata_archive)
}
actual_stevedata_sha256 <- tolower(sha256_file(stevedata_archive))
if (!identical(actual_stevedata_sha256, stevedata_sha256)) {
  stop(
    sprintf(
      "Pinned stevedata archive checksum mismatch: expected %s, observed %s",
      stevedata_sha256,
      actual_stevedata_sha256
    )
  )
}

if (refresh || !file.exists(djia_path)) {
  members <- utils::untar(stevedata_archive, list = TRUE)
  member <- members[grepl("(^|/)data/DJIA[.]rda$", members)]
  if (length(member) != 1L) stop("The pinned stevedata archive does not contain one data/DJIA.rda file.")
  extraction_dir <- tempfile("stevedata-", tmpdir = cache_dir)
  ensure_directory(extraction_dir)
  on.exit(unlink(extraction_dir, recursive = TRUE, force = TRUE), add = TRUE)
  utils::untar(stevedata_archive, files = member, exdir = extraction_dir)
  environment <- new.env(parent = emptyenv())
  load(file.path(extraction_dir, member), envir = environment)
  if (!exists("DJIA", envir = environment, inherits = FALSE)) {
    stop("DJIA object is absent from the pinned stevedata archive.")
  }
  djia <- data.table::as.data.table(get("DJIA", envir = environment, inherits = FALSE))
  if (!all(c("date", "value") %in% names(djia))) stop("Unexpected stevedata DJIA schema.")
  djia <- djia[, .(Date = as.Date(date), DJI = as.numeric(value))]
  djia <- djia[Date >= as.Date("1927-01-01") & Date < end_date & is.finite(DJI)]
  data.table::setorder(djia, Date)
  ensure_directory(dirname(djia_path))
  data.table::fwrite(djia, djia_path, na = "NA", quote = TRUE)
} else {
  log_message("Reusing cached CRAN DJIA series: %s", djia_path)
  djia <- data.table::fread(djia_path, showProgress = FALSE)
  djia[, Date := as.Date(Date)]
}

fred_url <- paste0(
  "https://fred.stlouisfed.org/graph/fredgraph.csv",
  "?id=VXDCLS&cosd=1997-10-07&coed=2021-05-31"
)
if (refresh || !file.exists(vxd_path)) {
  log_message("Downloading VXDCLS from FRED")
  raw_fred <- tempfile(tmpdir = cache_dir, fileext = ".csv")
  utils::download.file(fred_url, raw_fred, mode = "wb", quiet = TRUE)
  vxd_source <- data.table::fread(raw_fred, na.strings = c(".", "NA", ""), showProgress = FALSE)
  unlink(raw_fred)
  if (!all(c("observation_date", "VXDCLS") %in% names(vxd_source))) {
    stop("Unexpected FRED VXDCLS schema.")
  }
  vxd <- vxd_source[, .(Date = as.Date(observation_date), VXD = as.numeric(VXDCLS))]
  vxd <- vxd[is.finite(VXD)]
  data.table::setorder(vxd, Date)
  ensure_directory(dirname(vxd_path))
  data.table::fwrite(vxd, vxd_path, na = "NA", quote = TRUE)
} else {
  log_message("Reusing cached FRED VXD series: %s", vxd_path)
  vxd <- data.table::fread(vxd_path, showProgress = FALSE)
  vxd[, Date := as.Date(Date)]
}

required_yahoo <- c(
  "^GSPC", "^NDX", "^IXIC", "SPY", "QQQ", "^DJI", "DIA", "^RUT", "^VIX", "^VXN"
)
if (!setequal(unique(yahoo$Ticker), required_yahoo)) stop("Yahoo cache has an unexpected ticker set.")
if (min(yahoo[Ticker == "^GSPC", Date]) > as.Date("1927-12-30")) {
  stop("Yahoo ^GSPC history no longer reaches the start required by the paper.")
}
if (min(djia$Date) > as.Date("1927-12-30") || max(djia$Date) < as.Date("2021-05-28")) {
  stop("Pinned CRAN DJIA history does not cover the required paper interval.")
}
if (min(vxd$Date) > as.Date("1997-10-07") || max(vxd$Date) < as.Date("2021-05-28")) {
  stop("FRED VXDCLS history does not cover the required paper interval.")
}

close_on <- function(ticker, date) {
  value <- yahoo[Ticker == ticker & Date == date, Close]
  if (length(value) != 1L || !is.finite(value)) stop(sprintf("Missing Yahoo close for %s on %s", ticker, date))
  value
}
supplement_date <- as.Date("2021-01-13")
djia_close <- djia[Date == supplement_date, DJI]
if (length(djia_close) != 1L || !is.finite(djia_close)) stop("Missing CRAN DJIA close on 2021-01-13.")
supplemental <- data.table::data.table(
  SecurityID = c("108105", "102480", "102456", "102434"),
  Ticker = c("SPX", "NDX", "DJX", "RUT"),
  Date = supplement_date,
  ClosePrice = c(
    close_on("^GSPC", supplement_date),
    close_on("^NDX", supplement_date),
    round(djia_close / 100, 2),
    close_on("^RUT", supplement_date)
  ),
  Source = c("Yahoo Finance", "Yahoo Finance", "CRAN stevedata 1.8.0", "Yahoo Finance")
)
ensure_directory(dirname(supplemental_path))
data.table::fwrite(supplemental, supplemental_path, na = "NA", quote = TRUE)

series_range <- function(frame, date_column = "Date") {
  dates <- as.Date(frame[[date_column]])
  list(rows = nrow(frame), first_date = as.character(min(dates)), last_date = as.character(max(dates)))
}
report <- list(
  retrieved_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  cache_policy = if (refresh) "refreshed" else "reuse-valid-cache-or-download",
  yahoo = list(
    endpoint = "https://query1.finance.yahoo.com/v8/finance/chart/",
    requested_start = as.character(start_date),
    requested_end_exclusive = as.character(end_date),
    tickers = yahoo_tickers,
    ranges = lapply(split(yahoo, yahoo$Ticker), series_range),
    output = file_fingerprint(yahoo_path)
  ),
  djia = list(
    source = "CRAN package stevedata",
    package_version = stevedata_version,
    source_url = if (is.na(stevedata_url_used)) stevedata_urls[[1L]] else stevedata_url_used,
    archive_sha256_expected = stevedata_sha256,
    archive_sha256_observed = actual_stevedata_sha256,
    output_range = series_range(djia),
    output = file_fingerprint(djia_path)
  ),
  vxd = list(
    source = "Federal Reserve Bank of St. Louis FRED series VXDCLS; originating source Cboe",
    source_url = fred_url,
    output_range = series_range(vxd),
    output = file_fingerprint(vxd_path)
  ),
  supplemental_closes = list(
    transformation = "Yahoo closes; DJIA divided by 100 and rounded to two decimals for DJX",
    output = file_fingerprint(supplemental_path)
  )
)
write_json(report, report_path)
log_message("Auxiliary source acquisition complete. Report: %s", report_path)
