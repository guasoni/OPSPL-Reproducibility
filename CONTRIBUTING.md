# Contributing

Corrections that improve reproducibility, portability, documentation, or test
coverage are welcome after the initial public release. Proposed changes must
preserve the distinction between the fixed JEF replication profile and a new or
adapted empirical application.

## Never share licensed data

Do not commit, upload, paste, or attach any OptionMetrics observation or
row-level derivative. This prohibition applies to commits, branches, pull
requests, issues, discussion posts, screenshots, logs, and release assets.
Do not commit the Yahoo, CRAN DJIA, FRED VXD, or derived files created under
`work/auxiliary/`; preserve the user-side retrieval boundary.

When reporting a problem involving licensed inputs, provide only the failing
check, file schema, aggregate dimensions, cryptographic fingerprint, software
environment, and the smallest synthetic example capable of demonstrating the
problem. Remove personal paths and credentials from all output.

## Checks for a proposed change

Run from the repository root:

```text
Rscript tests/run_tests.R
Rscript reproduce.R --synthetic --cores 2
```

Changes affecting paper outputs, input contracts, filters, forecasts,
optimization, or numerical tolerances also require the relevant licensed-data
validation and a new reviewed release record. Expected values and tolerances
must never be regenerated merely to make a failing test pass; every change must
state its mathematical or empirical justification.

## Documentation

Document whether a change affects:

- the fixed JEF reproduction;
- the reusable workflow;
- the synthetic fixture;
- a data or software license boundary; or
- the numerical interpretation of an existing result.

All user-facing paths and commands must work from a fresh clone on a supported
64-bit R installation.
