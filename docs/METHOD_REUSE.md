# Method boundary and reuse

## Purpose

This repository has two related purposes:

1. provide an executable reproduction of the declared central results in
   *Options Portfolio Selection with Position Limits*; and
2. expose the computational method in enough detail that a licensed researcher
   can inspect, test, and adapt it without access to the authors' private code or
   undocumented decisions.

The first purpose fixes a specific empirical design. The second makes the
sequence of data contracts, transformations, optimization steps, and validation
checks reusable. The repository is a research workflow, not a general-purpose R
package or investment product.

## Reusable workflow

The following layers are designed to be inspected or adapted independently:

| Layer | Reusable content | Contract or test |
|---|---|---|
| Vendor export | Explicit columns, date bounds, identifiers, and filenames for three OptionMetrics extracts | `expected/raw_input_contract.csv` and `src/scripts/00_verify_inputs.R` |
| Monthly option sample | Deterministic exclusion of SPXW records, monthly-expiration selection, Saturday adjustment, curve matching, and underlying-price attachment | `src/scripts/01_build_step1.R` and Step 1 fingerprints |
| Option filtering | Consolidated parity, quote-quality, and option-universe rules | `src/scripts/02_filter_options.R` and exact retained-row checks |
| Auxiliary reconstruction | Public-source retrieval, historical index returns, and expanding-window volatility forecasts | `src/scripts/acquire_auxiliary_data.R`, `src/scripts/03_build_auxiliary_inputs.R`, and source/build reports |
| Forecast attachment | Date-keyed attachment of rebuilt return and volatility forecasts | `src/scripts/03_attach_forecasts.R` and completeness checks |
| Portfolio calculation | Position-limited quadratic optimization, optional solvency restrictions, alternative pricing, and the analytical small-limit calculation | `src/scripts/04_optimize_portfolios.R` and post-solution constraint checks |
| Research outputs | Performance, utility, margin, position, summary, and wealth calculations | `src/scripts/05_generate_outputs.R` and paper-value comparisons |
| Validation | Schema, fingerprint, selection, constraint, and numerical checks with explicit tolerances | `src/scripts/06_validate_release.R`, `tests/`, and the synthetic fixture |

The deterministic synthetic mode exercises these layers without using or
approximating any licensed observation. It is the public integration example for
extensions to the workflow.

## Fixed JEF replication profile

The initial release deliberately fixes the following features of the empirical
application:

- OptionMetrics SecurityIDs for SPX, NDX, DJX, and RUT;
- the paper's historical date coverage and monthly timing convention;
- the SPX, NDX, and DJX portfolio configurations reported in the current exhibit
  manifest;
- the paper's formulas for rebuilding historical returns and volatility forecasts
  from the documented source series;
- the paper's risk-aversion values, position limits, pricing conventions, and
  solvency specifications; and
- the expected cells, fingerprints, and numerical tolerances used for release
  validation.

These choices are part of the replication target, not universal defaults. The
exact covered exhibits are listed in `docs/COVERAGE.md`. A successful run does
not imply coverage of an exhibit marked as planned.

## Adapting the method

A researcher applying the workflow to another index, period, vendor vintage, or
forecasting model must make the corresponding empirical choices explicit and
must create new validation targets. At minimum, an adaptation should:

1. replace the security map and date bounds in the extraction contract;
2. confirm the relevant monthly-expiration and settlement conventions;
3. document the source and timing of underlying prices, forecasts, and interest
   rates;
4. state all filtering and portfolio parameters rather than inheriting the JEF
   values silently;
5. add a synthetic or otherwise distributable fixture that exercises any new
   branch; and
6. replace the paper-specific expected values with independently reviewed
   validation criteria.

The current command-line interface is optimized for the fixed JEF profile. Code
changes needed for a materially different application should be released as a
new version and must pass the complete public test suite. They should not be
described as reproducing the JEF results unless the unchanged paper profile also
continues to pass.

## Claims supported by each run mode

| Run | Supported conclusion | Unsupported conclusion |
|---|---|---|
| `--synthetic` | The public code path executes and its deliberately exercised decisions and numerical checkpoints pass | The paper's estimates or economic conclusions have been reproduced |
| `paper-vintage` | The archived OptionMetrics inputs and declared paper results satisfy the reproduction policy, subject to the recorded public-source vintage | A later public-source retrieval is byte-identical to the authors' historical auxiliary files |
| `current-vintage` | The documented method has been applied to the user's current licensed export and a recorded current auxiliary retrieval | Any difference from the paper is a software error, or the current run is an exact historical reproduction |

This distinction must be preserved in documentation, reports, and derivative
work.
