/*
  OptionMetrics inputs for "Options Portfolio Selection with Position Limits".

  Run each SELECT separately and export it as CSV with the column names retained.
  The schema prefix may differ on WRDS or in a local OptionMetrics installation.

  SecurityID mapping:
    108105 = SPX
    102434 = RUT
    102456 = DJX
    102480 = NDX
*/

/*
  1. Option quotes. Keep SPXW rows and all expiration dates.  The explicit
  column list is the raw-input contract used by src/scripts/01_build_step1.R; it
  also avoids accidental changes if the vendor later adds columns to the view.
*/
SELECT
    SecurityID,
    [Date],
    Symbol,
    SymbolFlag,
    Strike,
    Expiration,
    CallPut,
    BestBid,
    BestOffer,
    LastTradeDate,
    Volume,
    OpenInterest,
    SpecialSettlement,
    ImpliedVolatility,
    Delta,
    Gamma,
    Vega,
    Theta,
    OptionID,
    AdjustmentFactor,
    AMSettlement,
    ContractSize,
    ExpiryIndicator
FROM IvyDB.dbo.OPTION_PRICE_VIEW
WHERE SecurityID IN (108105, 102434, 102456, 102480)
  AND [Date] >= '19960101'
  AND [Date] <  '20210101'
ORDER BY SecurityID, [Date], Expiration, CallPut, Strike;

/*
  2. Underlying closes. January 2021 is required to value the final option block.
  An extract through 2021-01-31 avoids reliance on the four public supplements.
*/
SELECT
    SecurityID,
    [Date],
    BidLow,
    AskHigh,
    ClosePrice,
    Volume,
    TotalReturn,
    AdjustmentFactor,
    OpenPrice,
    SharesOutstanding,
    AdjustmentFactor2
FROM IvyDB.dbo.SECURITY_PRICE
WHERE SecurityID IN (108105, 102434, 102456, 102480)
  AND [Date] >= '19960101'
  AND [Date] <  '20210201'
ORDER BY SecurityID, [Date];

/* 3. Zero-coupon curve. Retain every maturity for each date. */
SELECT
    [Date],
    Days,
    Rate
FROM IvyDB.dbo.ZERO_CURVE
WHERE [Date] >= '19960101'
  AND [Date] <  '20210101'
ORDER BY [Date], Days;
