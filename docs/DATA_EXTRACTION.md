# OptionMetrics extraction and input contract

## Objective

The first raw file is the documented equivalent of the authors'
`option_price_view_indices_2020.csv`. The original local SQL contained
`SELECT * FROM IvyDB.dbo.OPTION_PRICE_VIEW` with the four SecurityIDs and no date
condition. The authors' dump ended on 2020-12-31 because of its database vintage.
This package makes that endpoint explicit.

## Required files

Run the three statements in `sql/optionmetrics_extract.sql` separately and save
the results with these exact names:

| Configuration field | Required filename | Requested dates | Source object |
|---|---|---|---|
| `option_prices` | `option_price_view_indices_2020.csv` | 1996-01-01 through 2020-12-31 | `IvyDB.dbo.OPTION_PRICE_VIEW` |
| `security_prices` | `security_price_indices_through_2021_01.csv` | 1996-01-01 through 2021-01-31 | `IvyDB.dbo.SECURITY_PRICE` |
| `zero_curve` | `zero_curve_through_2020.csv` | 1996-01-01 through 2020-12-31 | `IvyDB.dbo.ZERO_CURVE` |

Place all three files in one directory and pass that directory to
`Rscript reproduce.R --data-dir PATH`. The machine-readable version of this
contract, including the historical fingerprints, is
`expected/raw_input_contract.csv`.

Export comma-separated UTF-8 text with a header row, decimal points, and no
thousands separators. Preserve the SQL column order. Dates may contain a time
suffix, but their first ten characters must use `YYYY-MM-DD`; database `NULL`
values may be exported as empty fields, `NA`, or `NULL`. Do not open and resave
the 9.2 GB option file in spreadsheet software.

## Option quote extract

Required SecurityIDs are SPX `108105`, RUT `102434`, DJX `102456`, and NDX
`102480`. Retain quote dates from 1996-01-01 through 2020-12-31 and do not impose
an expiration cutoff. Retain SPXW records; the monthly and weekly samples are
separated by the processing code.

The Step 1 builder expects these columns, in this order. The supplied SQL uses
an explicit column list so that the CSV contract is not affected by later
vendor additions to `OPTION_PRICE_VIEW`:

`SecurityID`, `Date`, `Symbol`, `SymbolFlag`, `Strike`, `Expiration`, `CallPut`,
`BestBid`, `BestOffer`, `LastTradeDate`, `Volume`, `OpenInterest`,
`SpecialSettlement`, `ImpliedVolatility`, `Delta`, `Gamma`, `Vega`, `Theta`,
`OptionID`, `AdjustmentFactor`, `AMSettlement`, `ContractSize`, and
`ExpiryIndicator`.

The authors' paper-vintage file contained 50,490,867 rows, 23 columns, and ended on
2020-12-31. Byte sizes and SHA-256 fingerprints for all paper-vintage raw inputs
are in `expected/paper_vintage_raw_fingerprints.csv`. These values are
diagnostics, not requirements in current-vintage mode.

## Underlying-price extract

Export `SECURITY_PRICE` for the same four SecurityIDs through 2021-01-31. The
supplied SQL emits the paper-vintage column layout and the builder uses
`SecurityID`, `Date`, and `ClosePrice`. Extending the query beyond the
option-quote endpoint is necessary: the last option block is valued using the
underlying close on 2021-01-13.

If a paper-vintage closing-price file ends on 2020-12-31, the configuration points
to the four-row supplement created under `work/auxiliary/` by the public-source
acquisition stage. That supplement is generated from Yahoo and the pinned CRAN
DJIA series; it is not distributed.

## Zero-curve extract

Export every `ZERO_CURVE` maturity for each date from 1996-01-01 through
2020-12-31. The builder requires `Date`, `Days`, and `Rate`. It selects the curve
maturity closest to the option expiration using the rule in the authors' Step 1
code.

## Vintage recording

The pipeline records the extraction mode, execution date, file size, SHA-256
fingerprint, schema, row count, date range, and SecurityID counts. A current
vendor extraction may differ from the authors' historical vintage. Such a run is
reported as a current-vintage re-estimation, not silently presented as the
paper-vintage input.

The public one-command interface defaults to `current-vintage`, because a newly
exported security-price file includes January 2021 and therefore cannot have the
same byte fingerprint as the authors' archived `closing_prices_2020.csv`. The
authors' exact archived-file mapping is retained in
`config/config.paper-vintage.example.R`; it uses the generated four-row
closing-price supplement for the final January 2021 valuation.

## Automatic validation

Before the long option-file scan begins, `src/scripts/00_verify_inputs.R` checks that
all three private files exist and that their headers match the contract. Step 1
then records each file's byte size, SHA-256, schema, row count, SecurityID counts,
and date range. In paper-vintage mode those values and all four generated Step 1
files must match the recorded fingerprints exactly. In current-vintage mode they
are retained in the run report and the downstream numerical comparisons are
still produced.
