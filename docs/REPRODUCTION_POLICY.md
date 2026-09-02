# Reproduction policy

## Numerical standard

A paper-vintage run passes when:

1. every generated paper statistic either equals the final paper after rounding
   to its displayed precision or lies within the explicitly recorded numerical
   tolerance for that kind of cell;
2. unrounded monthly returns and final weights remain within the documented
   numerical tolerances; and
3. discrete decisions—option-row retention, no-trade months, margin feasibility,
   and solvency feasibility—match exactly unless a specifically diagnosed data-
   vintage difference is reported.

Byte-identical floating-point CSVs are not required across operating systems.
Figure PDFs need the same data, scales, labels, and economic content; identical
font rasterization or PDF bytes are not required.

## Current tolerances

- Step 1 paper-vintage files: byte-identical under the locked R workflow, checked
  against the four SHA-256 fingerprints in
  `expected/step1_paper_vintage_fingerprints.csv`; the independent audit also
  confirmed all imported cells at tolerance `1e-12`.
- Step 2 row selection: exact.
- Step 2 parity-implied index levels from the source-current Yahoo retrieval:
  differences from the authors' archived download are recorded and propagated.
- Monthly portfolio returns and final weights: absolute tolerance `2e-4`, subject
  to two separately diagnosed `5e-4` return exceptions: the SPX bisection cell
  at July 2012, 5% limit, gamma 1; and the DJX solvency cell at February 2013,
  5% limit, gamma 1, caused by propagation of the source-current Yahoo parity
  level. Both retain exact zero/nonzero decisions and a whole-file mean absolute
  difference below `1e-6`.
- For the DJX source-current auxiliary reconstruction only, monthly portfolio
  returns have a diagnosed absolute ceiling of `0.01`, a whole-matrix mean
  absolute difference below `1e-4`, final-weight differences below `5e-6`, and
  exact zero/nonzero, margin, and solvency decisions. This narrow exception
  reflects four corrected FRED VXD predictor dates and is not applied to SPX,
  NDX, or other data changes. See `docs/AUXILIARY_SOURCE_COMPARISON.md`.
- Wealth-figure endpoints: maximum relative difference `0.5%` from the audited
  paper-vintage series. This allows documented public-source revisions to
  propagate without permitting an economically different figure.
- Annualized mean, volatility, alpha, residual-volatility, equivalent-rate, and
  effective-position cells: `0.02` in their displayed percentage-point units.
- Sharpe, beta, and appraisal-ratio cells: `0.005` in displayed ratio units.
- For DJX unconstrained and solvency performance cells under the explicitly
  labelled `source-current` auxiliary mode, the corresponding ceilings are
  `0.025` percentage point and `0.007` ratio unit. Four cells require this narrow
  allowance after the FRED corrections are combined with pre-existing
  printed-rounding differences; the observed maxima are `0.02202` and `0.00635`.
- Margin-feasibility percentages and other discrete decisions: exact underlying
  decisions and equality after final-paper rounding.
- Every comparison file retains both the exact printed-rounding flag and the
  numerical-policy flag, so the tolerance never conceals a boundary crossing.

No blanket “close enough” rule is permitted. Every exception must identify the
cell, raw difference, source, and effect on the displayed paper value.

## Data modes

`paper-vintage` records and checks the authors' historical OptionMetrics file
fingerprint and benchmark counts. `current-vintage` applies the identical code
and selection rules to a current vendor extraction. This OptionMetrics choice is
separate from the public auxiliary-source vintage: the distributed workflow
retrieves Yahoo and FRED at run time and pins the CRAN DJIA archive. Historical
vendor or public-source revisions are reported as provenance differences and are
not treated as code failures when the source-specific policy above passes.
