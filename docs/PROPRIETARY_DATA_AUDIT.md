# Proprietary-data audit

## Outcome

The current release-candidate tree **passes the OptionMetrics data-boundary
audit**. It contains the extraction specification, identifiers, raw-file
fingerprints, software, synthetic observations, and low-dimensional values
published in the paper, but no OptionMetrics observation and no row-level
OptionMetrics derivative.

The earlier Yahoo/Bloomberg/FRED redistribution blockers have been removed from
the candidate tree. The separate-machine reproduction is recorded in
`docs/CLEAN_MACHINE_REPORT.md`.

## Scope and method

The audit was performed on the exact Git index assembled for the initial release,
not merely on selected visible folders. The automated audit is
`src/scripts/07_audit_public_tree.R`. It checks:

- every indexed path, file mode, byte size, and worktree-to-index hash;
- CSV headers for the OptionMetrics option-price, security-price, zero-curve,
  and generated Step 1 schemas;
- text for rows beginning with one of the four paper SecurityIDs followed by an
  observation date;
- private raw filenames, generated-output directories, archives, databases,
  binary signatures, and embedded NUL bytes;
- private-key and credential signatures and personal home-directory paths;
- every blob reachable from Git history; and
- unreachable local Git blobs, even though an ordinary Git push does not
  transfer them.

Run it from the repository root with:

```text
Rscript src/scripts/07_audit_public_tree.R
```

The machine-readable result is written to the ignored file
`outputs/proprietary_data_audit.json`. Continuous integration reruns the audit on
both Windows and Linux.

## Findings

- The three required OptionMetrics exports are absent from the indexed tree.
- No indexed CSV has a raw OptionMetrics or row-level Step 1 schema.
- No indexed text contains an OptionMetrics observation-row signature.
- No archive, database, opaque binary, file at or above GitHub's 100 MB limit,
  credential signature, or personal absolute path was found.
- The worktree and indexed blobs agree byte for byte.
- The repository has no inherited commit history. Local unreachable objects are
  earlier revisions of repository code and documentation; the same content scan
  found no vendor observation row, credential, personal path, or binary payload
  in them.
- Files under `expected/paper_values` contain only low-dimensional aggregate
  table cells and figure endpoints already reported or validated for the paper.
  They are not contract-, quote-, or position-level records.
- SecurityIDs, SQL criteria, filenames, schemas, counts, byte sizes, and SHA-256
  fingerprints are documentation about how licensed users can identify and
  verify their own extracts. They do not disclose the underlying observations.

The audit must be rerun after every final edit, on the exact first commit, and on
the downloadable source archive before the repository is made public.

## Auxiliary-data resolution

The four files that previously prevented a public push were removed before any
public history was created:

- the frozen Yahoo daily archive;
- the Bloomberg-derived DJX return checkpoint;
- the archived-source volatility-forecast checkpoint; and
- the four-row January 2021 closing-level supplement.

The one-command R workflow now retrieves Yahoo observations, checksum-pinned
CRAN DJIA history, and FRED VXD into ignored local storage. It reconstructs the
two derived checkpoints locally and creates the January 2021 supplement only
for users of the authors' legacy security-price extract. Neither the source
observations nor these generated files enter Git.

The sole redistributed empirical auxiliary file is the 0.76 MB minimum
Oxford-Man subset. Its archived-source hash, four-column extraction, 15,769-row
contract, distributed-file hash, attribution, and authors' redistribution
determination are recorded in `data/public/provenance.csv` and
`docs/DATA_SOURCES.md`. It contains no OptionMetrics field or observation.

## Release decision

The strict OptionMetrics audit is complete and passes, and the auxiliary files
that lacked a redistribution basis have been replaced by executable acquisition
steps. Publication additionally requires the exact final-commit and downloadable-
archive scans in `docs/RELEASE_CHECKLIST.md`.
