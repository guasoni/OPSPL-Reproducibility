script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate tests/test_method_formulas.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), ".."),
  winslash = "/"
)
source(file.path(root, "src", "R", "utils.R"), local = TRUE)
require_packages("quadprog")

failures <- character()
check <- function(condition, message) {
  if (!isTRUE(condition)) failures <<- c(failures, message)
}
near <- function(observed, expected, tolerance = 1e-10) {
  length(observed) == length(expected) &&
    all(is.finite(observed)) &&
    max(abs(observed - expected)) <= tolerance
}

# Load the actual computational functions without executing the script's
# command-line pipeline.  This keeps the tests coupled to the released
# implementation without refactoring the validated empirical entry point.
optimizer_path <- file.path(root, "src", "scripts", "04_optimize_portfolios.R")
expressions <- parse(optimizer_path)
function_names <- c(
  "meanvariance_solver", "small_position_solver", "bs_price", "implied_vol",
  "option_return_matrix", "scenario_returns", "realized_option_returns",
  "margin_satisfied"
)
method_environment <- new.env(parent = globalenv())
for (expression in expressions) {
  if (is.call(expression) && identical(expression[[1L]], as.name("<-")) &&
      is.symbol(expression[[2L]]) && as.character(expression[[2L]]) %in% function_names) {
    eval(expression, envir = method_environment)
  }
}
missing_functions <- function_names[!vapply(
  function_names,
  exists,
  FUN.VALUE = logical(1L),
  envir = method_environment,
  inherits = FALSE
)]
check(!length(missing_functions), paste("Could not load method functions:", paste(missing_functions, collapse = ", ")))

if (!length(missing_functions)) {
  with(method_environment, {
    # Closed-form small-position portfolio: only positive expected returns
    # receive weight and the Euclidean position constraint binds exactly.
    small <- small_position_solver(c(3, -1, 4, 0), leverage = 0.1, d = 2)
    expected_small <- c(0.1 / sqrt(2) * 3 / 5, 0, 0.1 / sqrt(2) * 4 / 5, 0)
    check(near(small[1:4], expected_small), "Small-position weights do not match the analytical formula.")
    check(
      abs(sum(small[1:4]^2) - 0.1^2 / 2) <= 1e-12,
      "Small-position portfolio does not bind the Euclidean limit."
    )
    check(abs(small[[5L]] - (1 - sum(expected_small))) <= 1e-12, "Small-position cash weight is incorrect.")

    # One-security quadratic program: the unconstrained solution exceeds the
    # position limit, so the bisection solution must lie at the boundary.
    one_asset <- meanvariance_solver(
      meanret = 1,
      covret = matrix(1, 1, 1),
      gamma = 1,
      leverage = 0.2,
      d = 1
    )
    check(abs(one_asset[[1L]] - 0.2) <= 3e-6, "One-asset quadratic solution misses the position boundary.")
    check(abs(sum(one_asset) - 1) <= 1e-12, "Quadratic-program cash weight does not complete the budget.")

    # The two endpoint constraints used by the solvency implementation have a
    # transparent upper-bound interpretation in this hand-solvable example.
    high <- c(-10, 0)
    low <- c(0, -5)
    constrained <- meanvariance_solver(
      meanret = c(1, 0.5),
      covret = diag(c(0.01, 0.01)),
      gamma = 1,
      leverage = 0.5,
      d = 1,
      high = high,
      low = low
    )
    risky <- constrained[1:2]
    check(all(risky >= -1e-12), "Constrained quadratic solution contains a negative enlarged-security weight.")
    check(sum(high * risky) >= -1 - 1e-10, "High-endpoint solvency constraint is violated.")
    check(sum(low * risky) >= -1 - 1e-10, "Low-endpoint solvency constraint is violated.")

    # Bid--ask option excess returns for a call with strike 100, zero rate,
    # ask 10, bid 8, and terminal index levels 90 and 110.
    option <- data.frame(
      Strike = 100,
      BestOffer = 10,
      BestBid = 8,
      MidPrice = 9,
      PriceExp = 110
    )
    return_matrix <- option_return_matrix(
      option,
      index_simulation = c(90, 110),
      is_put = FALSE,
      rate = 0,
      days = 30,
      pricing = "bid-ask"
    )
    check(near(return_matrix[1, ], c(-1, 0)), "Long-call bid--ask return formula is incorrect.")
    check(near(return_matrix[2, ], c(1, -0.25)), "Short-call bid--ask return formula is incorrect.")
    realized <- realized_option_returns(option, is_put = FALSE, rate = 0, days = 30, pricing = "bid-ask")
    check(near(realized, c(0, -0.25)), "Realized long/short option returns are incorrect.")

    # Black--Scholes pricing and inversion.
    spot <- 100
    strike <- 105
    maturity <- 0.5
    rate <- 0.03
    volatility <- 0.25
    call <- bs_price(spot, strike, maturity, rate, volatility, "C")
    put <- bs_price(spot, strike, maturity, rate, volatility, "P")
    check(
      abs(call - put - (spot - strike * exp(-rate * maturity))) <= 1e-10,
      "Black--Scholes prices violate put--call parity."
    )
    recovered <- implied_vol(spot, strike, maturity, rate, call, "C")
    check(abs(recovered - volatility) <= 1e-4, "Implied-volatility inversion does not recover the generating value.")

    # Transparent two-option margin example.
    margin_options <- data.frame(
      MidPrice = c(9, 9),
      BestOffer = c(10, 10),
      BestBid = c(8, 8)
    )
    margin_context <- list(theoretical = matrix(c(12, 4, 8, 12), nrow = 2, byrow = TRUE))
    margin <- margin_satisfied(c(0.2, -0.1, 0.9), margin_options, margin_context, "bid-ask")
    check(abs(margin$margin - 0.01) <= 1e-12, "Scenario margin value is incorrect.")
    check(abs(margin$capital_required - 0.09) <= 1e-12, "Scenario capital requirement is incorrect.")
    check(isTRUE(margin$satisfied), "Feasible hand-calculated margin example was rejected.")
  })
}

if (length(failures)) {
  cat(paste(sprintf("FAIL %s", failures), collapse = "\n"), "\n")
  quit(save = "no", status = 1L)
}
cat("PASS hand-verifiable method formula tests.\n")
