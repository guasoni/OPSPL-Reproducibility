args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate src/scripts/01_build_step1.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)
require_packages(c("data.table", "digest", "jsonlite"))

config <- read_config(root, args)
option_prices <- resolve_from_root(root, config$option_prices)
security_prices <- resolve_from_root(root, config$security_prices)
zero_curve <- resolve_from_root(root, config$zero_curve)
supplemental_closes <- resolve_from_root(root, config$supplemental_closes)
chunk_lines <- as.integer(if (is.null(config$chunk_lines)) 250000L else config$chunk_lines)
reuse_selection <- isTRUE(config$reuse_step1_selection) && !arg_flag(args, "--no-reuse-selection")

assert_file(option_prices, "OptionMetrics option-price extract")
assert_file(security_prices, "OptionMetrics security-price extract")
assert_file(zero_curve, "OptionMetrics zero-curve extract")
if (!is.null(supplemental_closes) && !file.exists(supplemental_closes)) supplemental_closes <- NULL
if (is.na(chunk_lines) || chunk_lines < 1000L) stop("config$chunk_lines must be at least 1000.")

work_dir <- file.path(pipeline_work_root(root, config), "step1")
output_dir <- file.path(pipeline_output_root(root, config), "step1")
ensure_directory(work_dir)
ensure_directory(output_dir)

security_to_ticker <- c(
  `102434` = "RUT",
  `102456` = "DJX",
  `102480` = "NDX",
  `108105` = "SPX"
)

raw_columns <- c(
  "SecurityID", "Date", "Symbol", "SymbolFlag", "Strike", "Expiration",
  "CallPut", "BestBid", "BestOffer", "LastTradeDate", "Volume",
  "OpenInterest", "SpecialSettlement", "ImpliedVolatility", "Delta",
  "Gamma", "Vega", "Theta", "OptionID", "AdjustmentFactor",
  "AMSettlement", "ContractSize", "ExpiryIndicator"
)

final_base_columns <- c(
  "SecurityID", "Date", "Strike", "Expiration", "CallPut", "BestBid",
  "BestOffer", "LastTradeDate", "Volume", "OpenInterest",
  "ImpliedVolatility", "Delta", "Gamma", "Vega", "Theta", "AMSettlement",
  "ContractSize", "ExpiryIndicator", "PriceExp", "PriceDate", "Days", "Rate",
  "Maturity", "Rate_simplex", "ProfitLossBuy", "ProfitLossSell", "IndexRet"
)

final_columns <- c(
  final_base_columns, "MidPrice", "ProfitLossBuyMid", "ProfitLossSellMid",
  "DateIndex"
)

adjust_saturday <- function(x) {
  dates <- as.Date(normalize_iso_date(x))
  weekday <- as.POSIXlt(dates)$wday
  dates <- dates - ifelse(!is.na(weekday) & weekday == 6L, 1, 0)
  format(dates, "%Y-%m-%d")
}

raw_cache_signature <- function(path) {
  info <- file.info(path)
  list(
    path = normalizePath(path, winslash = "/", mustWork = TRUE),
    bytes = unname(info$size),
    modified = as.numeric(info$mtime)
  )
}

stream_csv <- function(path, select = NULL, callback, expected_columns = NULL) {
  # Read bytes rather than asking the current locale to transcode a 9 GB file.
  # This accepts a UTF-8 BOM even when the reproducibility environment uses the
  # deterministic C locale.
  connection <- file(path, open = "rb")
  on.exit(close(connection), add = TRUE)
  header_line <- strip_utf8_bom(readLines(connection, n = 1L, warn = FALSE))
  if (length(header_line) != 1L) stop(sprintf("Empty CSV: %s", path))
  header <- names(data.table::fread(text = header_line, nrows = 0L, showProgress = FALSE))
  if (!is.null(expected_columns) && !identical(header, expected_columns)) {
    stop(
      sprintf(
        "Unexpected CSV schema in %s.\nExpected: %s\nObserved: %s",
        path,
        paste(expected_columns, collapse = ", "),
        paste(header, collapse = ", ")
      )
    )
  }
  chunk_number <- 0L
  total_rows <- 0
  repeat {
    lines <- readLines(connection, n = chunk_lines, warn = FALSE)
    if (!length(lines)) break
    chunk_number <- chunk_number + 1L
    input <- paste(c(header_line, lines), collapse = "\n")
    chunk <- data.table::fread(
      text = input,
      select = select,
      na.strings = c("", "NA", "NULL"),
      showProgress = FALSE
    )
    total_rows <- total_rows + nrow(chunk)
    callback(chunk, chunk_number, total_rows)
    rm(chunk, lines, input)
    if (chunk_number %% 10L == 0L) invisible(gc(FALSE))
  }
  invisible(list(chunks = chunk_number, rows = total_rows, columns = header))
}

selection_cache_path <- file.path(work_dir, "pass1_selection.rds")

build_selection <- function() {
  signature <- raw_cache_signature(option_prices)
  if (reuse_selection && file.exists(selection_cache_path)) {
    cached <- readRDS(selection_cache_path)
    if (identical(cached$raw_signature, signature)) {
      log_message("Reusing Step 1 selection cache: %s", selection_cache_path)
      return(cached)
    }
  }

  pair_environment <- new.env(hash = TRUE, parent = emptyenv())
  rows_by_security <- numeric()
  excluded_spxw_rows <- 0
  started <- Sys.time()

  update_pair <- function(key, volume, missing, dates) {
    if (exists(key, envir = pair_environment, inherits = FALSE)) {
      record <- get(key, envir = pair_environment, inherits = FALSE)
      record$volume <- record$volume + volume
      record$missing <- record$missing || missing
      record$dates <- union(record$dates, dates)
    } else {
      record <- list(volume = volume, missing = missing, dates = unique(dates))
    }
    assign(key, record, envir = pair_environment)
  }

  callback <- function(chunk, chunk_number, total_rows) {
    spxw <- grepl("SPXW", chunk$Symbol, fixed = TRUE)
    spxw[is.na(spxw)] <- FALSE
    excluded_spxw_rows <<- excluded_spxw_rows + sum(spxw)
    chunk <- chunk[!spxw]
    chunk[, SecurityID := trimws(as.character(SecurityID))]
    chunk[, Date := normalize_iso_date(Date)]
    chunk[, Expiration := adjust_saturday(Expiration)]

    counts <- table(chunk$SecurityID, useNA = "no")
    for (name in names(counts)) {
      existing <- rows_by_security[name]
      if (!length(existing) || is.na(existing)) existing <- 0
      rows_by_security[name] <<- existing + unname(counts[[name]])
    }

    chunk[, pair_key := paste(SecurityID, Expiration, sep = "|")]
    aggregates <- chunk[, .(
      chunk_volume = sum(as.numeric(Volume), na.rm = TRUE),
      chunk_missing = any(is.na(Volume)),
      dates = list(unique(Date[!is.na(Date)]))
    ), by = pair_key]

    for (i in seq_len(nrow(aggregates))) {
      update_pair(
        aggregates$pair_key[[i]],
        aggregates$chunk_volume[[i]],
        aggregates$chunk_missing[[i]],
        aggregates$dates[[i]]
      )
    }

    if (chunk_number == 1L || chunk_number %% 10L == 0L) {
      elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
      log_message(
        "Step 1 pass 1: chunks=%d, raw rows=%.0f, elapsed=%.1fs",
        chunk_number,
        total_rows,
        elapsed
      )
    }
  }

  stream_result <- stream_csv(
    option_prices,
    select = c("SecurityID", "Date", "Symbol", "Expiration", "Volume"),
    callback = callback,
    expected_columns = raw_columns
  )

  keys <- ls(pair_environment, all.names = TRUE)
  records <- lapply(keys, function(key) {
    value <- get(key, envir = pair_environment, inherits = FALSE)
    parts <- strsplit(key, "|", fixed = TRUE)[[1L]]
    data.table::data.table(
      pair_key = key,
      SecurityID = parts[[1L]],
      Expiration = parts[[2L]],
      TotalVolume = if (value$missing) NA_real_ else value$volume
    )
  })
  volume_table <- data.table::rbindlist(records)
  volume_table <- volume_table[Expiration < "2021-05-01"]
  volume_table[, month := substr(Expiration, 1L, 7L)]
  volume_table[, group_max := {
    valid <- TotalVolume[!is.na(TotalVolume)]
    if (length(valid)) max(valid) else NA_real_
  }, by = .(SecurityID, month)]
  selected <- volume_table[!is.na(TotalVolume) & TotalVolume == group_max]
  data.table::setorder(selected, SecurityID, Expiration)

  selected_keys <- selected$pair_key
  selected_dates <- unlist(
    lapply(selected_keys, function(key) get(key, envir = pair_environment, inherits = FALSE)$dates),
    use.names = FALSE
  )
  all_dates <- sort(unique(selected_dates[!is.na(selected_dates)]))
  selected_expirations <- sort(unique(selected$Expiration))
  trading_date_by_expiration <- stats::setNames(
    rep(NA_character_, length(selected_expirations)),
    selected_expirations
  )
  if (length(selected_expirations) > 1L) {
    for (i in 2:length(selected_expirations)) {
      candidates <- all_dates[all_dates > selected_expirations[[i - 1L]]]
      if (length(candidates)) trading_date_by_expiration[[i]] <- candidates[[1L]]
    }
  }

  tie_table <- selected[, .N, by = .(SecurityID, month)]
  result <- list(
    raw_signature = signature,
    raw_rows = stream_result$rows,
    excluded_spxw_rows = excluded_spxw_rows,
    rows_after_spxw_filter_by_security = as.list(rows_by_security[order(names(rows_by_security))]),
    selected_pairs = selected[, .(SecurityID, Expiration)],
    selected_pair_keys = selected_keys,
    selected_pair_count = nrow(selected),
    selected_expirations = selected_expirations,
    selected_expiration_count = length(selected_expirations),
    all_selected_pair_trading_date_count = length(all_dates),
    trading_date_by_expiration = trading_date_by_expiration,
    monthly_maximum_tie_groups = sum(tie_table$N > 1L),
    volume_pairs_with_missing_values = sum(is.na(volume_table$TotalVolume)),
    pass1_chunks = stream_result$chunks,
    pass1_seconds = as.numeric(difftime(Sys.time(), started, units = "secs"))
  )
  saveRDS(result, selection_cache_path)
  log_message(
    "Step 1 pass 1 complete: raw rows=%.0f, selected pairs=%d, selected expirations=%d",
    result$raw_rows,
    result$selected_pair_count,
    result$selected_expiration_count
  )
  result
}

extract_selected_rows <- function(selection) {
  retained <- list()
  retained_count <- 0L
  started <- Sys.time()
  selected_keys <- selection$selected_pair_keys
  trading_dates <- selection$trading_date_by_expiration

  callback <- function(chunk, chunk_number, total_rows) {
    spxw <- grepl("SPXW", as.character(chunk$Symbol), fixed = TRUE)
    spxw[is.na(spxw)] <- FALSE
    chunk <- chunk[!spxw]
    security_id <- trimws(as.character(chunk$SecurityID))
    expiration <- adjust_saturday(chunk$Expiration)
    quote_date <- normalize_iso_date(chunk$Date)
    pair_key <- paste(security_id, expiration, sep = "|")
    expected_date <- unname(trading_dates[expiration])
    keep <- pair_key %in% selected_keys & !is.na(expected_date) & quote_date == expected_date
    keep[is.na(keep)] <- FALSE
    if (any(keep)) {
      found <- chunk[keep]
      found[, SecurityID := as.integer(security_id[keep])]
      found[, Date := quote_date[keep]]
      found[, Expiration := expiration[keep]]
      found[, LastTradeDate := normalize_iso_date(LastTradeDate)]
      found[, ExpiryIndicator := {
        value <- trimws(as.character(ExpiryIndicator))
        value[value == ""] <- NA_character_
        value
      }]
      retained[[length(retained) + 1L]] <<- found
      retained_count <<- retained_count + nrow(found)
    }
    if (chunk_number == 1L || chunk_number %% 10L == 0L) {
      log_message(
        "Step 1 pass 2: chunks=%d, raw rows=%.0f, retained rows=%d, elapsed=%.1fs",
        chunk_number,
        total_rows,
        retained_count,
        as.numeric(difftime(Sys.time(), started, units = "secs"))
      )
    }
  }

  stream_csv(
    option_prices,
    select = NULL,
    callback = callback,
    expected_columns = raw_columns
  )
  if (!length(retained)) stop("No rows were retained from the OptionMetrics extract.")
  result <- data.table::rbindlist(retained, use.names = TRUE, fill = FALSE)
  log_message("Step 1 pass 2 complete: retained rows=%d", nrow(result))
  result
}

load_closing_prices <- function(path, supplemental = NULL) {
  closes <- data.table::fread(path, showProgress = FALSE)
  if (!"SecurityID" %in% names(closes)) data.table::setnames(closes, 1L, "SecurityID")
  required <- c("SecurityID", "Date", "ClosePrice")
  missing <- setdiff(required, names(closes))
  if (length(missing)) stop(sprintf("Security-price extract lacks: %s", paste(missing, collapse = ", ")))
  closes <- closes[, ..required]
  closes[, SecurityID := trimws(as.character(SecurityID))]
  closes[, Date := normalize_iso_date(Date)]
  closes[, ClosePrice := as.numeric(ClosePrice)]

  if (!is.null(supplemental)) {
    extra <- data.table::fread(supplemental, showProgress = FALSE)
    missing <- setdiff(required, names(extra))
    if (length(missing)) stop(sprintf("Supplemental closes lack: %s", paste(missing, collapse = ", ")))
    extra <- extra[, ..required]
    extra[, SecurityID := trimws(as.character(SecurityID))]
    extra[, Date := normalize_iso_date(Date)]
    extra[, ClosePrice := as.numeric(ClosePrice)]
    closes <- data.table::rbindlist(list(closes, extra), use.names = TRUE)
  }

  closes[, lookup_key := paste(SecurityID, Date, sep = "|")]
  conflicts <- closes[, .(values = data.table::uniqueN(ClosePrice, na.rm = FALSE)), by = lookup_key][values > 1L]
  if (nrow(conflicts)) stop("Conflicting closing prices occur for the same SecurityID and Date.")
  closes <- closes[!duplicated(lookup_key, fromLast = TRUE)]
  closes
}

attach_underlying_prices <- function(options, closes) {
  result <- data.table::copy(options)
  close_lookup <- stats::setNames(closes$ClosePrice, closes$lookup_key)
  security_id <- as.character(result$SecurityID)
  expiration <- as.Date(result$Expiration)
  price_exp <- rep(NA_real_, nrow(result))
  for (attempt in 0:2) {
    missing <- is.na(price_exp)
    keys <- paste(security_id, format(expiration, "%Y-%m-%d"), sep = "|")
    candidates <- unname(close_lookup[keys])
    price_exp[missing] <- candidates[missing]
    if (attempt < 2L) expiration[is.na(price_exp)] <- expiration[is.na(price_exp)] - 1
  }
  result[, Expiration := format(expiration, "%Y-%m-%d")]
  result[, PriceExp := price_exp]
  result[, PriceDate := unname(close_lookup[paste(security_id, Date, sep = "|")])]
  result
}

attach_rates <- function(options, path) {
  rates <- data.table::fread(path, showProgress = FALSE)
  if (!"Date" %in% names(rates)) data.table::setnames(rates, 1L, "Date")
  required <- c("Date", "Days", "Rate")
  missing <- setdiff(required, names(rates))
  if (length(missing)) stop(sprintf("Zero-curve extract lacks: %s", paste(missing, collapse = ", ")))
  rates <- rates[, ..required]
  rates[, Date := normalize_iso_date(Date)]
  rates[, Days := as.numeric(Days)]
  rates[, Rate := as.numeric(Rate)]
  rates[, Maturity := format(as.Date(Date) + Days, "%Y-%m-%d")]

  pairs <- unique(options[, .(Date, Expiration)])
  candidates <- merge(pairs, rates, by = "Date", all.x = TRUE, sort = FALSE, allow.cartesian = TRUE)
  candidates[, distance := abs(as.numeric(as.Date(Maturity) - as.Date(Expiration)))]
  candidates[, minimum := min(distance, na.rm = TRUE), by = Date]
  selected <- candidates[distance == minimum]
  selected[, c("distance", "minimum") := NULL]

  result <- data.table::copy(options)
  result[, source_order__ := .I]
  result <- merge(
    result,
    selected,
    by = c("Date", "Expiration"),
    all.x = TRUE,
    sort = FALSE,
    allow.cartesian = TRUE
  )
  data.table::setorder(result, source_order__)
  result[, source_order__ := NULL]
  result
}

calculate_option_returns <- function(options) {
  result <- data.table::copy(options)
  result[, c("Symbol", "SymbolFlag", "SpecialSettlement", "AdjustmentFactor", "OptionID") := NULL]
  result <- result[!is.na(ImpliedVolatility) & ImpliedVolatility != -99.99]
  result[, Strike := as.numeric(Strike) / 1000]
  result[, growth__ := exp(Rate / 100 * Days / 360)]
  result[, Rate_simplex := (growth__ - 1) / (Days / 360) * 100]
  result[, intrinsic__ := ifelse(
    CallPut == "C",
    pmax(0, PriceExp - Strike),
    pmax(0, Strike - PriceExp)
  )]
  result[, ProfitLossBuy := intrinsic__ - BestOffer * growth__]
  result[, ProfitLossSell := -intrinsic__ + BestBid * growth__]
  result[, IndexRet := (PriceExp - PriceDate * growth__) / PriceDate]
  result[, c("growth__", "intrinsic__") := NULL]
  data.table::setorderv(result, c("Date", "SecurityID", "CallPut", "Strike"), na.last = TRUE)
  result[, ..final_base_columns]
}

add_midprice_and_date_index <- function(options) {
  result <- data.table::copy(options)
  result[, source_row__ := .I]
  result[, maximum_bid__ := max(BestBid), by = .(Date, SecurityID, CallPut, Strike)]
  result <- result[BestBid == maximum_bid__]
  result[, maximum_bid__ := NULL]
  result[, MidPrice := (BestBid + BestOffer) / 2]
  result[, growth__ := exp(Rate / 100 * Days / 360)]
  result[, intrinsic__ := ifelse(
    CallPut == "C",
    pmax(0, PriceExp - Strike),
    pmax(0, Strike - PriceExp)
  )]
  result[, ProfitLossBuyMid := intrinsic__ - MidPrice * growth__]
  result[, ProfitLossSellMid := -intrinsic__ + MidPrice * growth__]
  result[, IndexRet := (PriceExp - PriceDate * growth__) / PriceDate]
  result[, c("growth__", "intrinsic__") := NULL]
  data.table::setorderv(result, c("Date", "SecurityID", "CallPut", "Strike"), na.last = TRUE)

  date_rows <- result[, .SD[which.max(source_row__)], by = Date, .SDcols = c("source_row__", "Days", "Rate", "Rate_simplex")]
  date_rows[, source_row__ := NULL]
  data.table::setorder(date_rows, Date)
  date_rows[, DateIndex := .I]
  date_lookup <- stats::setNames(date_rows$DateIndex, date_rows$Date)
  result[, DateIndex := unname(date_lookup[Date])]
  result[, source_row__ := NULL]
  result[, ..final_columns]
}

write_r_csv <- function(frame, path) {
  ensure_directory(dirname(path))
  write.csv(
    as.data.frame(frame),
    file = path,
    row.names = TRUE,
    na = "NA",
    quote = TRUE,
    eol = "\n"
  )
}

selection <- build_selection()
selected_options <- extract_selected_rows(selection)
closes <- load_closing_prices(security_prices, supplemental_closes)
prepared <- attach_underlying_prices(selected_options, closes)
prepared <- attach_rates(prepared, zero_curve)
optfinal <- calculate_option_returns(prepared)
final <- add_midprice_and_date_index(optfinal)

write_r_csv(optfinal, file.path(output_dir, "optfinal.csv"))
write_r_csv(final, file.path(output_dir, "optfinal3.csv"))

output_rows <- list(
  optfinal.csv = nrow(optfinal),
  optfinal3.csv = nrow(final)
)
for (security_id in names(security_to_ticker)) {
  ticker <- unname(security_to_ticker[[security_id]])
  subset <- final[as.character(SecurityID) == security_id]
  data.table::setorder(subset, Date)
  filename <- paste0(ticker, "final.csv")
  write_r_csv(subset, file.path(output_dir, filename))
  output_rows[[filename]] <- nrow(subset)
}

missing_values <- as.list(vapply(
  c("PriceExp", "PriceDate", "Days", "Rate", "Maturity"),
  function(column) sum(is.na(final[[column]])),
  FUN.VALUE = integer(1L)
))

report <- list(
  data_mode = if (is.null(config$data_mode)) "unspecified" else config$data_mode,
  generated_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  option_prices = file_fingerprint(option_prices),
  security_prices = file_fingerprint(security_prices),
  zero_curve = file_fingerprint(zero_curve),
  supplemental_closes = if (is.null(supplemental_closes)) NULL else file_fingerprint(supplemental_closes),
  source_logic = c("loadinR.R", "Multiunderlying Preprocess.R"),
  spxw_excluded_from_monthly_step1 = TRUE,
  selection = list(
    raw_rows = selection$raw_rows,
    excluded_spxw_rows = selection$excluded_spxw_rows,
    selected_pair_count = selection$selected_pair_count,
    selected_expiration_count = selection$selected_expiration_count,
    monthly_maximum_tie_groups = selection$monthly_maximum_tie_groups
  ),
  output_rows = output_rows,
  missing_values = missing_values
)
write_json(report, file.path(output_dir, "step1_report.json"))
log_message("Step 1 complete. Outputs: %s", output_dir)
