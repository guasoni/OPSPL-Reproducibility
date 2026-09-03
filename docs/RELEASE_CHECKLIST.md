# Public-release checklist

The repository remains a local release candidate until every required item below
passes.

## Reproduction

- [x] Clean repository with no private Git history.
- [x] R-only raw OptionMetrics-to-Step-1 implementation.
- [x] Full paper-vintage Step 1 comparison for SPX, NDX, DJX, and RUT.
- [x] R-only Step 2 filtering with exact archived row retention.
- [x] R-only acquisition and reconstruction of the public-source return history
      and all 300 volatility forecasts, followed by Step 3 attachment.
- [x] Full nine-configuration optimization for all three indexes and both panels.
- [x] Analytical small-position run for SPX (the index reported in the paper's
      current-coverage small-limit panel).
- [x] All currently covered paper cells pass the reproduction policy.
- [x] Single R entry point restores the environment, builds Step 1, runs the
      analysis, and validates the results.
- [x] Fresh project-library restore and paper-vintage input preflight from the
      assembled repository.
- [x] Deterministic synthetic integration run exercises the raw schemas, Step 1
      selection branches, filtering, forecasts, and every covered optimizer mode.
- [x] Clean-room protocol and publication-safe report template documented.
- [x] Complete separate-machine licensed-data run using only the repository and
      documented user inputs.
- [x] Publication-safe report records the candidate, environment, aggregate
      outcomes, post-run portability hardening, and the absence of a second full run.
- [x] Result labelled accurately as a clean-machine reproduction test, not an
      independent replication.
- [x] Formal method specification and hand-verifiable formula tests included.
- [x] Reproducible workflow figure and MethodsX resource map included.

## Data and licensing

- [x] OptionMetrics raw and row-level derived data excluded from the candidate.
- [x] Exact indexed tree, reachable history, and unreachable local blobs scanned
      by the strict audit documented in `docs/PROPRIETARY_DATA_AUDIT.md`.
- [x] Private raw directory and generated outputs ignored by Git.
- [x] SQL, schemas, SecurityIDs, dates, and validation rules documented.
- [x] Yahoo observations replaced by a documented user-side retrieval step; no
      Yahoo data file is committed.
- [x] Bloomberg-era DJIA/VXD compilation and derived checkpoints replaced by
      executable CRAN/FRED retrieval and R reconstruction; no Bloomberg data or
      Bloomberg-derived checkpoint is committed.
- [x] Oxford-Man inclusion decision, full archived-source checksum, exact subset
      transformation, and distributed-subset checksum recorded.
- [x] The sole redistributed empirical auxiliary file is listed in
      `data/public/provenance.csv`; source-provider rights remain outside the BSD
      code license.
- [x] Every included public data file has a source, transformation record, and
      SHA-256.

## Repository

- [x] R package versions locked with `renv`.
- [x] Separate public-ready local repository assembled under the final name.
- [x] Machine-readable exhibit coverage and final-paper values included.
- [x] BSD 3-Clause source-code license selected and installed; third-party data
      remain outside that grant.
- [x] Journal-neutral substantive source layout under `src/`.
- [x] Reusable method, fixed JEF profile, and supported run-mode claims documented.
- [x] Release/version and dual-article citation policy documented.
- [x] Contribution instructions prohibit licensed data in issues and pull requests.
- [x] Windows and Linux public synthetic-check matrix configured.
- [x] Optional WSL2 container route pins R 4.3.2, mounts licensed inputs
      read-only, and excludes the repository and data from the build context.
- [x] Exact second-computer commands and evidence requirements documented.
- [ ] Windows and Linux checks pass on the staged private GitHub repository.
- [x] `v1.0.0` GitHub release metadata prepared without asserting a DOI or Zenodo
      deposit before either exists.
- [ ] Citation metadata updated with the final journal citation and DOI.
- [x] Licensed-data leak scan passes on the current staged release-candidate Git
      index.
- [ ] Licensed-data and personal-path scans repeated after all final edits and on
      the exact commit to be pushed.
- [ ] Downloadable GitHub source archive inspected for the same data boundary.
- [ ] Candidate first pushed to a private remote and all remote checks pass.
- [ ] Public GitHub repository created only after the preceding checks pass.
- [ ] Optional archival DOI created later; intentionally not a condition for the
      JEF proof link or initial GitHub release.
