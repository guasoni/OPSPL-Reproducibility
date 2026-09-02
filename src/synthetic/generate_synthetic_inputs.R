args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate src/synthetic/generate_synthetic_inputs.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)
require_packages(c("data.table", "digest", "jsonlite"))

synthetic_root <- file.path(root, "work", "synthetic")
normalized_synthetic_root <- normalizePath(synthetic_root, winslash = "/", mustWork = FALSE)
expected_synthetic_root <- paste0(normalizePath(root, winslash = "/"), "/work/synthetic")
if (!identical(normalized_synthetic_root, expected_synthetic_root)) {
  stop("Refusing to replace an unexpected synthetic-work directory.")
}
if (dir.exists(synthetic_root)) unlink(synthetic_root, recursive = TRUE, force = TRUE)

private_dir <- file.path(synthetic_root, "inputs", "optionmetrics")
public_dir <- file.path(synthetic_root, "inputs", "public")
output_root <- file.path(synthetic_root, "outputs")
cache_root <- file.path(synthetic_root, "cache")
ensure_directory(private_dir)
ensure_directory(public_dir)
ensure_directory(output_root)
ensure_directory(cache_root)

security_to_ticker <- c(
  `102434` = "RUT",
  `102456` = "DJX",
  `102480` = "NDX",
  `108105` = "SPX"
)
base_levels <- c(RUT = 1500, DJX = 280, NDX = 8000, SPX = 3000)
phase <- c(RUT = 0.2, DJX = 0.8, NDX = 1.4, SPX = 2.0)
sigma_by_ticker <- c(RUT = 0.22, DJX = 0.18, NDX = 0.24, SPX = 0.20)

third_saturday <- function(month_start) {
  first_weekday <- as.POSIXlt(month_start)$wday
  first_saturday <- month_start + ((6L - first_weekday + 7L) %% 7L)
  first_saturday + 14L
}

next_weekday <- function(date) {
  candidate <- as.Date(date) + 1L
  while (as.POSIXlt(candidate)$wday %in% c(0L, 6L)) candidate <- candidate + 1L
  candidate
}

bs_price <- function(S, K, T, r, sigma, type) {
  d1 <- (log(S / K) + (r + sigma^2 / 2) * T) / (sigma * sqrt(T))
  d2 <- d1 - sigma * sqrt(T)
  if (type == "C") {
    S * stats::pnorm(d1) - K * exp(-r * T) * stats::pnorm(d2)
  } else {
    K * exp(-r * T) * stats::pnorm(-d2) - S * stats::pnorm(-d1)
  }
}

option_greeks <- function(S, K, T, r, sigma, type) {
  d1 <- (log(S / K) + (r + sigma^2 / 2) * T) / (sigma * sqrt(T))
  delta <- if (type == "C") stats::pnorm(d1) else stats::pnorm(d1) - 1
  c(
    Delta = delta,
    Gamma = stats::dnorm(d1) / (S * sigma * sqrt(T)),
    Vega = S * stats::dnorm(d1) * sqrt(T) / 100,
    Theta = -S * stats::dnorm(d1) * sigma / (2 * sqrt(T)) / 365
  )
}

month_starts <- seq(as.Date("2019-12-01"), as.Date("2020-12-01"), by = "month")
expiration_saturdays <- as.Date(vapply(month_starts, third_saturday, as.Date("1970-01-01")), origin = "1970-01-01")
expiration_fridays <- expiration_saturdays - 1L
quote_dates <- as.Date(rep(NA_real_, length(month_starts)), origin = "1970-01-01")
quote_dates[[1L]] <- as.Date("2019-11-18")
for (i in 2:length(quote_dates)) quote_dates[[i]] <- next_weekday(expiration_fridays[[i - 1L]])

level_table <- data.table::CJ(
  SecurityID = as.integer(names(security_to_ticker)),
  period = seq_along(month_starts)
)
level_table[, Ticker := unname(security_to_ticker[as.character(SecurityID)])]
level_table[, Date := quote_dates[period]]
level_table[, Expiration := expiration_fridays[period]]
level_table[, PriceDate := base_levels[Ticker] * exp(0.004 * (period - 1) + 0.012 * sin(0.7 * period + phase[Ticker]))]
level_table[, realized_return := 0.008 + 0.018 * sin(0.9 * period + phase[Ticker])]
level_table[, PriceExp := PriceDate * (1 + realized_return)]

option_columns <- c(
  "SecurityID", "Date", "Symbol", "SymbolFlag", "Strike", "Expiration",
  "CallPut", "BestBid", "BestOffer", "LastTradeDate", "Volume",
  "OpenInterest", "SpecialSettlement", "ImpliedVolatility", "Delta",
  "Gamma", "Vega", "Theta", "OptionID", "AdjustmentFactor",
  "AMSettlement", "ContractSize", "ExpiryIndicator"
)

option_rows <- list()
option_id <- 700000000L
append_option <- function(
  security_id, ticker, quote_date, expiration_saturday, strike, type,
  spot, sigma, rate_pct, volume, symbol
) {
  expiration_friday <- expiration_saturday - 1L
  days <- as.numeric(expiration_friday - quote_date)
  T <- days / 360
  mid <- bs_price(spot, strike, T, rate_pct / 100, sigma, type)
  half_spread <- min(0.02, 0.05 * mid)
  greeks <- option_greeks(spot, strike, T, rate_pct / 100, sigma, type)
  option_id <<- option_id + 1L
  option_rows[[length(option_rows) + 1L]] <<- data.table::data.table(
    SecurityID = security_id,
    Date = format(quote_date, "%Y-%m-%d"),
    Symbol = symbol,
    SymbolFlag = 0L,
    Strike = as.integer(round(strike * 1000)),
    Expiration = format(expiration_saturday, "%Y-%m-%d"),
    CallPut = type,
    BestBid = mid - half_spread,
    BestOffer = mid + half_spread,
    LastTradeDate = format(expiration_friday, "%Y-%m-%d"),
    Volume = as.integer(volume),
    OpenInterest = as.integer(500 + option_id %% 97L),
    SpecialSettlement = 0L,
    ImpliedVolatility = sigma,
    Delta = unname(greeks[["Delta"]]),
    Gamma = unname(greeks[["Gamma"]]),
    Vega = unname(greeks[["Vega"]]),
    Theta = unname(greeks[["Theta"]]),
    OptionID = option_id,
    AdjustmentFactor = 1,
    AMSettlement = 1L,
    ContractSize = 100L,
    ExpiryIndicator = "M"
  )
}

strike_multipliers <- c(0.90, 0.95, 1.00, 1.05, 1.10)
for (row_index in seq_len(nrow(level_table))) {
  row <- level_table[row_index]
  i <- row$period[[1L]]
  ticker <- row$Ticker[[1L]]
  selected_expiry <- expiration_saturdays[[i]]
  alternative_expiry <- selected_expiry + 7L
  rate_pct <- 1.20 + 0.03 * i
  strikes <- round(row$PriceDate[[1L]] * strike_multipliers, 2)
  for (strike_index in seq_along(strikes)) {
    for (type in c("C", "P")) {
      append_option(
        row$SecurityID[[1L]], ticker, row$Date[[1L]], selected_expiry,
        strikes[[strike_index]], type, row$PriceDate[[1L]], sigma_by_ticker[[ticker]],
        rate_pct, 100L + 5L * strike_index + if (type == "C") 1L else 2L,
        sprintf("%s_SYN_M%02d_%s_%02d", ticker, i, type, strike_index)
      )
    }
  }
  for (type in c("C", "P")) {
    append_option(
      row$SecurityID[[1L]], ticker, row$Date[[1L]], alternative_expiry,
      strikes[[3L]], type, row$PriceDate[[1L]], sigma_by_ticker[[ticker]],
      rate_pct, 10L, sprintf("%s_SYN_ALT_M%02d_%s", ticker, i, type)
    )
  }
  if (ticker == "SPX") {
    for (type in c("C", "P")) {
      append_option(
        row$SecurityID[[1L]], ticker, row$Date[[1L]], alternative_expiry,
        strikes[[3L]], type, row$PriceDate[[1L]], sigma_by_ticker[[ticker]],
        rate_pct, 100000L, sprintf("SPXW_SYN_M%02d_%s", i, type)
      )
    }
  }
}
options <- data.table::rbindlist(option_rows, use.names = TRUE)
data.table::setcolorder(options, option_columns)

security_rows <- list()
for (row_index in seq_len(nrow(level_table))) {
  row <- level_table[row_index]
  for (which_date in c("Date", "Expiration")) {
    date <- row[[which_date]][[1L]]
    close <- if (which_date == "Date") row$PriceDate[[1L]] else row$PriceExp[[1L]]
    security_rows[[length(security_rows) + 1L]] <- data.table::data.table(
      SecurityID = row$SecurityID[[1L]],
      Date = format(date, "%Y-%m-%d"),
      BidLow = close * 0.999,
      AskHigh = close * 1.001,
      ClosePrice = close,
      Volume = 1000000L + 1000L * row$period[[1L]],
      TotalReturn = close,
      AdjustmentFactor = 1,
      OpenPrice = close * 0.998,
      SharesOutstanding = 1000000000,
      AdjustmentFactor2 = 1
    )
  }
}
security_prices <- unique(data.table::rbindlist(security_rows), by = c("SecurityID", "Date"))
data.table::setorder(security_prices, SecurityID, Date)

curve_rows <- list()
for (i in seq_along(quote_dates)) {
  exact_days <- as.integer(expiration_fridays[[i]] - quote_dates[[i]])
  maturities <- unique(c(7L, exact_days, 60L))
  for (days in maturities) {
    curve_rows[[length(curve_rows) + 1L]] <- data.table::data.table(
      Date = format(quote_dates[[i]], "%Y-%m-%d"),
      Days = days,
      Rate = 1.20 + 0.03 * i + 0.001 * (days - exact_days)
    )
  }
}
zero_curve <- data.table::rbindlist(curve_rows)
data.table::setorder(zero_curve, Date, Days)

option_path <- file.path(private_dir, "option_price_view_indices_2020.csv")
security_path <- file.path(private_dir, "security_price_indices_through_2021_01.csv")
curve_path <- file.path(private_dir, "zero_curve_through_2020.csv")
data.table::fwrite(options, option_path, na = "")
data.table::fwrite(security_prices, security_path, na = "")
data.table::fwrite(zero_curve, curve_path, na = "")

yahoo_rows <- list()
yahoo_mapping <- list(
  SPX = c(index = "^GSPC", etf = "SPY"),
  NDX = c(index = "^NDX", etf = "QQQ"),
  DJX = c(index = "^DJI", etf = "DIA")
)
index_multiplier <- c(SPX = 1, NDX = 1, DJX = 100)
etf_divisor <- c(SPX = 10, NDX = 20, DJX = 1)
for (ticker in names(yahoo_mapping)) {
  ticker_levels <- level_table[Ticker == ticker & period >= 2L]
  for (row_index in seq_len(nrow(ticker_levels))) {
    row <- ticker_levels[row_index]
    observations <- list(
      list(date = row$Date[[1L]], index = row$PriceDate[[1L]]),
      list(date = row$Expiration[[1L]], index = row$PriceExp[[1L]])
    )
    for (observation in observations) {
      index_value <- observation$index * index_multiplier[[ticker]]
      etf_value <- observation$index / etf_divisor[[ticker]]
      for (pair in list(
        c(ticker = yahoo_mapping[[ticker]][["index"]], value = index_value),
        c(ticker = yahoo_mapping[[ticker]][["etf"]], value = etf_value)
      )) {
        value <- as.numeric(pair[["value"]])
        yahoo_rows[[length(yahoo_rows) + 1L]] <- data.table::data.table(
          Ticker = pair[["ticker"]],
          Date = format(observation$date, "%Y-%m-%d"),
          Open = value,
          High = value,
          Low = value,
          Close = value,
          Adjusted = value,
          Volume = 1000000
        )
      }
    }
  }
}

extra_tickers <- c("^IXIC", "^VIX", "^VXN")
all_yahoo_dates <- sort(unique(c(quote_dates[-1L], expiration_fridays[-1L])))
for (ticker_index in seq_along(extra_tickers)) {
  ticker <- extra_tickers[[ticker_index]]
  for (i in seq_along(all_yahoo_dates)) {
    value <- if (ticker == "^IXIC") 9000 + 15 * i else 18 + ticker_index + 0.05 * sin(i)
    yahoo_rows[[length(yahoo_rows) + 1L]] <- data.table::data.table(
      Ticker = ticker,
      Date = format(all_yahoo_dates[[i]], "%Y-%m-%d"),
      Open = value,
      High = value,
      Low = value,
      Close = value,
      Adjusted = value,
      Volume = 1000000
    )
  }
}
yahoo <- unique(data.table::rbindlist(yahoo_rows), by = c("Ticker", "Date"))
data.table::setorder(yahoo, Ticker, Date)
yahoo_path <- file.path(public_dir, "synthetic_yahoo_daily.csv")
data.table::fwrite(yahoo, yahoo_path)

forecast_dates <- quote_dates[-1L]
forecasts <- data.table::data.table(
  Date = format(forecast_dates, "%Y-%m-%d"),
  BizDays = 20L + (seq_along(forecast_dates) %% 2L),
  SPX_Vol_Pred = 18 + 1.5 * sin(seq_along(forecast_dates) / 2),
  NDX_Vol_Pred = 23 + 2.0 * cos(seq_along(forecast_dates) / 3),
  DJX_Vol_Pred = 17 + 1.2 * sin(seq_along(forecast_dates) / 4)
)
forecast_path <- file.path(public_dir, "synthetic_volatility_forecasts.csv")
data.table::fwrite(forecasts, forecast_path)

history_dates <- seq(as.Date("2014-01-31"), as.Date("2020-12-31"), by = "month")
history_index <- seq_along(history_dates)
returns <- data.table::data.table(
  Date = format(history_dates, "%Y-%m-%d"),
  SPXReturn = 0.006 + 0.035 * sin(0.71 * history_index) + 0.012 * cos(0.19 * history_index),
  NDXReturn = 0.009 + 0.050 * sin(0.63 * history_index + 0.4) + 0.016 * cos(0.23 * history_index),
  DJXReturn = 0.005 + 0.030 * sin(0.77 * history_index + 0.8) + 0.010 * cos(0.17 * history_index),
  Days_between = c(31L, as.integer(diff(history_dates)))
)
returns_path <- file.path(public_dir, "synthetic_index_return_history.csv")
data.table::fwrite(returns, returns_path)

config <- list(
  data_mode = "synthetic",
  option_prices = file.path("work", "synthetic", "inputs", "optionmetrics", basename(option_path)),
  security_prices = file.path("work", "synthetic", "inputs", "optionmetrics", basename(security_path)),
  zero_curve = file.path("work", "synthetic", "inputs", "optionmetrics", basename(curve_path)),
  supplemental_closes = NULL,
  public_yahoo_daily = file.path("work", "synthetic", "inputs", "public", basename(yahoo_path)),
  public_volatility_forecasts = file.path("work", "synthetic", "inputs", "public", basename(forecast_path)),
  public_index_returns = file.path("work", "synthetic", "inputs", "public", basename(returns_path)),
  output_root = file.path("work", "synthetic", "outputs"),
  work_root = file.path("work", "synthetic", "cache"),
  workers = 1L,
  chunk_lines = 1000L,
  reuse_step1_selection = FALSE
)
config_path <- file.path(synthetic_root, "config.R")
writeLines(c("config <-", capture.output(dput(config))), config_path, useBytes = TRUE)

input_paths <- c(option_path, security_path, curve_path, yahoo_path, forecast_path, returns_path)
manifest <- list(
  purpose = paste(
    "Deterministic, non-empirical integration fixture.",
    "It is not evidence for, and cannot reproduce, the paper's empirical estimates."
  ),
  generator = "src/synthetic/generate_synthetic_inputs.R",
  usable_monthly_periods = 12L,
  raw_expiration_months = 13L,
  security_ids = as.integer(names(security_to_ticker)),
  selected_strikes_per_type = length(strike_multipliers),
  expected_selected_pairs = length(security_to_ticker) * length(month_starts),
  expected_step1_rows_per_ticker = 12L * length(strike_multipliers) * 2L,
  expected_spxw_rows_excluded = 2L * length(month_starts),
  input_rows = as.list(stats::setNames(
    c(nrow(options), nrow(security_prices), nrow(zero_curve), nrow(yahoo), nrow(forecasts), nrow(returns)),
    basename(input_paths)
  )),
  input_sha256 = as.list(stats::setNames(vapply(input_paths, sha256_file, character(1L)), basename(input_paths)))
)
write_json(manifest, file.path(synthetic_root, "manifest.json"))

log_message("Generated deterministic synthetic inputs under %s", synthetic_root)
log_message("Synthetic data are non-empirical and must not be used to assess the paper's findings.")
