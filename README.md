# Option Portfolio Selection: Reproducibility Package

This repository is the clean reproduction package for **“Options Portfolio
Selection with Position Limits”** by Paolo Guasoni, Eberhard Mayerhofer, and
Mingchuan Zhao, accepted by the *Journal of Empirical Finance*.

The package was assembled from a completed forensic audit of the authors'
original code. It is intentionally separate from that private repository and
does not inherit its Git history.

## Scope and status

Release `v1.0.0` covers the central SPX, NDX, and DJX results validated by the
audit:

- the main unconstrained and solvency-constrained performance panels;
- the analytical small-position-limit panel;
- the margin tables;
- the corrected equivalent-safe-rate table;
- the five-year SPX panels;
- the effective-position tables;
- the numerical series underlying the three wealth figures; and
- the reproducible option-market cells in the cross-index summary table.

See [`docs/COVERAGE.md`](docs/COVERAGE.md) for the precise exhibit-level scope.
Additional paper exhibits will be added without changing the raw-data boundary
or the main execution interface.

The distinction between the reusable computational workflow and the fixed JEF
replication profile is documented in
[`docs/METHOD_REUSE.md`](docs/METHOD_REUSE.md). The repository is a research
workflow and reproduction package, not a general-purpose investment product.
The mathematical and computational definitions, with direct links to their R
implementation, are in
[`docs/METHOD_SPECIFICATION.md`](docs/METHOD_SPECIFICATION.md).

The mapping from the audited authors' code to this clean implementation is in
[`docs/CODE_PROVENANCE.md`](docs/CODE_PROVENANCE.md).
The completed release-candidate checks and observed tolerances are in
[`docs/VALIDATION.md`](docs/VALIDATION.md).
The separate-machine reproduction is summarized in
[`docs/CLEAN_MACHINE_REPORT.md`](docs/CLEAN_MACHINE_REPORT.md).
The strict indexed-tree and Git-object review is recorded in
[`docs/PROPRIETARY_DATA_AUDIT.md`](docs/PROPRIETARY_DATA_AUDIT.md).

## Reproduction standard

The target is equality with the final paper at its displayed precision, supported
by strict numerical tolerances for unrounded returns and weights. Byte-identical
floating-point files and byte-identical figure PDFs are not required across
operating systems.

Two data modes are supported:

1. **Current-vintage mode** (the default), which applies the documented
   selection criteria to a newly licensed OptionMetrics extraction and records
   the extraction date and input fingerprints.
2. **Paper-vintage mode**, reserved for the authors' archived files and validated
   against their recorded 2020-vintage fingerprints.

Historical vendor revisions may cause a current-vintage extraction to differ
from the archived input. Both modes write the same paper-value comparisons.
Paper-vintage mode additionally requires exact raw-input byte fingerprints and
canonical Step 1 content fingerprints; current-vintage mode records any vendor-
vintage differences explicitly rather than misidentifying them as code failures.
In either mode, the public auxiliary
series are retrieved from their sources and their run-specific fingerprints are
recorded as `auxiliary_data_mode = "source-current"`; this label is separate from
the OptionMetrics data mode.

## Data boundary

No OptionMetrics observations or row-level derivatives are distributed here.
Licensed users create three raw extracts and place them in `data/private_raw`:

1. `option_price_view_indices_2020.csv`
2. `security_price_indices_through_2021_01.csv`
3. `zero_curve_through_2020.csv`

Ready-to-run SQL, exact CSV schemas, canonical filenames, date coverage, and
historical fingerprints are in
[`sql/optionmetrics_extract.sql`](sql/optionmetrics_extract.sql) and
[`docs/DATA_EXTRACTION.md`](docs/DATA_EXTRACTION.md). The same contract is also
available in machine-readable form at
[`expected/raw_input_contract.csv`](expected/raw_input_contract.csv).

The R pipeline generates the Step 1 files locally from those extracts. The Step 1
files, all later option-level intermediates, and all portfolio weights remain in
ignored local directories. For the paper-vintage inputs, their row counts and
canonical table-content SHA-256 fingerprints are checked against
`expected/step1_paper_vintage_fingerprints.csv` without publishing the files.
Historical byte hashes remain in that contract as provenance but are not a
cross-platform release gate.

The minimum Oxford-Man realized-volatility subset is the sole redistributed
empirical auxiliary input. Yahoo observations, a long DJIA history, and VXD are
downloaded from Yahoo, a checksum-pinned CRAN `stevedata` archive, and FRED;
historical returns and volatility forecasts are then rebuilt in R. Source URLs,
date coverage, transformations, fingerprints, and the measured differences from
the authors' archive are documented in [`docs/DATA_SOURCES.md`](docs/DATA_SOURCES.md)
and [`docs/AUXILIARY_SOURCE_COMPARISON.md`](docs/AUXILIARY_SOURCE_COMPARISON.md).

## Software

All transformations, portfolio calculations, tables, and validations require R
only. The sole SQL file is an extraction recipe to be run inside the user's
licensed OptionMetrics database; once the three CSV dumps exist, SQL is not part
of the workflow. The audited optimizer uses R 4.3.2 and `quadprog` 1.5-8; all R
package versions are pinned in `renv.lock`.

Use 64-bit R 4.3.2 and allow internet access on the first run so that `renv` can
restore the four locked analysis packages and retrieve the non-OptionMetrics
market series. Some platforms may install
`data.table` or `digest` from source. In that case, Windows users need Rtools 4.3,
macOS users need the Command Line Tools for Xcode, and Linux users need the usual
C/C++ and Fortran build tools. No Python, MATLAB, Stata, or proprietary optimizer
is required.

For a clean Linux environment on Windows, the repository also provides an
optional WSL2/Docker launcher. It pins the exact Rocker R 4.3.2 base image,
mounts the licensed input directory read-only, and sends no research files to
the Docker build context. For example:

```text
./run-container.sh --synthetic --cores 2
./run-container.sh --data-dir ~/private/optionmetrics --mode paper-vintage --cores 8
```

The complete second-computer procedure is in [`docs/WSL2.md`](docs/WSL2.md).
Docker is optional and is not part of the analytical implementation.

## One-command reproduction

Export the three licensed files with the canonical filenames above, place them
in one directory, and run from the repository root:

```text
Rscript reproduce.R --data-dir "/path/to/optionmetrics-export" --cores 8
```

The first invocation restores the packages pinned in `renv.lock`, downloads the
required Yahoo, CRAN DJIA, and FRED VXD series, reconstructs the historical-return
and volatility-forecast inputs, constructs all four Step 1 files in R, runs the
currently covered analysis, and executes the numerical validation suite. It does
not contact OptionMetrics: users create those three licensed exports themselves.
Generated files remain under ignored `outputs/` and `work/` directories.

Downloaded auxiliary sources are cached for the run's reproducibility. Use
`--refresh-auxiliary` only when deliberately updating that source vintage. Every
acquisition and derived file receives a timestamp, date range, and SHA-256 in
`work/auxiliary/`.

Run `Rscript reproduce.R --help` for all options. Users who need nonstandard
paths or the authors' archived paper-vintage mode can instead copy
`config/config.example.R` or `config/config.paper-vintage.example.R`, edit it,
and run:

```text
Rscript reproduce.R --config config/config.R --cores 8
```

Before starting the long scan, the three private files can be checked with:

```text
Rscript reproduce.R --data-dir "/path/to/optionmetrics-export" --check-inputs
```

The final stage checks input schemas and fingerprints, Step 1 counts, covered
paper cells, returns and weights, margin and solvency decisions, wealth-figure
endpoints, the repository data boundary, and the absence of personal paths. A
successful command ends with a numerical validation pass rather than merely
writing output files. The validation rules are documented in
[`docs/REPRODUCTION_POLICY.md`](docs/REPRODUCTION_POLICY.md).

For development runs that already have private Step 1 or optimization outputs,
use `--skip-step1` or `--skip-optimization`. These shortcuts are never accepted
as a clean-machine release test.

On the authors' workstation, the first complete R scan of the 50,490,867-row,
9.2 GB option extract took about 17 minutes per raw-file pass. Step 1 uses bounded
memory and caches the monthly-contract selection for later development runs.
Hardware and storage speed will affect the observed runtime.

## Synthetic integration test

The complete executable path through Step 1, filtering, forecast attachment, and
all currently used portfolio-optimization modes can be tested without licensed
data:

```text
Rscript reproduce.R --synthetic --cores 2
```

This command deterministically generates a small OptionMetrics-shaped fixture
with 13 raw expiration months and 12 usable portfolio periods. It includes all
four index identifiers, calls and puts at five strikes, competing monthly
expirations, SPXW rows that must be excluded, Saturday expirations that must be
adjusted, multiple zero-curve maturities, and matching synthetic price,
forecast, and return histories. It then runs the core pipeline and checks
dimensions, missing values, selection decisions, solvency constraints, margin
diagnostics, and numerical regression checkpoints.

The fixture is deliberately non-empirical. A successful synthetic run verifies
software integration only; it does not reproduce, validate, or provide evidence
for any estimate in the paper. Each run replaces only `work/synthetic/`, and its
inputs and outputs remain ignored by Git. Its construction and validation
contract are documented in
[`docs/SYNTHETIC_FIXTURE.md`](docs/SYNTHETIC_FIXTURE.md).

The data-free source and fixed-input tests can be run separately with:

```text
Rscript tests/run_tests.R
```

The public continuous-integration configuration is set to run these checks and
the full synthetic integration test on both Windows and Linux. A complete
licensed-data run was also performed on a separate WSL2 machine. It reproduced
all covered empirical results and led to targeted portability hardening; the
scope of the run and the fact that the final repairs were not followed by a
second full optimization are stated in
[`docs/CLEAN_MACHINE_REPORT.md`](docs/CLEAN_MACHINE_REPORT.md). It is not
described as an independent replication.

## Repository layout

- `reproduce.R`: single public entry point.
- `Dockerfile` and `run-container.sh`: optional pinned R 4.3.2 environment for
  clean WSL2/Linux execution; the research pipeline invoked inside it is R-only.
- `src/R/`: shared R utilities.
- `src/scripts/01_build_step1.R`: bounded-memory R conversion from the three vendor
  exports to `SPXfinal.csv`, `NDXfinal.csv`, `DJXfinal.csv`, and `RUTfinal.csv`.
- `src/scripts/acquire_auxiliary_data.R`: source retrieval for Yahoo, pinned CRAN
  DJIA, and FRED VXD.
- `src/scripts/03_build_auxiliary_inputs.R`: R reconstruction of historical
  returns, business-day counts, and volatility forecasts.
- `src/scripts/02_filter_options.R`, `03_attach_forecasts.R`,
  `04_optimize_portfolios.R`, and `05_generate_outputs.R`: filtered samples,
  forecast attachment, portfolios, tables, and figure data.
- `src/scripts/06_validate_release.R`: numerical and public-release validation.
- `src/scripts/07_audit_public_tree.R`: strict indexed-tree and Git-history data-boundary audit.
- `src/scripts/generate_workflow_diagram.R`: reproducible workflow and graphical-abstract source.
- `src/synthetic/`: deterministic fixture generation and integration validation.
- `data/public/`: the minimal Oxford-Man subset with SHA-256 provenance.
- `data/private_raw/`, `work/`, and `outputs/`: ignored local-only locations.
- `expected/`: raw-input contracts, paper-vintage fingerprints, paper values,
  and exhibit coverage.
- `docs/METHODSX_RESOURCE_MAP.md`: provisional mapping from the MethodsX article
  template to the repository evidence.

Contribution instructions, including the prohibition on attaching licensed data
to issues or pull requests, are in [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Citation and releases

The JEF article is the source for the financial method, empirical design, and
economic findings. The exact archived software release identifies the code used
to reproduce them. A planned companion methods article will describe the
computational workflow and validation design; no citation for it is asserted
before publication.

Complete identifiers will be added after the JEF citation is final and an
archival deposit is created. Until then, cite the accepted article, GitHub
release, and Git commit. The permanent policy for article citations, GitHub
tags, and any later archival DOI is in
[`docs/RELEASES_AND_CITATION.md`](docs/RELEASES_AND_CITATION.md).

## Licensing

Source code and original repository documentation are released under the BSD
3-Clause License; see [`LICENSE.txt`](LICENSE.txt). Data retain the terms of their
respective providers, and inclusion here does not relicense third-party data.
The exact boundary is stated in
[`DATA_LICENSE_NOTICE.md`](DATA_LICENSE_NOTICE.md).

The BSD license applies independently of any Creative Commons license selected
for an associated journal article. The software release remains a software
archive even when it is cited by a methods article.

Release metadata identify `v1.0.0`. No Zenodo deposit or DOI is asserted in this
release; an archival DOI may be added later without changing the software
license.
