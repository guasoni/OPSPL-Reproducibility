args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate src/scripts/04_optimize_portfolios.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)
require_packages(c("quadprog", "jsonlite"))
config <- read_config(root, args)
cli_value <- function(name, default = NULL) arg_value(args, name, default)

ticker <- toupper(cli_value("--ticker", "SPX"))
mode <- tolower(cli_value("--mode", "unconstrained"))
pricing <- tolower(cli_value("--pricing", "bid-ask"))
workers <- as.integer(cli_value("--cores", if (is.null(config$workers)) "1" else as.character(config$workers)))
max_dates <- as.integer(cli_value("--max-dates", "0"))
date_indices_argument <- cli_value("--date-indices", "")
gamma_values <- as.numeric(strsplit(cli_value("--gamma", "1,3,5"), ",", fixed = TRUE)[[1L]])
leverage_values <- as.numeric(strsplit(cli_value("--leverage", "0.02,0.03,0.05"), ",", fixed = TRUE)[[1L]])
output_root <- pipeline_output_root(root, config)
output_argument_cli <- cli_value("--output-dir", "")
output_argument <- if (nzchar(output_argument_cli)) {
  resolve_from_root(root, output_argument_cli)
} else {
  file.path(output_root, "step4")
}

if (!ticker %in% c("SPX", "NDX", "DJX")) stop("--ticker must be SPX, NDX, or DJX")
if (!mode %in% c("unconstrained", "solvency", "small")) stop("--mode must be unconstrained, solvency, or small")
if (!pricing %in% c("bid-ask", "midprice")) stop("--pricing must be bid-ask or midprice")
if (is.na(workers) || workers < 1L) stop("--cores must be a positive integer")
if (any(!gamma_values %in% c(1, 3, 5))) stop("--gamma values must be drawn from 1,3,5")
if (any(!leverage_values %in% c(0.02, 0.03, 0.05))) stop("--leverage values must be drawn from 0.02,0.03,0.05")

configs <- expand.grid(
  gamma = gamma_values,
  leverage = leverage_values,
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)
configs <- configs[order(configs$leverage, configs$gamma), , drop = FALSE]
rownames(configs) <- NULL

input_path <- file.path(output_root, "step3", paste0(ticker, "_filtered.csv"))
underprice_path <- resolve_from_root(root, config$public_index_returns)
if (is.null(underprice_path)) underprice_path <- file.path(root, "work", "auxiliary", "paper_index_return_history.csv")
assert_file(input_path, paste(ticker, "prepared Step 3 input"))
assert_file(underprice_path, "Public-data index-return history")

ind <- read.csv(input_path, stringsAsFactors = FALSE, check.names = FALSE)
underprice <- read.csv(underprice_path, stringsAsFactors = FALSE, check.names = FALSE)
if (pricing == "midprice" && !"MidPrice" %in% names(ind)) {
  stop("The prepared option input must contain MidPrice when --pricing=midprice")
}
ind$Date <- as.Date(ind$Date)
underprice$Date <- as.Date(underprice$Date)
ind <- ind[order(ind$DateIndex), , drop = FALSE]
if (ticker == "NDX") underprice <- na.omit(underprice)

Dates <- as.Date(unique(ind$Date))
if (!is.na(max_dates) && max_dates > 0L) Dates <- head(Dates, max_dates)
if (nzchar(date_indices_argument)) {
  date_indices <- as.integer(strsplit(date_indices_argument, ",", fixed = TRUE)[[1L]])
  if (any(is.na(date_indices)) || any(date_indices < 1L) || any(date_indices > length(Dates))) {
    stop("--date-indices must be comma-separated one-based indices within the prepared sample")
  }
  Dates <- Dates[date_indices]
}

meanvariance_solver <- function(meanret, covret, gamma, leverage, d, high = NULL, low = NULL) {
  res <- 1
  lambda_up <- 200000
  lambda_low <- 0.0001
  counter <- 0L
  target <- leverage^2 / d
  norm_squared <- function(x) drop(t(x) %*% x)

  while (target - norm_squared(res) >= 0.000001 || norm_squared(res) > target) {
    if (counter >= 50L) break
    lambda_it <- (lambda_up + lambda_low) / 2
    amat <- diag(length(meanret))
    bvec <- rep(0, length(meanret))
    if (!is.null(high)) {
      amat <- cbind(amat, high, low)
      bvec <- c(bvec, -1, -1)
    }
    dmat <- gamma * covret + lambda_it * diag(nrow(covret))
    solution <- quadprog::solve.QP(Dmat = dmat, dvec = meanret, Amat = amat, bvec = bvec)$solution
    res <- solution
    if (norm_squared(res) > target) lambda_low <- lambda_it else lambda_up <- lambda_it
    counter <- counter + 1L
  }
  c(res, 1 - sum(res))
}

small_position_solver <- function(meanret, leverage, d) {
  positive_mean <- pmax(meanret, 0)
  norm <- sqrt(drop(crossprod(positive_mean)))
  if (!is.finite(norm) || norm == 0) return(c(rep(0, length(meanret)), 1))
  option_weights <- leverage / sqrt(d) * positive_mean / norm
  c(option_weights, 1 - sum(option_weights))
}

bs_price <- function(S, K, T, r, sigma, type) {
  d1 <- (log(S / K) + (r + sigma^2 / 2) * T) / (sigma * sqrt(T))
  d2 <- d1 - sigma * sqrt(T)
  ifelse(
    type == "C",
    S * pnorm(d1) - K * exp(-r * T) * pnorm(d2),
    K * exp(-r * T) * pnorm(-d2) - S * pnorm(-d1)
  )
}

implied_vol <- function(S, K, T, r, price, type) {
  discount <- exp(-r * T)
  lower_bound <- if (type == "C") max(0, S - K * discount) else max(0, K * discount - S)
  upper_bound <- if (type == "C") S else K * discount
  if (!is.finite(price) || price < lower_bound || price > upper_bound) return(NA_real_)
  objective <- function(sigma) bs_price(S, K, T, r, sigma, type) - price
  tryCatch(
    uniroot(objective, lower = 1e-8, upper = 5)$root,
    error = function(e) NA_real_
  )
}

option_return_matrix <- function(options, index_simulation, is_put, rate, days, pricing) {
  observations <- length(index_simulation)
  strikes <- matrix(rep(options$Strike, times = observations), nrow = nrow(options), byrow = FALSE)
  long_premium <- if (pricing == "midprice") options$MidPrice else options$BestOffer
  short_premium <- if (pricing == "midprice") options$MidPrice else options$BestBid
  offers <- matrix(rep(long_premium, times = observations), nrow = nrow(options), byrow = FALSE)
  bids <- matrix(rep(short_premium, times = observations), nrow = nrow(options), byrow = FALSE)
  simulated <- matrix(rep(index_simulation, nrow(options)), nrow = nrow(options), byrow = TRUE)
  discount <- exp(rate / 100 * days / 360)
  payoff <- if (is_put) pmax(strikes - simulated, 0) else pmax(simulated - strikes, 0)
  long <- (payoff - offers * discount) / offers
  short <- (-payoff + bids * discount) / bids
  combined <- matrix(0, nrow = 2 * nrow(options), ncol = observations)
  combined[seq(1, nrow(combined), 2), ] <- long
  combined[seq(2, nrow(combined), 2), ] <- short
  combined
}

scenario_returns <- function(options, index_level, is_put, rate, days, pricing) {
  discount <- exp(rate / 100 * days / 360)
  payoff <- if (is_put) pmax(options$Strike - index_level, 0) else pmax(index_level - options$Strike, 0)
  long_premium <- if (pricing == "midprice") options$MidPrice else options$BestOffer
  short_premium <- if (pricing == "midprice") options$MidPrice else options$BestBid
  long <- (payoff - long_premium * discount) / long_premium
  short <- (-payoff + short_premium * discount) / short_premium
  combined <- numeric(2 * nrow(options))
  combined[seq(1, length(combined), 2)] <- long
  combined[seq(2, length(combined), 2)] <- short
  combined
}

realized_option_returns <- function(options, is_put, rate, days, pricing) {
  discount <- exp(rate / 100 * days / 360)
  payoff <- if (is_put) pmax(options$Strike - options$PriceExp, 0) else pmax(options$PriceExp - options$Strike, 0)
  long_premium <- if (pricing == "midprice") options$MidPrice else options$BestOffer
  short_premium <- if (pricing == "midprice") options$MidPrice else options$BestBid
  long <- (payoff - long_premium * discount) / long_premium
  short <- (-payoff + short_premium * discount) / short_premium
  combined <- numeric(2 * nrow(options))
  combined[seq(1, length(combined), 2)] <- long
  combined[seq(2, length(combined), 2)] <- short
  combined
}

strike_volatilities <- function(options, pricing) {
  volatility_premium <- if (pricing == "midprice") options$MidPrice else options$BestOffer
  calculated <- numeric(nrow(options))
  for (i in seq_len(nrow(options))) {
    calculated[[i]] <- implied_vol(
      S = options$PriceDate[[i]],
      K = options$Strike[[i]],
      T = options$Days[[i]] / 365,
      r = options$Rate[[i]] / 100,
      price = volatility_premium[[i]],
      type = options$CallPut[[i]]
    )
  }
  strikes <- sort(unique(options$Strike))
  values <- vapply(strikes, function(strike) {
    candidates <- calculated[options$Strike == strike]
    if (all(is.na(candidates))) 0 else max(candidates, na.rm = TRUE)
  }, numeric(1))
  data.frame(Strike = strikes, ImpVol = values)
}

build_margin_context <- function(options, strikevol) {
  distance <- abs(options$Strike - options$PriceDate)
  atm_vol <- mean(options$ImpliedVolatility[distance == min(distance)])
  index_returns <- seq(from = -0.08, to = 0.06, length.out = 10)
  index_levels <- options$PriceDate[[1L]] * (1 + index_returns)
  sigma_rates <- c(0.25, 1, 1.75)
  theoretical <- matrix(NA_real_, nrow = length(index_levels) * length(sigma_rates), ncol = nrow(options))
  position <- 1L
  for (level in index_levels) {
    for (sigma_rate in sigma_rates) {
      implied <- strikevol$ImpVol[match(options$Strike, strikevol$Strike)]
      sigma <- if (sigma_rate >= 1) pmax(atm_vol * sigma_rate, implied) else pmin(atm_vol * sigma_rate, implied)
      theoretical[position, ] <- bs_price(
        S = level,
        K = options$Strike,
        T = options$Days / 360,
        r = options$Rate / 100,
        sigma = sigma,
        type = options$CallPut
      )
      position <- position + 1L
    }
  }
  list(theoretical = theoretical)
}

margin_satisfied <- function(portfolio_with_cash, options, context, pricing) {
  port <- portfolio_with_cash[-length(portfolio_with_cash)]
  market_price <- if (pricing == "midprice") {
    options$MidPrice
  } else {
    ifelse(port > 0, options$BestOffer, options$BestBid)
  }
  scenario_ratios <- sweep(context$theoretical, 2, market_price, FUN = "/")
  values <- as.vector(scenario_ratios %*% port)
  margin <- min(values)
  capital_required <- sum(port) - margin
  list(
    satisfied = is.finite(capital_required) && capital_required <= 1,
    margin = margin,
    capital_required = capital_required
  )
}

worker_date <- function(i) {
  trading_date <- Dates[[i]]
  puts <- ind[ind$Date == trading_date & ind$CallPut == "P", , drop = FALSE]
  calls <- ind[ind$Date == trading_date & ind$CallPut == "C", , drop = FALSE]
  if (nrow(puts) == 0L || nrow(calls) == 0L) stop(sprintf("No put/call pair on %s", trading_date))

  vol_pred <- puts$VolPred[[1L]]
  biz_days <- puts$BizDays[[1L]]
  days <- puts$Days[[1L]]
  rate <- puts$Rate[[1L]]
  implied_index <- puts$Implied_Price[[1L]]
  history <- underprice[underprice$Date < trading_date, , drop = FALSE]
  history_returns <- history[[paste0(ticker, "Return")]]
  mean_return <- mean(history_returns)
  sd_return <- sd(history_returns)
  standardized <- (history_returns - mean_return) / sd_return
  sampled <- standardized * vol_pred / sqrt(12) / 100 * sqrt(biz_days / 252 * 12) + mean_return * biz_days / 252 * 12
  simulated_index <- implied_index * (1 + sampled)

  put_matrix <- option_return_matrix(puts, simulated_index, TRUE, rate, days, pricing)
  call_matrix <- option_return_matrix(calls, simulated_index, FALSE, rate, days, pricing)
  all_returns <- t(rbind(put_matrix, call_matrix))
  mean_vector <- as.vector(colMeans(all_returns))
  covariance <- if (mode == "small") NULL else cov(all_returns)
  d <- ncol(all_returns) / 2

  high <- low <- NULL
  if (mode == "solvency") {
    high_level <- max(simulated_index)
    low_level <- min(simulated_index)
    high <- c(
      scenario_returns(puts, high_level, TRUE, rate, days, pricing),
      scenario_returns(calls, high_level, FALSE, rate, days, pricing)
    )
    low <- c(
      scenario_returns(puts, low_level, TRUE, rate, days, pricing),
      scenario_returns(calls, low_level, FALSE, rate, days, pricing)
    )
  }

  actual <- c(
    realized_option_returns(puts, TRUE, rate, days, pricing),
    realized_option_returns(calls, FALSE, rate, days, pricing)
  )
  options <- rbind(puts, calls)
  strikevol <- if (ticker == "SPX") strike_volatilities(options, pricing) else NULL
  margin_context <- if (ticker == "SPX") build_margin_context(options, strikevol) else NULL

  returns <- positions <- numeric(nrow(configs))
  margins <- capital <- rep(NA_real_, nrow(configs))
  satisfied <- rep(TRUE, nrow(configs))
  option_portfolios <- matrix(0, nrow = ncol(all_returns), ncol = nrow(configs))
  solvency_minimum <- rep(NA_real_, nrow(configs))
  last_weights <- if (i == length(Dates)) vector("list", nrow(configs)) else NULL

  for (j in seq_len(nrow(configs))) {
    portfolio <- if (mode == "small") {
      small_position_solver(meanret = mean_vector, leverage = configs$leverage[[j]], d = d)
    } else {
      meanvariance_solver(
        meanret = mean_vector,
        covret = covariance,
        gamma = configs$gamma[[j]],
        leverage = configs$leverage[[j]],
        d = d,
        high = high,
        low = low
      )
    }
    portfolio[abs(portfolio) < 1e-10] <- 0
    option_portfolios[, j] <- portfolio[-length(portfolio)]
    long <- portfolio[seq(1, length(portfolio) - 1, 2)]
    short <- portfolio[seq(2, length(portfolio) - 1, 2)]
    net <- long - short
    net_with_cash <- c(net, 1 - sum(net))
    positions[[j]] <- sum(abs(net))

    if (ticker == "SPX") {
      margin_result <- margin_satisfied(net_with_cash, options, margin_context, pricing)
      satisfied[[j]] <- margin_result$satisfied
      margins[[j]] <- margin_result$margin
      capital[[j]] <- margin_result$capital_required
    }
    active <- if (ticker == "SPX" && mode != "small" && !satisfied[[j]]) rep(0, length(portfolio)) else portfolio
    returns[[j]] <- sum(active[-length(active)] * actual)
    if (!is.null(last_weights)) last_weights[[j]] <- portfolio
  }

  if (mode == "solvency") {
    scenario_portfolio_returns <- all_returns %*% option_portfolios
    solvency_minimum <- apply(scenario_portfolio_returns, 2, min)
    violations <- which(solvency_minimum < -1 - 1e-8)
    if (length(violations)) {
      stop(sprintf(
        "All-scenario solvency validation failed on %s for configuration(s) %s",
        trading_date,
        paste(violations, collapse = ",")
      ))
    }
  }

  list(
    returns = returns,
    positions = positions,
    margins = margins,
    capital = capital,
    satisfied = satisfied,
    solvency_minimum = solvency_minimum,
    last_weights = last_weights
  )
}

cat(sprintf(
  "Running %s %s with %s pricing: %d dates, %d configurations, %d worker(s)\n",
  ticker, mode, pricing, length(Dates), nrow(configs), workers
))
start_time <- proc.time()[["elapsed"]]

if (workers == 1L) {
  results <- lapply(seq_along(Dates), worker_date)
} else {
  workers <- min(workers, length(Dates))
  cluster <- parallel::makeCluster(workers)
  on.exit(parallel::stopCluster(cluster), add = TRUE)
  library_paths <- .libPaths()
  parallel::clusterCall(cluster, function(paths) .libPaths(paths), library_paths)
  parallel::clusterExport(
    cluster,
    c(
      "Dates", "ind", "underprice", "ticker", "mode", "pricing", "configs",
      "meanvariance_solver", "small_position_solver", "bs_price", "implied_vol",
      "option_return_matrix", "scenario_returns", "realized_option_returns",
      "strike_volatilities", "build_margin_context", "margin_satisfied", "worker_date"
    ),
    envir = environment()
  )
  results <- parallel::parLapplyLB(cluster, seq_along(Dates), worker_date, chunk.size = 1L)
  parallel::stopCluster(cluster)
  on.exit(NULL, add = FALSE)
}

elapsed <- proc.time()[["elapsed"]] - start_time
excess_returns <- do.call(rbind, lapply(results, `[[`, "returns"))
realized_positions <- do.call(rbind, lapply(results, `[[`, "positions"))
margin_values <- do.call(rbind, lapply(results, `[[`, "margins"))
capital_required <- do.call(rbind, lapply(results, `[[`, "capital"))
margin_satisfied_matrix <- do.call(rbind, lapply(results, `[[`, "satisfied"))
solvency_minimum <- do.call(rbind, lapply(results, `[[`, "solvency_minimum"))
configuration_labels <- if (mode == "small") {
  sprintf("small_limit_%g_pct", configs$leverage * 100)
} else {
  sprintf("gamma_%g_limit_%g_pct", configs$gamma, configs$leverage * 100)
}
colnames(excess_returns) <- configuration_labels
colnames(realized_positions) <- configuration_labels
colnames(margin_values) <- configuration_labels
colnames(capital_required) <- configuration_labels
colnames(margin_satisfied_matrix) <- configuration_labels
colnames(solvency_minimum) <- configuration_labels

unique_rows <- ind[!duplicated(ind$Date), , drop = FALSE]
unique_rows <- unique_rows[match(Dates, unique_rows$Date), , drop = FALSE]
index_excess_return <- (unique_rows$PriceExp - unique_rows$PriceDate) / unique_rows$PriceDate -
  unique_rows$Rate_simplex / 100 * unique_rows$Days / 360

last_weight_lists <- results[[length(results)]]$last_weights
weight_columns <- if (mode == "small") seq_len(nrow(configs)) else which(configs$gamma == 3)
if (length(weight_columns)) {
  portfolio_weights <- do.call(cbind, last_weight_lists[weight_columns])
  colnames(portfolio_weights) <- configuration_labels[weight_columns]
} else {
  portfolio_weights <- matrix(numeric(0), nrow = 0, ncol = 0)
}

step4_dir <- normalizePath(output_argument, winslash = "/", mustWork = FALSE)
dir.create(step4_dir, recursive = TRUE, showWarnings = FALSE)
mode_suffix <- switch(mode, solvency = "_solvency", small = "_LL", "")
pricing_suffix <- if (pricing == "midprice") "_midprice" else ""
suffix <- paste0(mode_suffix, pricing_suffix)
write.csv(excess_returns, file.path(step4_dir, paste0(ticker, "_Excess_Return", suffix, ".csv")), row.names = FALSE)
write.csv(
  data.frame(index_excess_return = index_excess_return),
  file.path(step4_dir, paste0(ticker, "_ind_excess_return.csv")),
  row.names = FALSE
)
write.csv(portfolio_weights, file.path(step4_dir, paste0(ticker, "_port_weight", suffix, ".csv")), row.names = FALSE)
write.csv(realized_positions, file.path(step4_dir, paste0(ticker, "_realized_position", suffix, ".csv")), row.names = FALSE)
write.csv(
  data.frame(
    Date = rep(Dates, each = nrow(configs)),
    leverage = rep(configs$leverage, times = length(Dates)),
    gamma = rep(configs$gamma, times = length(Dates)),
    margin = as.vector(t(margin_values)),
    capital_required = as.vector(t(capital_required)),
    satisfied = as.vector(t(margin_satisfied_matrix)),
    minimum_in_sample_option_return = as.vector(t(solvency_minimum))
  ),
  file.path(step4_dir, paste0(ticker, "_margin_audit", suffix, ".csv")),
  row.names = FALSE
)

session <- sessionInfo()
metadata <- list(
  ticker = ticker,
  mode = mode,
  pricing = pricing,
  dates = length(Dates),
  configurations = unname(split(configs, seq_len(nrow(configs)))),
  workers = workers,
  elapsed_seconds = elapsed,
  r_version = R.version.string,
  quadprog_version = as.character(utils::packageVersion("quadprog")),
  r_platform = session$platform,
  operating_system = session$running,
  locale = session$locale,
  timezone = session$tzone,
  matrix_products = session$matprod,
  linear_algebra_version = session$LA_version,
  margin_implied_volatility_price = if (pricing == "midprice") "MidPrice" else "BestOffer (ask), per final paper definition",
  margin_initial_premium = if (pricing == "midprice") "MidPrice" else "BestOffer for long positions and BestBid for short positions",
  margin_feasibility_rule = "capital_required <= 1, per final paper definition",
  solvency_validation = "Every in-sample scenario checked; failure threshold -1 - 1e-8",
  small_position_margin_policy = "Margin is diagnostic only; first-order benchmark returns are not cash-screened",
  completed_at = format(Sys.time(), tz = "UTC", usetz = TRUE)
)
dput(metadata, file = file.path(step4_dir, paste0(ticker, "_run_metadata", suffix, ".dput")))
cat(sprintf("Completed in %.1f seconds. Outputs: %s\n", elapsed, step4_dir))
