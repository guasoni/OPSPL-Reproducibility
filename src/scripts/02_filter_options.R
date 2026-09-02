args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate src/scripts/02_filter_options.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)
require_packages(c("data.table", "jsonlite"))

config <- read_config(root, args)
yahoo_path <- resolve_from_root(root, config$public_yahoo_daily)
if (is.null(yahoo_path)) yahoo_path <- file.path(root, "work", "auxiliary", "yahoo_daily.csv")
assert_file(yahoo_path, "Downloaded Yahoo daily series")

output_root <- pipeline_output_root(root, config)
input_dir <- file.path(output_root, "step1")
output_dir <- file.path(output_root, "step2")
ensure_directory(output_dir)

yahoo <- data.table::fread(yahoo_path, showProgress = FALSE)
yahoo[, Date := normalize_iso_date(Date)]
yahoo[, key__ := paste(Ticker, Date, sep = "|")]
close_lookup <- stats::setNames(yahoo$Close, yahoo$key__)
adjusted_lookup <- stats::setNames(yahoo$Adjusted, yahoo$key__)

index_ticker <- c(SPX = "^GSPC", NDX = "^NDX", DJX = "^DJI")
etf_ticker <- c(SPX = "SPY", NDX = "QQQ", DJX = "DIA")
index_scale <- c(SPX = 1, NDX = 1, DJX = 100)
missing_dividend_to_zero <- c(SPX = FALSE, NDX = TRUE, DJX = TRUE)
maximum_deletions <- c(SPX = 2L, NDX = 8L, DJX = 1L)

lookup_series <- function(lookup, ticker, dates) {
  unname(lookup[paste(ticker, dates, sep = "|")])
}

build_dividend_adjustments <- function(options, ticker) {
  calendar <- unique(options[, .(Date, Expiration)])
  data.table::setorder(calendar, Date)
  index_dates <- lookup_series(adjusted_lookup, index_ticker[[ticker]], calendar$Date)
  index_expirations <- lookup_series(adjusted_lookup, index_ticker[[ticker]], calendar$Expiration)
  if (ticker == "SPX") {
    index_dates <- lookup_series(close_lookup, index_ticker[[ticker]], calendar$Date)
    index_expirations <- lookup_series(close_lookup, index_ticker[[ticker]], calendar$Expiration)
  }
  index_dates <- index_dates / index_scale[[ticker]]
  index_expirations <- index_expirations / index_scale[[ticker]]

  etf_dates <- lookup_series(adjusted_lookup, etf_ticker[[ticker]], calendar$Date)
  etf_expirations <- lookup_series(adjusted_lookup, etf_ticker[[ticker]], calendar$Expiration)
  index_return <- (index_expirations - index_dates) / index_dates
  etf_return <- (etf_expirations - etf_dates) / etf_dates
  dividends <- (etf_return - index_return) * index_dates
  if (missing_dividend_to_zero[[ticker]]) dividends[is.na(dividends)] <- 0

  calendar[, `:=`(
    IndexDate = index_dates,
    IndexExpiration = index_expirations,
    ETFDateAdjusted = etf_dates,
    ETFExpirationAdjusted = etf_expirations,
    IndexReturn = index_return,
    ETFReturn = etf_return,
    Dividends = dividends
  )]
  calendar
}

bound_table <- function(pairs) {
  if (!nrow(pairs)) {
    return(data.table::data.table(
      Date = character(), Low = numeric(), Up = numeric(), PriceDate = numeric(),
      Low_below_Up = logical(), Price_inside_bound = logical(), New_Price = numeric()
    ))
  }
  result <- pairs[, .(
    Low = max(PutCallIndexLow),
    Up = min(PutCallIndexUp),
    PriceDate = mean(PriceDate)
  ), by = Date]
  result[, Low_below_Up := Low < Up]
  result[, Price_inside_bound := PriceDate > Low & PriceDate < Up]
  result[, New_Price := ifelse(
    !Low_below_Up,
    NA_real_,
    ifelse(!Price_inside_bound, (Low + Up) / 2, PriceDate)
  )]
  result
}

filter_one_index <- function(ticker) {
  input_path <- file.path(input_dir, paste0(ticker, "final.csv"))
  assert_file(input_path, paste(ticker, "Step 1 file"))
  options_all <- data.table::fread(input_path, showProgress = FALSE)
  if (names(options_all)[[1L]] %in% c("", "V1")) data.table::setnames(options_all, 1L, "X")
  options_all[, Date := normalize_iso_date(Date)]
  options_all[, Expiration := normalize_iso_date(Expiration)]
  options_all[, source_order__ := .I]

  dividends <- build_dividend_adjustments(options_all, ticker)
  dividend_lookup <- stats::setNames(dividends$Dividends, dividends$Date)
  options <- options_all[BestBid > 0]

  puts <- options[CallPut == "P", .(
    Date, Strike,
    BestBid.Put = BestBid,
    BestOffer.Put = BestOffer,
    PriceDate.Put = PriceDate,
    Rate.Put = Rate,
    Days.Put = Days
  )]
  calls <- options[CallPut == "C", .(
    Date, Strike,
    BestBid.Call = BestBid,
    BestOffer.Call = BestOffer
  )]
  pairs <- merge(puts, calls, by = c("Date", "Strike"), sort = FALSE, allow.cartesian = TRUE)
  pairs[, Dividends := unname(dividend_lookup[Date])]
  pairs[, PutCallIndexLow := Strike * exp(-Rate.Put * Days.Put / 360 / 100) + BestBid.Call - BestOffer.Put + Dividends]
  pairs[, PutCallIndexUp := Strike * exp(-Rate.Put * Days.Put / 360 / 100) + BestOffer.Call - BestBid.Put + Dividends]
  pairs[, PriceDate := PriceDate.Put]
  valid_pairs <- pairs[PutCallIndexLow < PutCallIndexUp]

  initial_bounds <- bound_table(valid_pairs)
  resolved <- initial_bounds[!is.na(New_Price), .(Date, Implied_Price = New_Price)]
  unresolved_dates <- initial_bounds[is.na(New_Price), Date]
  working <- valid_pairs[Date %in% unresolved_dates]
  deleted <- data.table::data.table(Date = character(), Strike = numeric(), deletion_round = integer())

  max_round <- maximum_deletions[[ticker]]
  if (length(unresolved_dates)) {
    for (round in seq_len(max_round)) {
      if (!nrow(working)) break
      working[, `:=`(
        maximum_low__ = max(PutCallIndexLow),
        minimum_up__ = min(PutCallIndexUp)
      ), by = Date]
      keep <- working$PutCallIndexLow != working$maximum_low__ & working$PutCallIndexUp != working$minimum_up__
      removed <- unique(working[!keep, .(Date, Strike)])
      if (nrow(removed)) {
        removed[, deletion_round := round]
        deleted <- data.table::rbindlist(list(deleted, removed), use.names = TRUE)
      }
      working <- working[keep]
      working[, c("maximum_low__", "minimum_up__") := NULL]
      bounds <- bound_table(working)
      if (ticker == "NDX" && round == max_round) {
        bounds[, New_Price := (Low + Up) / 2]
      }
      newly_resolved <- bounds[!is.na(New_Price), .(Date, Implied_Price = New_Price)]
      if (nrow(newly_resolved)) {
        resolved <- data.table::rbindlist(list(resolved, newly_resolved), use.names = TRUE)
      }
      unresolved_dates <- bounds[is.na(New_Price), Date]
      working <- working[Date %in% unresolved_dates]
      if (!length(unresolved_dates)) break
    }
  }

  resolved <- resolved[!duplicated(Date)]
  data.table::setorder(resolved, Date)
  implied_lookup <- stats::setNames(resolved$Implied_Price, resolved$Date)
  deleted_keys <- unique(paste(deleted$Date, deleted$Strike, sep = "|"))
  option_keys <- paste(options$Date, options$Strike, sep = "|")
  filtered <- options[!option_keys %in% deleted_keys]
  filtered[, Implied_Price := unname(implied_lookup[Date])]
  data.table::setorder(filtered, source_order__)
  filtered[, source_order__ := NULL]

  output_path <- file.path(output_dir, paste0(ticker, "_filtered1.csv"))
  write.csv(as.data.frame(filtered), output_path, row.names = TRUE, na = "NA", quote = TRUE, eol = "\n")
  data.table::fwrite(dividends, file.path(output_dir, paste0(ticker, "_dividend_adjustments.csv")), na = "NA")
  data.table::fwrite(unique(deleted), file.path(output_dir, paste0(ticker, "_parity_deletions.csv")), na = "NA")

  summary <- list(
    ticker = ticker,
    input_rows = nrow(options_all),
    positive_bid_rows = nrow(options),
    paired_rows = nrow(pairs),
    parity_deleted_date_strikes = nrow(unique(deleted[, .(Date, Strike)])),
    output_rows = nrow(filtered),
    dates = data.table::uniqueN(filtered$Date),
    unresolved_implied_prices = sum(is.na(filtered$Implied_Price)),
    missing_dividend_adjustments = sum(is.na(dividends$Dividends))
  )
  write_json(summary, file.path(output_dir, paste0(ticker, "_filter_report.json")))
  log_message("%s Step 2 complete: %d rows", ticker, nrow(filtered))
  summary
}

reports <- lapply(c("SPX", "NDX", "DJX"), filter_one_index)
names(reports) <- c("SPX", "NDX", "DJX")
write_json(reports, file.path(output_dir, "step2_report.json"))
log_message("Step 2 complete. Outputs: %s", output_dir)
