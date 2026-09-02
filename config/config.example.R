# Advanced configuration example. Most users can instead run:
# Rscript reproduce.R --data-dir PATH --cores N
# Forward slashes work on Windows, macOS, and Linux.

config <- list(
  data_mode = "current-vintage",
  option_prices = "data/private_raw/option_price_view_indices_2020.csv",
  security_prices = "data/private_raw/security_price_indices_through_2021_01.csv",
  zero_curve = "data/private_raw/zero_curve_through_2020.csv",
  supplemental_closes = NULL,
  acquire_auxiliary = TRUE,
  build_auxiliary = TRUE,
  auxiliary_data_mode = "source-current",
  public_yahoo_daily = "work/auxiliary/yahoo_daily.csv",
  public_djia_daily = "work/auxiliary/djia_daily.csv",
  public_vxd_daily = "work/auxiliary/vxd_daily.csv",
  public_oxford_man_realized = "data/public/oxford_man_realized_5min.csv",
  public_volatility_forecasts = "work/auxiliary/paper_volatility_forecasts.csv",
  public_index_returns = "work/auxiliary/paper_index_return_history.csv",
  supplemental_closes_generated = "work/auxiliary/index_closes_2021-01-13.csv",
  auxiliary_acquisition_report = "work/auxiliary/acquisition_report.json",
  auxiliary_build_report = "work/auxiliary/build_report.json",
  output_root = "outputs",
  work_root = "work",
  workers = 1L,
  chunk_lines = 250000L,
  reuse_step1_selection = TRUE
)
