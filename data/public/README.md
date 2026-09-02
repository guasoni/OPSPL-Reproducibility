# Auxiliary data

This directory contains the sole redistributed empirical auxiliary input:
`oxford_man_realized_5min.csv`. It is the minimum subset of the discontinued
Oxford-Man Institute Realized Library used by the paper's estimator: `rv5` and
`close_price` for `.SPX`, `.IXIC`, and `.DJI`, with dates through 2020-12-18.

`provenance.csv` records the archived source-file checksum, exact transformation,
included-file checksum, and authors' redistribution determination. The source
code's BSD 3-Clause License does not relicense this third-party dataset; the
source-provider rights and requested scholarly attribution remain in force.

Yahoo observations, the long DJIA history, FRED VXD, the January 2021 closing
levels, historical-return input, and volatility forecasts are not stored in Git.
They are downloaded or rebuilt under ignored `work/auxiliary/` by the one-command
pipeline. See `docs/DATA_SOURCES.md` and
`docs/AUXILIARY_SOURCE_COMPARISON.md`.
