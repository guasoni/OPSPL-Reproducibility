# Release-candidate validation record

This record summarizes the authors' full local validation on 2026-08-29. The
machine used Windows 11, R 4.3.2, `quadprog` 1.5-8, and the package versions in
`renv.lock`. Generated OptionMetrics-derived files remained under ignored local
directories throughout the audit.

## Raw data through Step 1

The R builder streamed the 9.2 GB, 50,490,867-row paper-vintage option dump in
two bounded-memory passes. It selected 1,194 security-expiration pairs across
304 expirations. On the authors' Windows workstation the resulting files were
byte-identical to all four archived paper inputs:

| File | Rows | Result |
|---|---:|---|
| `SPXfinal.csv` | 69,835 | SHA-256 exact |
| `NDXfinal.csv` | 53,527 | SHA-256 exact |
| `DJXfinal.csv` | 25,455 | SHA-256 exact |
| `RUTfinal.csv` | 40,279 | SHA-256 exact |

The legacy byte hashes and platform-neutral canonical table hashes are both in
`expected/step1_paper_vintage_fingerprints.csv`; raw-input hashes are in
`expected/paper_vintage_raw_fingerprints.csv`. The canonical hashes are the
release gate. They normalize CSV syntax and represent numeric fields to ten
decimal places, which removes operating-system serialization differences while
remaining substantially stricter than the downstream numerical tolerances.

## Filtering and auxiliary-data attachment

Step 2 retained exactly the archived option rows and reproduced every non-parity-
price field exactly:

| Index | Retained rows | Maximum parity-price difference from archived Yahoo download |
|---|---:|---:|
| SPX | 61,497 | 0.001946 index points |
| NDX | 45,880 | 0.006204 index points |
| DJX | 18,761 | 0.000276 index points |

These small differences arose from the audited current Yahoo retrieval rather
than an unavailable byte copy of the authors' original download. The release
workflow now retrieves those observations itself and records their run-specific
fingerprint.

On 2026-09-02, the new R auxiliary stage downloaded all ten Yahoo series, the
checksum-pinned `stevedata` 1.8.0 DJIA history, and FRED `VXDCLS`, and rebuilt
the 23,443-row return history and all 300 volatility forecasts. SPX and NDX
forecasts matched the archived outputs within `2.20e-12`; the DJX source-current
differences and their full portfolio effects passed the source-specific policy
in `docs/AUXILIARY_SOURCE_COMPARISON.md`. No selection, margin, or solvency
decision changed.

## Portfolio calculations

The author-side R validator compared the clean outputs with both the archived
original output set and the repaired audit output set. All 16 required return,
final-weight, index-return, and small-limit comparisons passed.

- Index excess-return series were exact for SPX, NDX, and DJX.
- Zero/nonzero and no-trade decisions were exact for every main and solvency
  return matrix.
- The two documented one-cell return exceptions remained below `5e-4`; all
  other main and solvency return differences remained below `2e-4`.
- The largest final-weight difference against the archived outputs was below
  `3.1e-7`; SPX and DJX final weights were effectively exact.
- SPX small-limit returns differed from the audited clean output by at most
  `2.89e-6`, and its three final-weight columns differed by less than `1e-15`.
- Every in-sample scenario passed the post-solution solvency check.

The canonical 12-worker runs took approximately 24.4 minutes for SPX
unconstrained, 19.9 minutes for the corrected SPX midprice specification,
11.6 minutes for NDX solvency, 23.7 minutes for SPX solvency, and 0.9 minutes
for the SPX analytical small-limit panel on the authors' workstation.
Runtime is not part of the numerical acceptance criterion.

## Covered paper outputs

| Validation group | Cells/endpoints | Exact printed-rounding matches | Policy failures |
|---|---:|---:|---:|
| Main and small-limit performance | 399 | 396 | 0 |
| Corrected SPX midprice robustness | 63 | 63 | 0 |
| Corrected Table 4.5 | 63 | 63 | 0 |
| SPX margin percentages | 18 | 18 | 0 |
| Cross-index option summary | 12 | 12 | 0 |
| SPX five-year panels | 330 | 327 | 0 |
| Effective positions | 108 | 108 | 0 |
| Wealth-figure endpoints | 21 | not a printed-cell test | 0 |

The six printed-rounding boundary crossings differ from the paper by at most
0.0075 displayed percentage points, below the declared 0.02-point tolerance.
The maximum relative difference among the 21 wealth endpoints is
`1.31e-5`. Every comparison CSV records the paper value, computed value, exact
rounding flag, numerical tolerance, and policy result.

The machine-readable summary is generated locally as
`outputs/tables/table_validation_summary.json`. It reports
`generation_complete = true`, `paper_value_pass = true`, and
`pipeline_pass = true` for this run.

## Synthetic integration fixture

On 2026-09-02, the exact documented command
`Rscript reproduce.R --synthetic --cores 2` restored the locked environment,
regenerated the fixture from an empty `work/synthetic` directory, and completed
all eight optimizer runs. All 46 structural, integrity, constraint, and numerical
checks passed. The nine numerical regression checkpoints had a maximum absolute
error of `4.27e-14` relative to their stored values.

This test establishes that the public code path operates without proprietary
data. Because the fixture is non-empirical, it is not evidence that the paper's
reported estimates can be recovered without the licensed OptionMetrics exports.

## Separate-machine reproduction

On 2026-09-02--03, the complete licensed-data workflow was run from a clean clone
on a separate Windows/WSL2 computer using the pinned R 4.3.2 container. The run
took 2 hours 51 minutes and completed every covered optimization. All paper-value
groups passed the declared numerical policy, the synthetic fixture passed all 46
checks, and the proprietary-data audit passed all 13 checks.

The run exposed portability issues that were corrected before release and added
to the public regression suite. A second complete licensed-data optimization was
not performed after those corrections. The concise scope, outcome, and resulting
qualification are recorded in [`CLEAN_MACHINE_REPORT.md`](CLEAN_MACHINE_REPORT.md).
