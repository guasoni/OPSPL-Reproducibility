# Private licensed inputs

Place the three OptionMetrics exports in this directory, using the filenames in
the list below, or pass another directory to `reproduce.R --data-dir PATH`.

Nothing in this directory is tracked by Git except this README.

Required inputs:

- `option_price_view_indices_2020.csv`: the four index SecurityIDs and quote dates
  through 2020-12-31. Do not restrict expiration dates and do not remove SPXW.
- `security_price_indices_through_2021_01.csv`: the same SecurityIDs, extending
  through at least 2021-01-13.
- `zero_curve_through_2020.csv`: every maturity for all quote dates through
  2020-12-31.

See `docs/DATA_EXTRACTION.md` for schemas and validation checks.

From the repository root, the complete current-coverage pipeline is then one
command:

```text
Rscript reproduce.R --data-dir data/private_raw --cores 8
```

Use `--check-inputs` first if you want to verify filenames, schemas, and public
input fingerprints without starting the long scan.

The first run restores the locked R environment. All generated OptionMetrics
derivatives remain under the ignored `outputs/` and `work/` directories.
