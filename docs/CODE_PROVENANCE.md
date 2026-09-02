# Code provenance and audit decisions

The release code was reconstructed from the authors' private repository at commit
`e278b8587eb9ce33ba5db70049d7a21e967a5a90` and from the accepted-paper audit.
It is a clean implementation, not a fork and not a continuation of the private
repository's Git history.

## Stage mapping

| Release stage | Audited source logic | Release treatment |
|---|---|---|
| `acquire_auxiliary_data.R` | Yahoo download calls and archived Bloomberg-era inputs | Executable source boundary: Yahoo is retrieved directly, long DJIA comes from checksum-pinned CRAN `stevedata`, and VXD comes from FRED; no Bloomberg file is distributed |
| `01_build_step1.R` | `loadinR.R`; `Multiunderlying Preprocess.R` | Streaming R implementation; byte-identical across all four archived Step 1 files, with an independent `1e-12` imported-cell check |
| `02_filter_options.R` | Three index-specific Step 2 scripts | Consolidated parameterized R implementation; source-retrieved Yahoo input; exact archived row retention under the audited source vintage |
| `03_build_auxiliary_inputs.R` | `Volatility.R` and its historical-return construction | R-only reconstruction from downloaded Yahoo/DJIA/VXD series and the distributed minimum Oxford-Man subset; source-vintage differences are measured explicitly |
| `03_attach_forecasts.R` | Step 3 hand-off | Date-keyed attachment of the rebuilt business-day and volatility-forecast records |
| `04_optimize_portfolios.R` | Step 4 optimizer and repaired audit implementation | Preserves the accepted mathematical definitions and explicit numerical checks |
| `05_generate_outputs.R` | Step 5 scripts and audit table generator | R-only calculation of performance, utility rates, margins, subperiods, positions, summaries, and wealth series |

## Decisions incorporated into the release

- Margin implied volatilities use ask prices, as stated by the paper.
- Margin feasibility uses capital required `<= 1`.
- Every in-sample scenario is checked after solving the endpoint solvency
  constraints.
- The analytical small-position benchmark is not cash-screened.
- The corrected Table 4.5 implements the printed quadratic and fourth-order
  definitions.
- Numerical equality is evaluated under `docs/REPRODUCTION_POLICY.md`.

These choices are explicit in code and metadata so a reproducer does not need
private correspondence or undocumented author judgment.
