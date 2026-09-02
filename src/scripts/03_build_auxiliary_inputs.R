args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate src/scripts/03_build_auxiliary_inputs.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)
require_packages(c("data.table", "jsonlite", "digest"))
config <- read_config(root, args)

path_from_config <- function(field, fallback) {
  value <- config[[field]]
  resolve_from_root(root, if (is.null(value)) fallback else value)
}

yahoo_path <- path_from_config("public_yahoo_daily", "work/auxiliary/yahoo_daily.csv")
djia_path <- path_from_config("public_djia_daily", "work/auxiliary/djia_daily.csv")
vxd_path <- path_from_config("public_vxd_daily", "work/auxiliary/vxd_daily.csv")
oxford_path <- path_from_config(
  "public_oxford_man_realized",
  "data/public/oxford_man_realized_5min.csv"
)
forecast_path <- path_from_config(
  "public_volatility_forecasts",
  "work/auxiliary/paper_volatility_forecasts.csv"
)
returns_path <- path_from_config(
  "public_index_returns",
  "work/auxiliary/paper_index_return_history.csv"
)
report_path <- path_from_config(
  "auxiliary_build_report",
  "work/auxiliary/build_report.json"
)

for (item in list(
  c(yahoo_path, "Downloaded Yahoo series"),
  c(djia_path, "Downloaded CRAN DJIA series"),
  c(vxd_path, "Downloaded FRED VXD series"),
  c(oxford_path, "Oxford-Man realized-volatility subset")
)) {
  assert_file(item[[1L]], item[[2L]])
}

output_root <- pipeline_output_root(root, config)
step2_dir <- file.path(output_root, "step2")

option_calendars <- lapply(c("SPX", "NDX", "DJX"), function(ticker) {
  path <- file.path(step2_dir, paste0(ticker, "_filtered1.csv"))
  assert_file(path, paste(ticker, "Step 2 file"))
  frame <- data.table::fread(path, select = c("Date", "Expiration"), showProgress = FALSE)
  frame[, `:=`(Date = as.Date(Date), Expiration = as.Date(Expiration))]
  unique(frame)
})
names(option_calendars) <- c("SPX", "NDX", "DJX")
calendar <- data.table::copy(option_calendars$SPX)
data.table::setorder(calendar, Date)
if (nrow(calendar) != 300L || anyDuplicated(calendar$Date)) {
  stop("The SPX Step 2 calendar must contain exactly 300 unique trading dates.")
}
for (ticker in c("NDX", "DJX")) {
  candidate <- data.table::copy(option_calendars[[ticker]])
  data.table::setorder(candidate, Date)
  common <- merge(
    calendar,
    candidate,
    by = "Date",
    all.y = TRUE,
    suffixes = c("_SPX", paste0("_", ticker)),
    sort = FALSE
  )
  if (anyNA(common$Expiration_SPX) ||
      any(common$Expiration_SPX != common[[paste0("Expiration_", ticker)]])) {
    stop(sprintf("%s option dates are not an expiration-matched subset of SPX dates.", ticker))
  }
  if (ticker == "NDX" && nrow(candidate) != nrow(calendar)) {
    stop("NDX and SPX must contain the same 300 option dates.")
  }
}
option_dates <- calendar$Date

yahoo <- data.table::fread(yahoo_path, showProgress = FALSE)
yahoo[, Date := as.Date(Date)]
data.table::setorder(yahoo, Ticker, Date)
get_yahoo <- function(ticker, value_name) {
  frame <- yahoo[Ticker == ticker, .(Date, value = as.numeric(Close))]
  if (!nrow(frame)) stop(sprintf("Yahoo series is missing: %s", ticker))
  data.table::setnames(frame, "value", value_name)
  frame
}

gspc <- get_yahoo("^GSPC", "SPX")
ndx <- get_yahoo("^NDX", "NDX")
ixic <- get_yahoo("^IXIC", "IXIC")
vix <- get_yahoo("^VIX", "VIX")
vxn <- get_yahoo("^VXN", "VXN")

djia <- data.table::fread(djia_path, showProgress = FALSE)
djia[, `:=`(Date = as.Date(Date), DJI = as.numeric(DJI))]
djia <- unique(djia[is.finite(DJI), .(Date, DJI)], by = "Date")
data.table::setorder(djia, Date)

vxd <- data.table::fread(vxd_path, showProgress = FALSE)
vxd[, `:=`(Date = as.Date(Date), VXD = as.numeric(VXD))]
vxd <- unique(vxd[is.finite(VXD), .(Date, VXD)], by = "Date")
data.table::setorder(vxd, Date)

realized <- data.table::fread(oxford_path, showProgress = FALSE)
required_realized <- c("Symbol", "Date", "rv5", "close_price")
if (!identical(names(realized), required_realized)) {
  stop(sprintf("Oxford-Man subset must have columns: %s", paste(required_realized, collapse = ", ")))
}
realized[, `:=`(Date = as.Date(Date), rv5 = as.numeric(rv5), close_price = as.numeric(close_price))]
if (!setequal(unique(realized$Symbol), c(".SPX", ".IXIC", ".DJI"))) {
  stop("Oxford-Man subset must contain exactly .SPX, .IXIC, and .DJI.")
}

lagged_returns <- function(frame, value_column, periods = 21L) {
  values <- frame[[value_column]]
  n <- length(values)
  if (n <= periods) stop(sprintf("Insufficient observations in %s.", value_column))
  data.table::data.table(
    Date = frame$Date[seq.int(periods + 1L, n)],
    Return = (values[seq.int(periods + 1L, n)] - values[seq_len(n - periods)]) /
      values[seq_len(n - periods)]
  )
}

spx_monthly <- lagged_returns(gspc, "SPX")
ndx_monthly_observed <- lagged_returns(ndx, "NDX")
ixic_monthly <- lagged_returns(ixic, "IXIC")
extension_length <- nrow(ixic_monthly) - nrow(ndx_monthly_observed)
if (extension_length <= 0L || 2L * extension_length > nrow(ixic_monthly)) {
  stop("Yahoo NDX/IXIC coverage no longer supports the paper's historical NDX extension.")
}
ndx_monthly <- data.table::rbindlist(
  list(ixic_monthly[seq_len(extension_length)], ndx_monthly_observed),
  use.names = TRUE
)
ndx_overlap <- ndx_monthly_observed[seq_len(extension_length), Return]
ixic_overlap <- ixic_monthly[extension_length + seq_len(extension_length), Return]
extension_model <- stats::lm(ndx_overlap ~ ixic_overlap)
ndx_monthly[seq_len(extension_length), Return :=
  stats::coef(extension_model)[[1L]] + stats::coef(extension_model)[[2L]] * Return]

dji_on_spx_calendar <- merge(gspc[, .(Date)], djia, by = "Date", all.x = TRUE, sort = FALSE)
data.table::setorder(dji_on_spx_calendar, Date)
if (any(!is.finite(dji_on_spx_calendar$DJI))) {
  missing_dates <- dji_on_spx_calendar[!is.finite(DJI), Date]
  stop(sprintf("DJIA source is missing %d S&P-calendar date(s), first: %s", length(missing_dates), missing_dates[[1L]]))
}
dji_on_spx_calendar[, DJX := DJI / 100]
djx_monthly <- lagged_returns(dji_on_spx_calendar, "DJX")

underprice <- data.table::data.table(
  Date = spx_monthly$Date,
  SPXReturn = spx_monthly$Return,
  NDXReturn = unname(stats::setNames(ndx_monthly$Return, ndx_monthly$Date)[as.character(spx_monthly$Date)]),
  DJXReturn = djx_monthly$Return,
  Days_between = as.numeric(
    gspc$Date[seq.int(22L, nrow(gspc))] - gspc$Date[seq_len(nrow(gspc) - 21L)]
  )
)
underprice[.N, Days_between := 30]
if (anyNA(underprice[, .(SPXReturn, DJXReturn, Days_between)])) {
  stop("Generated SPX/DJX return history contains missing values.")
}

daily_return <- function(frame, value_column, denominator = c("previous", "current")) {
  denominator <- match.arg(denominator)
  values <- frame[[value_column]]
  result <- if (denominator == "previous") {
    values / data.table::shift(values) - 1
  } else {
    c(0, diff(values)) / values
  }
  data.table::data.table(Date = frame$Date[-1L], daily_return = result[-1L])
}

spx_daily <- daily_return(gspc, "SPX", "previous")
ndx_daily <- daily_return(ndx, "NDX", "previous")
djx_daily <- daily_return(dji_on_spx_calendar, "DJX", "current")

pre_schedule <- djx_daily[
  Date >= as.Date("1989-12-28") & Date < as.Date("1996-01-22"),
  Date
]
schedule_dates <- c(pre_schedule[seq.int(1L, length(pre_schedule), by = 21L)], option_dates)
if (anyDuplicated(schedule_dates) || is.unsorted(schedule_dates)) {
  stop("The historical and option-date volatility schedule is not strictly increasing.")
}

realized_for <- function(symbol) {
  realized[
    Symbol == symbol & Date >= as.Date("1989-12-28") & Date < as.Date("2020-12-21"),
    .(Date, rv5 = sqrt(rv5 * 252) * 100)
  ]
}

assign_periods <- function(frame) {
  result <- data.table::copy(frame[Date >= as.Date("1989-12-28")])
  ids <- findInterval(result$Date, schedule_dates)
  ids[ids >= length(schedule_dates)] <- 0L
  result[, ID := ids]
  result
}

build_realized_blocks <- function(daily, realized_symbol) {
  joined <- merge(
    assign_periods(daily),
    realized_for(realized_symbol),
    by = "Date",
    all.x = TRUE,
    sort = TRUE
  )
  monthly <- joined[, .(hmvol = stats::sd(daily_return) * sqrt(252) * 100), by = ID][ID != 0L]
  data.table::setorder(monthly, ID)
  monthly[, fmvol := data.table::shift(hmvol, type = "lead")]
  high_frequency <- joined[is.finite(rv5), .(
    hvol = mean(rv5, na.rm = TRUE),
    hf1 = rv5[.N]
  ), by = ID][ID != 0L]
  data.table::setorder(high_frequency, ID)
  high_frequency[, fvol := data.table::shift(hvol, type = "lead")]
  merge(monthly, high_frequency, by = "ID", all.x = TRUE, sort = TRUE)
}

spx_blocks <- build_realized_blocks(spx_daily, ".SPX")
ndx_blocks <- build_realized_blocks(ndx_daily, ".IXIC")
djx_blocks <- build_realized_blocks(djx_daily, ".DJI")

fill_from_vix <- function(target, target_column) {
  joined <- merge(vix, target, by = "Date", all.x = TRUE, sort = TRUE)
  target_dates <- target[is.finite(get(target_column)), Date]
  if (length(target_dates) < 63L) stop(sprintf("%s has fewer than 63 finite observations.", target_column))
  train_end <- target_dates[[63L]]
  training <- joined[Date >= target_dates[[1L]] & Date <= train_end]
  model <- stats::lm(stats::as.formula(paste(target_column, "~ VIX")), data = training)
  missing <- !is.finite(joined[[target_column]])
  joined[missing, (target_column) :=
    stats::coef(model)[[1L]] + stats::coef(model)[[2L]] * VIX]
  list(series = joined, train_end = train_end, model = model)
}

vxn_filled <- fill_from_vix(vxn, "VXN")
vxd_filled <- fill_from_vix(vxd, "VXD")

make_schedule <- function(implied, blocks) {
  frame <- data.table::data.table(Date = schedule_dates, ID = seq.int(0L, length(schedule_dates) - 1L))
  frame <- merge(frame, implied, by = "Date", all.x = TRUE, sort = FALSE)
  frame <- merge(frame, blocks, by = "ID", all.x = TRUE, sort = FALSE)
  data.table::setorder(frame, ID)
  frame
}

spx_schedule <- make_schedule(vix, spx_blocks)
ndx_schedule <- make_schedule(vxn_filled$series[, .(Date, VXN)], ndx_blocks)
djx_schedule <- make_schedule(vxd_filled$series[, .(Date, VXD)], djx_blocks)

forecast_one <- function(
  trading_date,
  schedule,
  implied_column,
  history_start = NULL,
  high_frequency_start
) {
  history <- schedule[Date < trading_date]
  if (!is.null(history_start)) history <- history[Date >= history_start]
  current <- schedule[Date == trading_date]
  if (nrow(current) != 1L) stop(sprintf("Missing or duplicate forecast row for %s.", trading_date))
  implied <- current[[implied_column]]
  if (trading_date < high_frequency_start) {
    model <- stats::lm(
      stats::as.formula(sprintf("log(fmvol) ~ log(hmvol) + log(%s)", implied_column)),
      data = history
    )
    raw <- exp(
      stats::coef(model)[[1L]] +
        stats::coef(model)[[2L]] * log(current$hmvol) +
        stats::coef(model)[[3L]] * log(implied)
    )
    raw * exp((1 - summary(model)$r.squared) * stats::var(log(history$fmvol), na.rm = TRUE))
  } else {
    history <- history[Date >= as.Date("2000-01-01")]
    model <- stats::lm(
      stats::as.formula(sprintf("log(fmvol) ~ log(hf1) + log(%s)", implied_column)),
      data = history
    )
    raw <- exp(
      stats::coef(model)[[1L]] +
        stats::coef(model)[[2L]] * log(current$hf1) +
        stats::coef(model)[[3L]] * log(implied)
    )
    raw * exp((1 - summary(model)$r.squared) * stats::var(log(history$fmvol), na.rm = TRUE))
  }
}

spx_forecast <- vapply(
  option_dates,
  forecast_one,
  FUN.VALUE = numeric(1L),
  schedule = spx_schedule,
  implied_column = "VIX",
  history_start = NULL,
  high_frequency_start = as.Date("2001-01-01")
)
ndx_forecast <- vapply(
  option_dates,
  forecast_one,
  FUN.VALUE = numeric(1L),
  schedule = ndx_schedule,
  implied_column = "VXN",
  history_start = as.Date("1995-05-23"),
  high_frequency_start = vxn_filled$train_end
)
djx_forecast <- vapply(
  option_dates,
  forecast_one,
  FUN.VALUE = numeric(1L),
  schedule = djx_schedule,
  implied_column = "VXD",
  history_start = as.Date("1995-05-23"),
  high_frequency_start = as.Date("2001-01-01")
)

business_days <- vapply(
  seq_len(nrow(calendar)),
  function(i) sum(gspc$Date > calendar$Date[[i]] & gspc$Date <= calendar$Expiration[[i]]),
  FUN.VALUE = integer(1L)
)
forecasts <- data.table::data.table(
  Date = option_dates,
  BizDays = business_days,
  SPX_Vol_Pred = spx_forecast,
  NDX_Vol_Pred = ndx_forecast,
  DJX_Vol_Pred = djx_forecast
)
if (anyNA(forecasts) || any(!is.finite(as.matrix(forecasts[, -1L])))) {
  stop("Generated volatility forecasts contain missing or non-finite values.")
}

ensure_directory(dirname(forecast_path))
ensure_directory(dirname(returns_path))
data.table::fwrite(forecasts, forecast_path, na = "NA", quote = TRUE)
data.table::fwrite(underprice, returns_path, na = "NA", quote = TRUE)

report <- list(
  generated_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  method = "R reconstruction of the paper's historical-return and volatility-forecast procedure",
  inputs = list(
    yahoo = file_fingerprint(yahoo_path),
    djia = file_fingerprint(djia_path),
    vxd = file_fingerprint(vxd_path),
    oxford_man = file_fingerprint(oxford_path)
  ),
  option_calendar = list(
    rows = nrow(calendar),
    first_date = as.character(min(option_dates)),
    last_date = as.character(max(option_dates))
  ),
  ndx_extension = list(
    observations = extension_length,
    intercept = unname(stats::coef(extension_model)[[1L]]),
    slope = unname(stats::coef(extension_model)[[2L]])
  ),
  vxn_fill = list(
    training_end = as.character(vxn_filled$train_end),
    intercept = unname(stats::coef(vxn_filled$model)[[1L]]),
    slope = unname(stats::coef(vxn_filled$model)[[2L]])
  ),
  vxd_fill = list(
    training_end = as.character(vxd_filled$train_end),
    intercept = unname(stats::coef(vxd_filled$model)[[1L]]),
    slope = unname(stats::coef(vxd_filled$model)[[2L]])
  ),
  outputs = list(
    forecasts = file_fingerprint(forecast_path),
    index_returns = file_fingerprint(returns_path)
  )
)
write_json(report, report_path)
log_message("Auxiliary inputs rebuilt: %s; %s", forecast_path, returns_path)
