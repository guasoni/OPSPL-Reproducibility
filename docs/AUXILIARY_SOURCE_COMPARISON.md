# Auxiliary-source comparison

## Decision

The public workflow uses a pinned CRAN `stevedata` DJIA series and FRED
`VXDCLS`, rather than redistributing the authors' Bloomberg-era compilation.
The comparison was performed on 2026-09-02 against the archived series and then
propagated through the DJX forecast and all 18 DJX portfolio configurations.

This is a source-current reconstruction. It is sufficiently close for the
paper's economic and numerical conclusions under the declared validation
tolerances, but it is not byte-identical to the authors' historical source
download.

## DJIA candidates

The selected `stevedata` 1.8.0 series overlaps the archived daily DJIA on 23,713
S&P-calendar dates. Its correlation with the archive is 0.99999999899. The
median absolute level difference is zero, the 95th percentile is 0.01 index
point, the 99th percentile is 0.10 point, and the maximum is 20.01 points.

For the 23,443 rolling 21-trading-day returns used by the paper, the median
absolute difference is below `3e-16`, the 95th percentile is `6.08e-6`, the 99th
percentile is `7.55e-4`, and the maximum is `0.03110`. Every required return is
available. Across the 300 option dates, the largest changes to the expanding
historical annualized mean and standard deviation inputs are `3.38e-7` and
`1.77e-6`, respectively.

MeasuringWorth was tested independently on the same 23,713 dates. It has an
explicit non-profit educational-use statement and excellent overall agreement,
but contains several apparent transcription errors. Its maximum daily level
difference is 360 points; its maximum 21-day return difference is `0.05103`.
Those sparse errors have a larger effect on the expanding volatility regressions,
so MeasuringWorth is documented as a cross-check rather than used by the
pipeline.

## VXD

FRED `VXDCLS` overlaps the archive on 5,950 finite observations from 1997-10-07
through 2021-05-28. The median, 90th-percentile, and 95th-percentile absolute
differences are all zero; the 99th percentile is 0.2304 volatility point. The
correlation is 0.99945.

The nonzero differences are not random noise. From approximately 2006-05-01
through 2006-07-03, the archived compilation is shifted forward by one trading
day. Current FRED values agree with the official Cboe overlap beginning in 2009,
and a few isolated archive anomalies remain thereafter. Of the 300 option dates,
only four have a nonzero archived-versus-FRED VXD predictor difference:

| Option date | Absolute VXD difference |
|---|---:|
| 2006-04-24 | 0.07 |
| 2006-05-22 | 1.20 |
| 2006-06-19 | 0.52 |
| 2019-09-23 | 1.09 |

The official Cboe CSV is not used directly because its history currently begins
on 2009-09-18 and therefore omits the first twelve years required by the study.

## Downstream effect

Rebuilding all three volatility forecasts from the downloadable sources exactly
reproduces the archived SPX and NDX forecasts to numerical precision (maximum
absolute differences `2.20e-12` and `1.19e-12` in volatility points). The DJX
forecast has a median absolute difference of 0.00639 point, a 95th percentile of
0.03404 point, a 99th percentile of 0.08143 point, and a maximum of 0.87413
point. The FRED VXD corrections account for almost all of this difference.

The reconstructed sources were then run through all 279 DJX portfolio dates,
nine position-limit/risk-aversion configurations, and both the unconstrained and
solvency panels:

- no zero/nonzero portfolio-return decision changed;
- no margin or solvency decision changed;
- the maximum final-weight difference was `4.85e-6`;
- the maximum realized-position difference was `0.00406`;
- mean absolute monthly-return differences were below `8.5e-5` in both panels;
- the largest monthly-return difference was `0.00967`, localized to a corrected
  VXD predictor date; and
- annualized means, volatilities, alphas, and hedged volatilities changed by at
  most 0.0191 percentage point, while Sharpe, beta, and appraisal ratios changed
  by at most 0.00396.

Some reported DJX cells therefore cross a two-decimal rounding boundary. The
source substitution itself changes percentage statistics by no more than 0.0191
point and ratios by no more than 0.00397. When these changes are combined with
the accepted run's pre-existing distance from rounded paper entries, four cells
slightly exceed the general `0.02`/`0.005` limits: the largest total distances
from a printed value are 0.02202 percentage point and 0.00635 ratio unit. The
source-current DJX profile therefore declares narrow ceilings of `0.025` and
`0.007`; no other panel receives them.

| DJX panel | Position limit | Risk aversion | Statistic | Paper | Source-current | Absolute difference |
|---|---:|---:|---|---:|---:|---:|
| Solvency | 2% | 3 | Appraisal ratio | 0.28 | 0.27366 | 0.00634 |
| Solvency | 2% | 5 | Alpha (%) | 1.71 | 1.68828 | 0.02172 |
| Solvency | 2% | 5 | Mean return (%) | 3.04 | 3.01798 | 0.02202 |
| Solvency | 3% | 5 | Appraisal ratio | 0.21 | 0.21592 | 0.00592 |

The maximum effective-position table difference remains 0.00451 percentage
point and no such cell changes at displayed precision. The largest relative
wealth-endpoint difference is 0.394%, below the existing 0.5% ceiling. The
portfolio decisions and conclusions are unchanged. Each run records the freshly
acquired input fingerprints so that a later source revision can be distinguished
from a code change.
