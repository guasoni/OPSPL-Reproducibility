# Mathematical and computational method specification

## Authority and scope

This document states the method implemented by the repository and maps each
definition to executable R code. The mathematical definitions in the final
*Journal of Empirical Finance* article, *Options Portfolio Selection with
Position Limits*, have substantive priority. This specification records how
those definitions are operationalized. A discrepancy must be reported and
resolved in favor of the mathematical definition; it must not be treated as an
undocumented implementation choice.

The fixed JEF profile uses monthly European index options on SPX, NDX, and DJX
from 1996--2020 (DJX begins in 1997). RUT is constructed in Step 1 as a data-
processing check but is not optimized in the currently covered release. Exact
exhibit coverage is in [`COVERAGE.md`](COVERAGE.md).

## Notation and timing

For a decision date (t) and the selected subsequent expiration (T):

- (S_t) is the index level used for pricing at the decision date;
- (S_T) is the relevant closing or settlement index value at expiration;
- (K_j) is the strike of option contract (j);
- (a_j) and (b_j) are its ask and bid premia;
- (r_{t,T}) is the continuously compounded zero-curve rate, in decimals;
- \(\Delta=(T-t)/360\) is the option-cycle year fraction;
- (d) is the number of distinct contracts available on that date;
- (R_i\in\mathbb R^{2d}) is an enlarged long--short option-return scenario;
- \(\mu\) and \(\Sigma\) are the scenario mean vector and covariance matrix;
- \(\bar w\in\mathbb R^{2d}\) contains nonnegative premium weights, alternating
  long and short positions for each contract;
- \(\gamma\in\{1,3,5\}\) is risk aversion; and
- \(L\in\{0.02,0.03,0.05\}\) is the position-limit parameter.

The cash weight is (1-\mathbf 1^\top\bar w). The signed weight of contract
(j) is (w_j=\bar w_{2j-1}-\bar w_{2j}), and reported effective option
exposure is \(\sum_j|w_j|\).

## 1. Licensed input contract

Users supply three CSV exports from their own OptionMetrics license:

1. option quotes from `OPTION_PRICE_VIEW`;
2. underlying index prices from `SECURITY_PRICE`; and
3. all zero-curve maturities from `ZERO_CURVE`.

The exact filenames, 23-column option schema, four SecurityIDs, date bounds,
and SQL-equivalent selection are in [`DATA_EXTRACTION.md`](DATA_EXTRACTION.md),
[`../expected/raw_input_contract.csv`](../expected/raw_input_contract.csv), and
[`../sql/optionmetrics_extract.sql`](../sql/optionmetrics_extract.sql). No
OptionMetrics observation or row-level derivative is distributed.

Implementation: [`../src/scripts/00_verify_inputs.R`](../src/scripts/00_verify_inputs.R)
and [`../src/scripts/01_build_step1.R`](../src/scripts/01_build_step1.R).

## 2. Monthly option sample (Step 1)

The 9.2 GB paper-vintage option file is processed in two bounded-memory passes.

1. Remove symbols containing `SPXW`; weekly PM-settled contracts are not mixed
   with the monthly AM-settled SPX sample.
2. Move a Saturday expiration to the preceding Friday.
3. For each SecurityID and expiration, sum volume across all quote rows. If any
   contributing volume is missing, the aggregate is treated as missing.
4. Within each SecurityID and calendar expiration month, select the expiration
   with maximum nonmissing total volume. The paper-vintage data have no ties.
5. For each selected expiration after the first, use the first available quote
   date strictly after the preceding selected expiration as its decision date.
6. Retain every quote at the selected SecurityID--expiration--decision-date
   combination.
7. Attach the decision-date index close and the expiration close. If the close
   is unavailable on the nominal expiration, search the preceding two calendar
   days. The final January 2021 supplemental closes are rounded to their quoted
   two-decimal precision before use.
8. For each decision date, select the available zero-curve node whose maturity
   date is closest to expiration; do not interpolate.
9. Remove observations with missing implied volatility or the vendor sentinel
   `-99.99`. When duplicated contract rows remain, keep the row with the highest
   bid.

The simple annualized rate written to Step 1 is

\[
r^{\mathrm{simple}}_{t,T}
=\frac{e^{r_{t,T}\Delta}-1}{\Delta}.
\]

Step 1 records input fingerprints, selection counts, missing-value counts, row
counts, and platform-neutral canonical content fingerprints. Numeric fields in
the canonical fingerprint are represented to ten decimal places; this is much
tighter than every downstream reproduction tolerance but removes immaterial
cross-platform differences around (10^{-13}).

Implementation: [`../src/scripts/01_build_step1.R`](../src/scripts/01_build_step1.R).

## 3. Quote and put--call-parity filter (Step 2)

Only contracts with a strictly positive bid are eligible. There is no separate
screen for bid above ask, trading volume, or open interest.

For a same-date, same-strike put--call pair, let (D_{t,T}) denote the dividend
adjustment inferred from the difference between the total return on the tracking
ETF and the price return on the index. The individual parity interval is

\[
\begin{aligned}
\mathrm{Low}_{K,t}&=K e^{-r_{t,T}\Delta}+C_{\mathrm{bid}}-P_{\mathrm{ask}}+D_{t,T},\\
\mathrm{Up}_{K,t}&=K e^{-r_{t,T}\Delta}+C_{\mathrm{ask}}-P_{\mathrm{bid}}+D_{t,T}.
\end{aligned}
\]

Pairs with \(\mathrm{Low}_{K,t}\ge\mathrm{Up}_{K,t}\) do not contribute to the
joint interval. Across valid pairs,

\[
\mathrm{Low}_t=\max_K\mathrm{Low}_{K,t},\qquad
\mathrm{Up}_t=\min_K\mathrm{Up}_{K,t}.
\]

If the observed index is inside this interval, it is retained. If it is outside
a nonempty interval, the midpoint is used. If the joint interval is empty, the
strikes attaining its extreme bounds are removed iteratively using the fixed
index-specific deletion limits in the code. All deletions and adjustments are
reported.

Implementation: [`../src/scripts/02_filter_options.R`](../src/scripts/02_filter_options.R).

## 4. Public auxiliary series and volatility forecasts

The repository retrieves Yahoo price histories, a checksum-pinned CRAN archive
containing the long DJIA history, and FRED `VXDCLS`. The discontinued Oxford-Man
five-minute realized-volatility subset needed by the estimator is distributed
with provenance. Source details and date bounds are in
[`DATA_SOURCES.md`](DATA_SOURCES.md).

At each decision date, the log-volatility model is estimated using only
information available before that date:

\[
\log\sigma_{t,T}=\log\alpha+
\beta_{\mathrm{imp}}\log\sigma^{\mathrm{imp}}_t+
\beta_{\mathrm{hist}}\log\sigma^{\mathrm{hist}}_t+\varepsilon_{t,T}.
\]

If \(\hat\sigma_{t,T}\) is the exponentiated fitted value and
\(s_\varepsilon^2\) is the estimated residual variance, the variance-unbiased
forecast used by the optimizer is

\[
\widetilde\sigma_{t,T}=\hat\sigma_{t,T}e^{s_\varepsilon^2}.
\]

Historical volatility uses the Oxford-Man series once the corresponding history
is available and otherwise uses daily returns over the previous monthly block.
VIX is used to fill the early VXN and VXD histories through fixed, documented
overlap regressions. NDX return history is extended backward with the Nasdaq
Composite using its overlap regression. Business days are counted directly
between the decision and expiration dates.

Implementation:
[`../src/scripts/acquire_auxiliary_data.R`](../src/scripts/acquire_auxiliary_data.R)
and
[`../src/scripts/03_build_auxiliary_inputs.R`](../src/scripts/03_build_auxiliary_inputs.R).

## 5. Empirical return scenarios

At date (t), take every 21-business-day index return observed strictly before
the decision date. If \(\bar\mu_t\) and \(\bar\sigma_t\) are the mean and
standard deviation estimated from that available history, standardize the
historical observations and rescale them to the forecast volatility and length
of the next option cycle. In paper notation,

\[
\widetilde R_i=\frac{R_i-\bar\mu_t\Delta_i}
{\bar\sigma_t\sqrt{\Delta_i}},\qquad
\widehat R_i=\widetilde R_i\widetilde\sigma_{t,T}\sqrt\Delta+
\bar\mu_t\Delta.
\]

Each rescaled observation receives equal probability and implies a terminal
level (S_i^T=S_t(1+\widehat R_i)).

For a call, the long and short excess returns are

\[
R^{C+}_i=\frac{(S_i^T-K)_+-a e^{r\Delta}}{a},\qquad
R^{C-}_i=\frac{-(S_i^T-K)_++b e^{r\Delta}}{b}.
\]

For a put, replace \((S_i^T-K)_+\) with \((K-S_i^T)_+\). Long positions enter
at the ask and short positions at the bid. Midprice robustness replaces both
premia with \((a+b)/2\). Stacking long and short returns for every put and call
produces the scenario matrix, \(\mu\), and \(\Sigma\).

Implementation: [`../src/scripts/04_optimize_portfolios.R`](../src/scripts/04_optimize_portfolios.R),
functions `option_return_matrix`, `scenario_returns`, and `realized_option_returns`.

## 6. Position-limited portfolio

The baseline enlarged-security problem is

\[
\max_{\bar w\in\mathbb R^{2d}}
\left\{\bar w^\top\mu-\frac\gamma2\bar w^\top\Sigma\bar w:
\bar w\ge0,\ \bar w^\top\bar w\le\frac{L^2}{d}\right\}.
\]

For a given multiplier \(\lambda\), the numerical quadratic program maximizes

\[
\bar w^\top\mu-
\frac12\bar w^\top(\gamma\Sigma+\lambda I)\bar w
\]

subject to the linear constraints. A binary search over \(\lambda\) targets
\(\bar w^\top\bar w=L^2/d\), with the fixed bounds, iteration limit, and
tolerance in the implementation. `quadprog::solve.QP` receives
`Dmat = gamma * covariance + lambda * I` and `dvec = mean_return`.

The first-order small-position portfolio is

\[
\bar w_L=\frac{L}{\sqrt d}\frac{\mu_+}{\|\mu_+\|_2},
\qquad (\mu_+)_j=\max(\mu_j,0),
\]

with an all-cash portfolio if every expected return is nonpositive.

Implementation: [`../src/scripts/04_optimize_portfolios.R`](../src/scripts/04_optimize_portfolios.R),
functions `meanvariance_solver` and `small_position_solver`.

## 7. Solvency restriction

The solvency specification adds

\[
\bar w^\top R_i\ge-1\quad\text{for every in-sample scenario }i.
\]

Because only the minimum and maximum simulated index levels bind in the audited
application, those two endpoint constraints are imposed in the quadratic
program. The resulting portfolio is then checked against every scenario. The
run stops if any option-portfolio scenario return is below \(-1-10^{-8}\).

Implementation: [`../src/scripts/04_optimize_portfolios.R`](../src/scripts/04_optimize_portfolios.R),
`mode = "solvency"` and the post-solution all-scenario check.

## 8. Margin diagnostic and cash screen

For SPX, a TIMS-style diagnostic combines ten index shocks from -8% to +6% with
three at-the-money volatility multipliers, 0.25, 1, and 1.75. Options are repriced
with Black--Scholes. For signed weights (w_j), scenario value relative to the
initial trading premium is

\[
V(x,v)=\sum_j w_j\frac{P_j(x,v)}{P_j^0}.
\]

The margin value is \(m(w)=\min_{x,v}V(x,v)\), and the implementation's capital
requirement is

\[
\mathcal C(w)=\sum_j w_j-m(w).
\]

A portfolio is feasible when \(\mathcal C(w)\le1\). For the standard and
solvency SPX panels, an infeasible proposed option portfolio is replaced by the
all-cash portfolio for that realized month. The analytical small-position panel
reports margin only as a diagnostic and is not cash-screened.

Implementation: [`../src/scripts/04_optimize_portfolios.R`](../src/scripts/04_optimize_portfolios.R),
functions `strike_volatilities`, `build_margin_context`, and `margin_satisfied`.

## 9. Out-of-sample returns and reported statistics

The portfolio selected using information before (t) is evaluated at the
observed expiration value using the same long-ask and short-bid return formulas.
The index excess return is

\[
R^{\mathrm{index}}_{t,T}=\frac{S_T-S_t}{S_t}
-r^{\mathrm{simple}}_{t,T}\Delta.
\]

The output stage calculates annualized means and volatilities, Sharpe ratios,
market-model alpha and beta, hedged volatility and appraisal ratios, equivalent
safe rates, margin frequencies, effective positions, subperiod results, and
wealth paths. Each covered statistic is compared with a fixed paper target under
the rules in [`REPRODUCTION_POLICY.md`](REPRODUCTION_POLICY.md).

Implementation: [`../src/scripts/05_generate_outputs.R`](../src/scripts/05_generate_outputs.R)
and [`../src/scripts/06_validate_release.R`](../src/scripts/06_validate_release.R).

## 10. Validation hierarchy

Validation is deliberately layered:

1. schemas, filenames, dates, and input fingerprints;
2. Step 1 row counts and canonical content fingerprints;
3. source acquisition and auxiliary-series provenance;
4. hand-verifiable formula tests;
5. a deterministic synthetic raw-data-to-optimizer integration test;
6. post-solution nonnegativity, norm, margin, and all-scenario solvency checks;
7. covered paper cells and wealth endpoints under declared tolerances; and
8. a strict Git-tree and history audit excluding proprietary rows and paths.

Run the data-free layers with `Rscript tests/run_tests.R` and the public
integration layer with `Rscript reproduce.R --synthetic --cores 2`.
