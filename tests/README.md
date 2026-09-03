# Validation tests

Run the public, data-free checks with:

```text
Rscript tests/run_tests.R
```

These checks parse every R source file, verify the distributed Oxford-Man subset
by SHA-256, confirm that source-retrieved auxiliary files remain outside Git,
validate the machine-readable OptionMetrics input contract, confirm that
every covered exhibit has a paper-value target, exercise BOM-safe CSV reading
and platform-neutral Step 1 fingerprints, execute hand-verifiable tests of the
portfolio, return, pricing, and margin formulas, and run the public-source leak checks.
They also scan the exact Git index, reachable history, and any unreachable
local blobs for OptionMetrics rows, raw schemas, credentials, personal paths,
archives, and opaque binary content.

The generated end-to-end integration test can be run without licensed inputs:

```text
Rscript reproduce.R --synthetic --cores 2
```

It exercises the core raw-data-to-optimizer path and compares nine deterministic
numerical checkpoints. The fixture is non-empirical and does not test agreement
with the paper's estimates. The continuous-integration workflow runs both test
suites on Windows and Linux. Passing continuous integration demonstrates public
code-path portability; it does not replace the licensed-data clean-room run.

The complete numerical tests run automatically at the end of `reproduce.R`.
They compare generated returns, weights, table cells, margin decisions, and
wealth-series endpoints with the targets in `expected/` under the explicit rules
in `docs/REPRODUCTION_POLICY.md`. A command that fails any required comparison
exits with a nonzero status.

Continuous integration deliberately does not depend on live Yahoo, CRAN, or FRED
availability. The clean-machine release test must exercise the live acquisition
stage and retain its aggregate `work/auxiliary/` reports outside the public tree.
