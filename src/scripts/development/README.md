# Author-side development utilities

These scripts are not required by a public reproducer and are not called by
`src/scripts/run_all.R`.

- `create_oxford_man_subset.R` verifies the authors' archived full Oxford-Man
  file and creates the exact four-column subset distributed in `data/public`.
- `create_expected_paper_values.R` converts the final-paper audit tables into
  machine-readable expected cells.
- `compare_private_audit_reference.R` compares a clean run with the authors'
  private audited Step 4 outputs under the published numerical policy. Supply
  that private directory with `--reference-dir`; no reference data or local path
  is embedded in the repository.
