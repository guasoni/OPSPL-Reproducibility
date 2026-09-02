# Auxiliary-data sources

## Public-source boundary

The repository does not redistribute Yahoo, FRED/Cboe, CRAN DJIA, or
Bloomberg-era observations. On the first empirical run,
`src/scripts/acquire_auxiliary_data.R` retrieves the required public-source
series into ignored `work/auxiliary/`. It records retrieval time, URL, observed
date range, row count, byte size, and SHA-256 for every local result. Later runs
reuse that cache unless the user supplies `--refresh-auxiliary`.

| Local file (ignored by Git) | Role |
|---|---|
| `work/auxiliary/yahoo_daily.csv` | Yahoo index, ETF, and volatility-index observations |
| `work/auxiliary/djia_daily.csv` | Long DJIA history extracted from pinned `stevedata` |
| `work/auxiliary/vxd_daily.csv` | FRED `VXDCLS` finite observations |
| `work/auxiliary/index_closes_2021-01-13.csv` | Legacy four-index closing supplement |
| `work/auxiliary/paper_index_return_history.csv` | Rebuilt 21-trading-day return history |
| `work/auxiliary/paper_volatility_forecasts.csv` | Rebuilt 300-date forecast input |
| `work/auxiliary/acquisition_report.json` | URLs, ranges, times, and source-file fingerprints |
| `work/auxiliary/build_report.json` | Transformations and derived-file fingerprints |

This design avoids republishing market-data files while leaving users with an
executable acquisition step. Because Yahoo and FRED can revise history or alter
their interfaces, a later retrieval is a source-current reconstruction, not a
promise of byte identity with the authors' download. The numerical policy and
the measured effect of this limitation are in `docs/REPRODUCTION_POLICY.md` and
`docs/AUXILIARY_SOURCE_COMPARISON.md`.

## Yahoo Finance

The script calls Yahoo's chart endpoint
(`https://query1.finance.yahoo.com/v8/finance/chart/`) for `^GSPC`, `SPY`, `^NDX`, `^IXIC`,
`QQQ`, `^DJI`, `DIA`, `^RUT`, `^VIX`, and `^VXN`, requesting daily history from
1919-12-31 through 2021-05-31. The endpoint returns only the dates on which each
series exists; for example, the required `^GSPC` history begins on 1927-12-30.

The local schema is:

`Ticker`, `Date`, `Open`, `High`, `Low`, `Close`, `Adjusted`, `Volume`.

The option filters use index and ETF close/adjusted-close pairs to reconstruct
the paper's dividend adjustment. The forecast builder uses `^GSPC`, `^NDX`,
`^IXIC`, `^VIX`, and `^VXN`. A four-row January 2021 closing-price supplement is
also generated for the authors' legacy security-price export; current
OptionMetrics users obtain those closes directly in the required January 2021
vendor extract.

Yahoo source terms continue to govern the user's retrieval. The file and all
derived source caches are ignored by Git.

## Long DJIA history

Yahoo's current `^DJI` download begins in 1992, too late to reconstruct the
paper's historical return distribution. The pipeline therefore retrieves the
`DJIA` data object from [CRAN package `stevedata`](https://cran.r-project.org/package=stevedata)
version 1.8.0. That object covers
1885 onward; the local pipeline retains 1927-01-03 through 2021-05-28. The
package documentation identifies MeasuringWorth, Pinnacle Systems, and Yahoo as
the component historical sources.

The exact CRAN source archive is pinned by both version and SHA-256:

`042bf29bfc46e86d7f3fe3bb0427397660dfe5f71122f87b69bf96072fed0380`.

The downloader first tries the current CRAN source directory and then CRAN's
version archive. It refuses to use a file with any other checksum, extracts only
`data/DJIA.rda`, and writes `Date,DJI` under `work/auxiliary/`. The repository
does not redistribute the package data. CRAN records `stevedata` under GPL-2.
The two attempted source URLs are
`https://cran.r-project.org/src/contrib/stevedata_1.8.0.tar.gz` and
`https://cran.r-project.org/src/contrib/Archive/stevedata/stevedata_1.8.0.tar.gz`.

MeasuringWorth was also evaluated because it offers daily DJIA history from
1885 with an explicit non-profit educational-use statement. It is retained as
an independently documented cross-check, not the computational source, because
several transcription errors have materially larger downstream effects than the
pinned CRAN series. See `docs/AUXILIARY_SOURCE_COMPARISON.md`.

## VXD

The script downloads [FRED series `VXDCLS`](https://fred.stlouisfed.org/series/VXDCLS)
from the Federal Reserve Bank of St. Louis, whose originating source is Cboe.
The requested daily interval is
1997-10-07 through 2021-05-31; the last finite observation needed by the paper
is 2021-05-28. The local schema is `Date,VXD` and rows with FRED's missing-value
marker are removed.
The exact download request is
`https://fred.stlouisfed.org/graph/fredgraph.csv?id=VXDCLS&cosd=1997-10-07&coed=2021-05-31`.

The [official Cboe history file](https://cdn.cboe.com/api/global/us_indices/daily_prices/VXD_History.csv)
currently begins only on 2009-09-18, so it cannot
replace FRED for the early sample. It was used as an overlap check: current Cboe
and FRED observations agree, while a short block in the authors' archived
Bloomberg-era compilation is shifted by one trading day. No FRED or Cboe
observations are committed to Git. Their source terms and requested citations
remain applicable to each user's retrieval.

## Oxford-Man Institute Realized Library

The Oxford-Man Institute Realized Library was openly downloadable from its
former `https://realized.oxford-man.ox.ac.uk/data` site when the study was
conducted and was discontinued in 2022. The authors approved redistribution
of the minimum subset required here. `data/public/oxford_man_realized_5min.csv`
contains exactly four columns (`Symbol`, `Date`, `rv5`, `close_price`) and 15,769
rows for `.SPX`, `.IXIC`, and `.DJI`, covering 2000-01-03 through 2020-12-18.

The authors' archived full `rvdf.csv` has SHA-256:

`a65def29a0c907d83b2595d6c0a4f6a4ab5c43e5ee52c23eb2ce901c25dc4f53`.

The included subset has SHA-256:

`21d1de0a63a7fb27068d95e46f140f1ff43b4b716c1a23aedbae90db0b395ef5`.

The auditable extraction utility is
`src/scripts/development/create_oxford_man_subset.R`. The source code license
does not relicense these observations. Cite the Oxford-Man Institute Realized
Library and Heber, Lunde, Shephard, and Sheppard (2009) when using them.

## Generated auxiliary inputs

After Step 2 establishes the paper's 300 option dates,
`src/scripts/03_build_auxiliary_inputs.R` reconstructs two local inputs:

- `paper_index_return_history.csv`: 21-trading-day SPX, NDX, and DJX return
  histories and calendar spacing; and
- `paper_volatility_forecasts.csv`: business-day counts and the three expanding-
  window volatility forecasts used by the optimizer.

The NDX history is extended with the paper's estimated linear relation between
overlapping NDX and Nasdaq Composite returns. The volatility stage implements
the paper code's historical-volatility/VIX-family regressions, the switch to
Oxford-Man five-minute realized variance, and the documented lognormal bias
adjustment. Both files and a complete build report remain under ignored
`work/auxiliary/`.
