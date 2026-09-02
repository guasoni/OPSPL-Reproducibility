# Clean-room replication protocol and report

## Objective

The clean-room test determines whether a researcher can start from the release
candidate and the documented inputs, restore the software environment, and
obtain the declared results without using the development workspace, cached
intermediates, private correspondence, or undocumented instructions.

A different operator is preferred. If the original operator repeats the test on
another machine, the report must call it a **clean-machine replication**, not an
independent replication.

## Isolation requirements

- Start from a fresh clone or release archive at the candidate commit.
- Do not copy `work/`, `outputs/`, an existing project library, or an edited
  configuration from the development workspace.
- Supply only the three documented OptionMetrics exports and, for the authors'
  historical test, the documented paper-vintage configuration.
- Allow the public entry point to retrieve Yahoo, the pinned CRAN DJIA archive,
  and FRED VXD. Do not prepopulate `work/auxiliary/` from the development machine.
- Restore packages from `renv.lock` using the public entry point.
- Do not consult the private source repository during the run.
- Record every deviation from the published instructions.
- On WSL2, keep the clone and licensed inputs in the Linux filesystem rather
  than `/mnt/c`, and keep the licensed directory outside the clone.

The public synthetic run should also be executed on Windows and Linux. The full
licensed-data run may be performed on one clean 64-bit platform, provided that
the platform and hardware are recorded.

## Required commands

From the repository root, first run the data-free checks:

```text
Rscript tests/run_tests.R
Rscript reproduce.R --synthetic --cores 2
```

Then check the licensed inputs before the long scan:

```text
Rscript reproduce.R --data-dir "/path/to/optionmetrics-export" --check-inputs
```

Finally run the full paper-vintage configuration using only the paths prepared
for the clean environment:

```text
Rscript reproduce.R --config config/config.R --cores N
```

For the recommended WSL2 container route, the equivalent complete sequence is:

```text
./run-container.sh --source-tests
./run-container.sh --synthetic --cores 2
./run-container.sh --data-dir ~/private/optionmetrics-paper-vintage --mode paper-vintage --check-inputs
./run-container.sh --data-dir ~/private/optionmetrics-paper-vintage --mode paper-vintage --cores N
./run-container.sh --audit-source
```

See `docs/WSL2.md`. The licensed directory is mounted read-only and the pinned
container supplies R 4.3.2; all research computations still run through the
same R entry point.

The operator should follow `README.md` and `docs/DATA_EXTRACTION.md`; this file
must not supply a hidden workaround.

## Report template

Complete the following record without including personal paths, credentials,
OptionMetrics rows, or row-level derivatives.

### Identity

- Candidate version:
- Git commit:
- Test date:
- Operator:
- Operator role: independent / coauthor not involved in implementation /
  original operator on a separate machine
- Source obtained as: clean clone / release archive

### Environment

- Operating system and version:
- R version and architecture:
- Execution route: native R / WSL2 container
- Container base digest, if applicable:
- `renv.lock` restored without manual package substitutions: yes / no
- CPU and logical cores:
- RAM:
- Locale:
- Number of workers used:

### Inputs

- Data mode: paper-vintage / current-vintage
- Required filenames present: pass / fail
- Input schemas: pass / fail
- Input fingerprints: pass / fail / not applicable to current-vintage mode
- Auxiliary acquisition completed from source: pass / fail
- CRAN `stevedata` archive checksum: pass / fail
- Auxiliary source and derived-file fingerprints recorded: pass / fail
- Any deviation from the documented extraction or filenames:

### Checks

| Check | Result | Public evidence retained |
|---|---|---|
| Data-free source and fixed-input tests | pass / fail | |
| Synthetic integration test | pass / fail | |
| Licensed-input preflight | pass / fail | |
| Step 1 construction and fingerprints | pass / fail | |
| Auxiliary acquisition and return/forecast reconstruction | pass / fail | |
| Filtering and forecast attachment | pass / fail | |
| All declared optimization modes | pass / fail | |
| Post-solution constraint checks | pass / fail | |
| Paper-value numerical validation | pass / fail | |
| Public-source and proprietary-data boundary checks | pass / fail | |

### Outcome

- `generation_complete`:
- `paper_value_pass`:
- `pipeline_pass`:
- Total elapsed time:
- Undocumented intervention required: yes / no
- Deviations, warnings, or failed checks:
- Operator conclusion:
- Operator sign-off and date:

## Evidence permitted in the public repository

The completed public record may contain software versions, hardware, commands,
elapsed times, aggregate counts, cryptographic fingerprints, tolerances, and
pass/fail summaries. Before it is committed, it must pass the same proprietary-
data and personal-path scan as the source tree.

Raw OptionMetrics observations, row-level derived files, excerpts from those
files, credentials, private paths, and unrestricted execution logs must remain
outside GitHub, issues, pull requests, release assets, and journal supplements.
