args <- commandArgs(trailingOnly = TRUE)
script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate src/scripts/05_generate_outputs.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)
require_packages(c("data.table", "jsonlite"))
config <- read_config(root, args)
data_mode <- if (is.null(config$data_mode)) "paper-vintage" else config$data_mode
if (!data_mode %in% c("paper-vintage", "current-vintage")) {
  stop("config$data_mode must be paper-vintage or current-vintage.")
}

output_root <- pipeline_output_root(root, config)
step3_dir <- file.path(output_root, "step3")
step4_dir <- file.path(output_root, "step4")
tables_dir <- file.path(output_root, "tables")
wealth_dir <- file.path(output_root, "wealth_series")
expected_dir <- file.path(root, "expected", "paper_values")
ensure_directory(tables_dir)
ensure_directory(wealth_dir)

ordering <- data.table::CJ(leverage_pct = c(2, 3, 5), gamma = c(1, 3, 5))
data.table::setorder(ordering, leverage_pct, gamma)
metric_fields <- c(
  "mean_ann", "sd_ann", "sharpe_ann", "alpha_ann", "beta", "hsd_ann",
  "appraisal_ann"
)
ratio_fields <- c("sharpe_ann", "beta", "appraisal_ann")

numeric_matrix <- function(path) {
  assert_file(path)
  frame <- data.table::fread(path, check.names = FALSE, showProgress = FALSE)
  if (ncol(frame)) {
    first <- suppressWarnings(as.integer(frame[[1L]]))
    if (length(first) == nrow(frame) && !anyNA(first) && identical(first, seq_len(nrow(frame)))) {
      frame <- frame[, -1L, with = FALSE]
    }
  }
  matrix(as.numeric(as.matrix(frame)), nrow = nrow(frame), ncol = ncol(frame), dimnames = dimnames(as.matrix(frame)))
}

performance_metrics <- function(returns, benchmark) {
  valid <- is.finite(returns) & is.finite(benchmark)
  y <- returns[valid]
  x <- benchmark[valid]
  mean_monthly <- mean(y)
  sd_monthly <- stats::sd(y)
  benchmark_variance <- stats::var(x)
  beta <- stats::cov(y, x) / benchmark_variance
  alpha <- mean_monthly - beta * mean(x)
  residual_sd <- sqrt(max(0, sd_monthly^2 - beta^2 * benchmark_variance))
  list(
    n = length(y),
    mean_ann = mean_monthly * 12,
    sd_ann = sd_monthly * sqrt(12),
    sharpe_ann = mean_monthly / sd_monthly * sqrt(12),
    alpha_ann = alpha * 12,
    beta = beta,
    hsd_ann = residual_sd * sqrt(12),
    appraisal_ann = if (residual_sd == 0) NA_real_ else alpha / residual_sd * sqrt(12)
  )
}

near_zero_real_root <- function(coefficients_in_increasing_order) {
  roots <- polyroot(coefficients_in_increasing_order)
  real <- Re(roots[abs(Im(roots)) <= 1e-9])
  if (!length(real)) stop("No real root found for equivalent-rate equation.")
  real[[which.min(abs(real))]]
}

equivalent_rates <- function(returns, gamma) {
  r <- returns[is.finite(returns)]
  esr <- if (gamma == 1) {
    exp(mean(log1p(r))) - 1
  } else {
    mean((1 + r)^(1 - gamma))^(1 / (1 - gamma)) - 1
  }
  rhs2 <- mean(r) - gamma / 2 * mean(r^2)
  repository_stored_mvr <- mean(r) - gamma / 2 * stats::var(r) - gamma / 2 * mean(r)^2
  mvr <- near_zero_real_root(c(-rhs2, 1, -gamma / 2))
  cubic <- gamma * (gamma + 1) / 6
  quartic <- gamma * (gamma + 1) * (gamma + 2) / 24
  rhs3 <- mean(r) - gamma / 2 * mean(r^2) + cubic * mean(r^3)
  rhs4 <- rhs3 - quartic * mean(r^4)
  skr <- near_zero_real_root(c(-rhs4, 1, -gamma / 2, cubic, -quartic))
  list(
    esr_pct_ann = esr * 1200,
    mvr_pct_ann = mvr * 1200,
    skr_pct_ann = skr * 1200,
    esr_minus_mvr_pp = (esr - mvr) * 1200,
    esr_minus_skr_pp = (esr - skr) * 1200,
    one_minus_mvr_over_esr_pct = (1 - mvr / esr) * 100,
    one_minus_skr_over_esr_pct = (1 - skr / esr) * 100,
    second_order_rhs_pct_ann = rhs2 * 1200,
    third_order_rhs_pct_ann = rhs3 * 1200,
    fourth_order_rhs_pct_ann = rhs4 * 1200,
    repository_stored_mvr_pct_ann = repository_stored_mvr * 1200,
    repository_stored_skr_pct_ann = rhs3 * 1200
  )
}

metrics_row <- function(returns, benchmark, identifiers) {
  data.table::as.data.table(c(identifiers, performance_metrics(returns, benchmark)))
}

all_performance <- list()
for (ticker in c("SPX", "NDX", "DJX")) {
  benchmark <- numeric_matrix(file.path(step4_dir, paste0(ticker, "_ind_excess_return.csv")))[, 1L]
  for (panel in c("unconstrained", "solvency")) {
    suffix <- if (panel == "solvency") "_solvency" else ""
    returns <- numeric_matrix(file.path(step4_dir, paste0(ticker, "_Excess_Return", suffix, ".csv")))
    rows <- lapply(seq_len(nrow(ordering)), function(index) {
      metrics_row(
        returns[, index],
        benchmark,
        list(
          ticker = ticker,
          panel = panel,
          leverage_pct = ordering$leverage_pct[[index]],
          gamma = as.character(ordering$gamma[[index]])
        )
      )
    })
    panel_table <- data.table::rbindlist(rows, fill = TRUE)
    data.table::fwrite(panel_table, file.path(tables_dir, paste0(ticker, "_", panel, "_performance.csv")), na = "NA")
    all_performance[[length(all_performance) + 1L]] <- panel_table
  }
}

spx_benchmark <- numeric_matrix(file.path(step4_dir, "SPX_ind_excess_return.csv"))[, 1L]
spx_midprice_path <- file.path(step4_dir, "SPX_Excess_Return_midprice.csv")
assert_file(spx_midprice_path, "SPX corrected midprice robustness output")
spx_midprice <- numeric_matrix(spx_midprice_path)
if (ncol(spx_midprice) != nrow(ordering)) {
  stop("SPX midprice output does not contain the nine paper configurations")
}
midprice_rows <- lapply(seq_len(nrow(ordering)), function(index) {
  metrics_row(
    spx_midprice[, index],
    spx_benchmark,
    list(
      ticker = "SPX",
      panel = "midprice",
      leverage_pct = ordering$leverage_pct[[index]],
      gamma = as.character(ordering$gamma[[index]])
    )
  )
})
midprice_table <- data.table::rbindlist(midprice_rows, fill = TRUE)
data.table::fwrite(midprice_table, file.path(tables_dir, "SPX_midprice_performance.csv"), na = "NA")
midprice_computed <- midprice_table[, .(
  leverage_pct,
  gamma = as.integer(gamma),
  mean_pct = mean_ann * 100,
  sd_pct = sd_ann * 100,
  sharpe = sharpe_ann,
  alpha_pct = alpha_ann * 100,
  beta,
  hedged_sd_pct = hsd_ann * 100,
  appraisal = appraisal_ann
)]
midprice_expected <- data.table::fread(file.path(expected_dir, "SPX_midprice_corrected.csv"))
midprice_comparison <- merge(
  midprice_expected,
  midprice_computed,
  by = c("leverage_pct", "gamma"),
  suffixes = c("_paper", "_computed"),
  sort = FALSE
)
midprice_fields <- setdiff(names(midprice_expected), c("leverage_pct", "gamma"))
for (field in midprice_fields) {
  paper_column <- paste0(field, "_paper")
  computed_column <- paste0(field, "_computed")
  match_column <- paste0(field, "_matches_paper_rounding")
  data.table::set(
    midprice_comparison,
    j = match_column,
    value = abs(round(midprice_comparison[[computed_column]], 2) - midprice_comparison[[paper_column]]) <= 1e-10
  )
}
midprice_match_columns <- grep("_matches_paper_rounding$", names(midprice_comparison), value = TRUE)
midprice_comparison[, all_cells_match := rowSums(.SD) == length(midprice_match_columns), .SDcols = midprice_match_columns]
data.table::fwrite(midprice_comparison, file.path(tables_dir, "SPX_midprice_comparison.csv"), na = "NA")
spx_small <- numeric_matrix(file.path(step4_dir, "SPX_Excess_Return_LL.csv"))
small_rows <- lapply(seq_along(c(2, 3, 5)), function(index) {
  metrics_row(
    spx_small[, index],
    spx_benchmark,
    list(ticker = "SPX", panel = "small_position_limit", leverage_pct = c(2, 3, 5)[[index]], gamma = "Small")
  )
})
small_table <- data.table::rbindlist(small_rows, fill = TRUE)
data.table::fwrite(small_table, file.path(tables_dir, "SPX_small_position_performance.csv"), na = "NA")
all_performance[[length(all_performance) + 1L]] <- small_table
performance_table <- data.table::rbindlist(all_performance, fill = TRUE)
data.table::fwrite(performance_table, file.path(tables_dir, "all_performance_tables.csv"), na = "NA")

performance_long <- data.table::melt(
  performance_table,
  id.vars = c("ticker", "panel", "leverage_pct", "gamma", "n"),
  measure.vars = metric_fields,
  variable.name = "statistic",
  value.name = "raw_computed"
)
performance_long[, computed := raw_computed * ifelse(statistic %in% ratio_fields, 1, 100)]
expected_performance <- data.table::fread(file.path(expected_dir, "performance_cells.csv"))
expected_performance[, gamma := as.character(gamma)]
performance_comparison <- merge(
  expected_performance,
  performance_long,
  by = c("ticker", "panel", "leverage_pct", "gamma", "statistic"),
  all.x = TRUE,
  sort = FALSE
)
performance_comparison[, rounded_computed := round(computed, 2)]
performance_comparison[, matches_paper_rounding := abs(rounded_computed - paper) <= 1e-10]
performance_comparison[, numerical_tolerance := ifelse(statistic %in% ratio_fields, 0.005, 0.02)]
configured_auxiliary_mode <- if (is.null(config$auxiliary_data_mode)) "archived" else config$auxiliary_data_mode
performance_comparison[, auxiliary_data_mode := configured_auxiliary_mode]
if (identical(configured_auxiliary_mode, "source-current")) {
  performance_comparison[
    ticker == "DJX" & panel %in% c("unconstrained", "solvency"),
    numerical_tolerance := ifelse(statistic %in% ratio_fields, 0.007, 0.025)
  ]
}
performance_comparison[, absolute_difference := abs(computed - paper)]
performance_comparison[is.na(diagnosed_numerical_exception), diagnosed_numerical_exception := FALSE]
performance_comparison[, passes_reproduction_policy :=
  matches_paper_rounding | absolute_difference <= numerical_tolerance | diagnosed_numerical_exception]
data.table::fwrite(performance_comparison, file.path(tables_dir, "final_paper_cell_comparison.csv"), na = "NA")

spx_returns <- numeric_matrix(file.path(step4_dir, "SPX_Excess_Return.csv"))
rate_rows <- lapply(seq_len(nrow(ordering)), function(index) {
  data.table::as.data.table(c(
    list(gamma = ordering$gamma[[index]], leverage_pct = ordering$leverage_pct[[index]]),
    equivalent_rates(spx_returns[, index], ordering$gamma[[index]])
  ))
})
rate_table <- data.table::rbindlist(rate_rows, fill = TRUE)
data.table::fwrite(rate_table, file.path(tables_dir, "table_4_5_corrected.csv"), na = "NA")
rate_expected <- data.table::fread(file.path(expected_dir, "table_4_5_final.csv"))
rate_fields <- setdiff(names(rate_expected), c("gamma", "leverage_pct"))
rate_long <- data.table::melt(rate_table, id.vars = c("gamma", "leverage_pct"), measure.vars = rate_fields, variable.name = "statistic", value.name = "computed")
rate_expected_long <- data.table::melt(rate_expected, id.vars = c("gamma", "leverage_pct"), measure.vars = rate_fields, variable.name = "statistic", value.name = "paper")
rate_comparison <- merge(rate_expected_long, rate_long, by = c("gamma", "leverage_pct", "statistic"), sort = FALSE)
rate_comparison[, rounded_computed := round(computed, 2)]
rate_comparison[, matches_paper_rounding := abs(rounded_computed - paper) <= 1e-10]
rate_comparison[, `:=`(
  absolute_difference = abs(computed - paper),
  numerical_tolerance = 0.02
)]
rate_comparison[, passes_reproduction_policy := matches_paper_rounding | absolute_difference <= numerical_tolerance]
data.table::fwrite(rate_comparison, file.path(tables_dir, "table_4_5_comparison.csv"), na = "NA")

margin_rows <- list()
for (panel in c("unconstrained", "solvency")) {
  suffix <- if (panel == "solvency") "_solvency" else ""
  audit <- data.table::fread(file.path(step4_dir, paste0("SPX_margin_audit", suffix, ".csv")))
  if (!is.logical(audit$satisfied)) audit[, satisfied := tolower(as.character(satisfied)) == "true"]
  for (index in seq_len(nrow(ordering))) {
    selected <- audit[
      abs(leverage - ordering$leverage_pct[[index]] / 100) <= 1e-12 & gamma == ordering$gamma[[index]]
    ]
    margin_rows[[length(margin_rows) + 1L]] <- data.table::data.table(
      panel = panel,
      leverage_pct = ordering$leverage_pct[[index]],
      gamma = ordering$gamma[[index]],
      computed_infeasible_pct = mean(!selected$satisfied) * 100
    )
  }
}
margin_table <- data.table::rbindlist(margin_rows)
margin_expected <- data.table::fread(file.path(expected_dir, "SPX_margin_cells.csv"))
margin_comparison <- merge(margin_expected, margin_table, by = c("panel", "leverage_pct", "gamma"), sort = FALSE)
margin_comparison[, rounded_computed := round(computed_infeasible_pct, 2)]
margin_comparison[, matches_paper_rounding := abs(rounded_computed - paper_infeasible_pct) <= 1e-10]
data.table::fwrite(margin_comparison, file.path(tables_dir, "SPX_margin_violation_comparison.csv"), na = "NA")

index_summary_rows <- list()
for (ticker in c("SPX", "NDX", "DJX")) {
  options <- data.table::fread(file.path(step3_dir, paste0(ticker, "_filtered.csv")), showProgress = FALSE)
  options[, Date := normalize_iso_date(Date)]
  options <- options[Date >= "1997-10-20"]
  options[, moneyness := Strike / PriceDate]
  options[, relative_spread := (BestOffer - BestBid) / ((BestOffer + BestBid) / 2)]
  daily <- options[, {
    put_rows <- .SD[CallPut == "P"]
    call_rows <- .SD[CallPut == "C"]
    list(
      atm_put_spread_pct = put_rows$relative_spread[[which.min(abs(put_rows$moneyness - 1))]] * 100,
      atm_call_spread_pct = call_rows$relative_spread[[which.min(abs(call_rows$moneyness - 1))]] * 100,
      min_moneyness = min(moneyness),
      max_moneyness = max(moneyness)
    )
  }, by = Date]
  index_summary_rows[[ticker]] <- data.table::data.table(
    ticker = ticker,
    atm_put_spread_pct = mean(daily$atm_put_spread_pct),
    atm_call_spread_pct = mean(daily$atm_call_spread_pct),
    min_moneyness = mean(daily$min_moneyness),
    max_moneyness = mean(daily$max_moneyness),
    realized_volatility_status = "Planned expansion: public-source realized-volatility cell not yet generated"
  )
}
index_summary <- data.table::rbindlist(index_summary_rows, fill = TRUE)
data.table::fwrite(index_summary, file.path(tables_dir, "index_summary_option_statistics.csv"), na = "NA")
index_long <- data.table::melt(
  index_summary,
  id.vars = c("ticker", "realized_volatility_status"),
  measure.vars = c("atm_put_spread_pct", "atm_call_spread_pct", "min_moneyness", "max_moneyness"),
  variable.name = "statistic",
  value.name = "computed"
)
index_expected <- data.table::fread(file.path(expected_dir, "index_summary_option_cells.csv"))
index_comparison <- merge(index_expected, index_long, by = c("ticker", "statistic"), sort = FALSE)
index_comparison[, rounded_computed := round(computed, display_decimals)]
index_comparison[, matches_paper_rounding := abs(rounded_computed - paper) <= 10^(-(display_decimals + 8))]
data.table::fwrite(index_comparison, file.path(tables_dir, "index_summary_option_comparison.csv"), na = "NA")

subperiod_rows <- list()
period_labels <- c("1996-2000", "2001-2005", "2006-2010", "2011-2015", "2016-2020")
for (period_index in seq_along(period_labels)) {
  rows <- ((period_index - 1L) * 60L + 1L):(period_index * 60L)
  benchmark_slice <- spx_benchmark[rows]
  for (portfolio_index in seq_len(nrow(ordering))) {
    subperiod_rows[[length(subperiod_rows) + 1L]] <- metrics_row(
      spx_returns[rows, portfolio_index],
      benchmark_slice,
      list(
        period = period_labels[[period_index]],
        asset = "SPX options",
        leverage_pct = ordering$leverage_pct[[portfolio_index]],
        gamma = ordering$gamma[[portfolio_index]]
      )
    )
  }
  subperiod_rows[[length(subperiod_rows) + 1L]] <- metrics_row(
    benchmark_slice,
    benchmark_slice,
    list(period = period_labels[[period_index]], asset = "SPX index", leverage_pct = NA_real_, gamma = NA_real_)
  )
}
subperiod_table <- data.table::rbindlist(subperiod_rows, fill = TRUE)
data.table::fwrite(subperiod_table, file.path(tables_dir, "SPX_five_year_performance.csv"), na = "NA")
subperiod_long <- data.table::melt(
  subperiod_table,
  id.vars = c("period", "asset", "leverage_pct", "gamma", "n"),
  measure.vars = metric_fields,
  variable.name = "statistic",
  value.name = "raw_computed"
)
subperiod_long[, computed := raw_computed * ifelse(statistic %in% ratio_fields, 1, 100)]
subperiod_expected <- data.table::fread(file.path(expected_dir, "SPX_five_year_cells.csv"))
subperiod_comparison <- merge(
  subperiod_expected,
  subperiod_long,
  by = c("period", "asset", "leverage_pct", "gamma", "statistic"),
  all.x = TRUE,
  sort = FALSE
)
subperiod_comparison[, rounded_computed := round(computed, 2)]
subperiod_comparison[, matches_paper_rounding := abs(rounded_computed - paper) <= 1e-10]
subperiod_comparison[, numerical_tolerance := ifelse(statistic %in% ratio_fields, 0.005, 0.02)]
subperiod_comparison[, absolute_difference := abs(computed - paper)]
subperiod_comparison[is.na(diagnosed_numerical_exception), diagnosed_numerical_exception := FALSE]
subperiod_comparison[, passes_reproduction_policy :=
  matches_paper_rounding | absolute_difference <= numerical_tolerance | diagnosed_numerical_exception]
data.table::fwrite(subperiod_comparison, file.path(tables_dir, "SPX_five_year_cell_comparison.csv"), na = "NA")

position_rows <- list()
wealth_endpoint_rows <- list()
for (ticker in c("SPX", "NDX", "DJX")) {
  for (panel in c("unconstrained", "solvency")) {
    suffix <- if (panel == "solvency") "_solvency" else ""
    positions <- numeric_matrix(file.path(step4_dir, paste0(ticker, "_realized_position", suffix, ".csv")))
    for (index in seq_len(nrow(ordering))) {
      values <- positions[, index]
      position_rows[[length(position_rows) + 1L]] <- data.table::data.table(
        ticker = ticker,
        panel = panel,
        leverage_pct = ordering$leverage_pct[[index]],
        gamma = ordering$gamma[[index]],
        mean_effective_position_pct = mean(values, na.rm = TRUE) * 100,
        sd_effective_position_pct = stats::sd(values, na.rm = TRUE) * 100
      )
    }
  }

  dates <- data.table::fread(file.path(step3_dir, paste0(ticker, "_filtered.csv")), showProgress = FALSE)
  dates <- dates[!duplicated(Date)]
  unconstrained <- numeric_matrix(file.path(step4_dir, paste0(ticker, "_Excess_Return.csv")))
  solvency <- numeric_matrix(file.path(step4_dir, paste0(ticker, "_Excess_Return_solvency.csv")))
  if (nrow(dates) != nrow(unconstrained) || nrow(dates) != nrow(solvency)) stop(paste(ticker, "date and return lengths differ"))
  risk_free <- dates$Rate_simplex / 100 * dates$Days / 360
  wealth <- data.table::data.table(Date = dates$Date)
  for (index in c(2L, 5L, 8L)) {
    leverage <- ordering$leverage_pct[[index]]
    data.table::set(
      wealth,
      j = paste0("unconstrained_gamma3_L", leverage),
      value = cumprod(1 + unconstrained[, index] + risk_free)
    )
    data.table::set(
      wealth,
      j = paste0("solvency_gamma3_L", leverage),
      value = cumprod(1 + solvency[, index] + risk_free)
    )
  }
  data.table::set(wealth, j = "index_price_relative", value = dates$PriceExp / dates$PriceDate[[1L]])
  data.table::fwrite(wealth, file.path(wealth_dir, paste0(ticker, "_wealth_series.csv")), na = "NA")
  for (series_name in setdiff(names(wealth), "Date")) {
    wealth_endpoint_rows[[length(wealth_endpoint_rows) + 1L]] <- data.table::data.table(
      ticker = ticker,
      series = series_name,
      computed_endpoint = wealth[[series_name]][[nrow(wealth)]]
    )
  }
}
position_table <- data.table::rbindlist(position_rows)
data.table::fwrite(position_table, file.path(tables_dir, "effective_positions.csv"), na = "NA")
position_long <- data.table::melt(
  position_table,
  id.vars = c("ticker", "panel", "leverage_pct", "gamma"),
  measure.vars = c("mean_effective_position_pct", "sd_effective_position_pct"),
  variable.name = "statistic",
  value.name = "computed"
)
position_expected <- data.table::fread(file.path(expected_dir, "effective_position_cells.csv"))
position_comparison <- merge(position_expected, position_long, by = c("ticker", "panel", "leverage_pct", "gamma", "statistic"), sort = FALSE)
position_comparison[, rounded_computed := round(computed, 2)]
position_comparison[, matches_paper_rounding := abs(rounded_computed - paper) <= 1e-10]
position_comparison[, `:=`(
  absolute_difference = abs(computed - paper),
  numerical_tolerance = 0.02
)]
position_comparison[, passes_reproduction_policy :=
  matches_paper_rounding | absolute_difference <= numerical_tolerance]
data.table::fwrite(position_comparison, file.path(tables_dir, "effective_position_comparison.csv"), na = "NA")

wealth_endpoints <- data.table::rbindlist(wealth_endpoint_rows)
wealth_expected <- data.table::fread(file.path(expected_dir, "wealth_endpoints.csv"))
wealth_comparison <- merge(wealth_expected, wealth_endpoints, by = c("ticker", "series"), all.x = TRUE, sort = FALSE)
wealth_comparison[, relative_difference := ifelse(
  audited_reference_endpoint == 0,
  abs(computed_endpoint - audited_reference_endpoint),
  abs(computed_endpoint / audited_reference_endpoint - 1)
)]
wealth_comparison[, passes_reproduction_policy :=
  is.finite(relative_difference) & relative_difference <= maximum_relative_difference]
data.table::fwrite(wealth_comparison, file.path(tables_dir, "wealth_endpoint_comparison.csv"), na = "NA")

paper_value_pass <- all(c(
  performance_comparison$passes_reproduction_policy,
  midprice_comparison$all_cells_match,
  rate_comparison$passes_reproduction_policy,
  margin_comparison$matches_paper_rounding,
  index_comparison$matches_paper_rounding,
  subperiod_comparison$passes_reproduction_policy,
  position_comparison$passes_reproduction_policy,
  wealth_comparison$passes_reproduction_policy
))
generation_complete <- all(c(
  is.finite(performance_comparison$computed),
  is.finite(as.matrix(midprice_computed[, ..midprice_fields])),
  is.finite(rate_comparison$computed),
  is.finite(margin_comparison$computed_infeasible_pct),
  is.finite(index_comparison$computed),
  is.finite(subperiod_comparison$computed),
  is.finite(position_comparison$computed),
  is.finite(wealth_comparison$computed_endpoint)
))
pipeline_pass <- generation_complete && (data_mode != "paper-vintage" || paper_value_pass)

counts <- list(
  data_mode = data_mode,
  auxiliary_data_mode = configured_auxiliary_mode,
  performance_cells = nrow(performance_comparison),
  performance_display_matches = sum(performance_comparison$matches_paper_rounding),
  performance_policy_failures = sum(!performance_comparison$passes_reproduction_policy),
  midprice_cells = nrow(midprice_expected) * length(midprice_fields),
  midprice_failures = sum(!unlist(midprice_comparison[, ..midprice_match_columns])),
  table_4_5_cells = nrow(rate_comparison),
  table_4_5_failures = sum(!rate_comparison$passes_reproduction_policy),
  margin_cells = nrow(margin_comparison),
  margin_failures = sum(!margin_comparison$matches_paper_rounding),
  index_summary_option_cells = nrow(index_comparison),
  index_summary_failures = sum(!index_comparison$matches_paper_rounding),
  five_year_cells = nrow(subperiod_comparison),
  five_year_policy_failures = sum(!subperiod_comparison$passes_reproduction_policy),
  effective_position_cells = nrow(position_comparison),
  effective_position_failures = sum(!position_comparison$passes_reproduction_policy),
  wealth_endpoints = nrow(wealth_comparison),
  wealth_endpoint_failures = sum(!wealth_comparison$passes_reproduction_policy),
  generation_complete = generation_complete,
  paper_value_pass = paper_value_pass,
  pipeline_pass = pipeline_pass,
  overall_pass = pipeline_pass
)
write_json(counts, file.path(tables_dir, "table_validation_summary.json"))
print(counts)
if (!counts$pipeline_pass) stop("One or more generated paper cells failed the reproduction policy.")
if (data_mode == "current-vintage" && !isTRUE(paper_value_pass)) {
  log_message("Current-vintage run completed; differences from final-paper cells are reported, not treated as code failures.")
}
log_message("Tables and wealth series complete: %s", tables_dir)
