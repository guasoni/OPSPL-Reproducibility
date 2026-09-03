# Separate-machine reproduction record

## Test identity

- Candidate tested: pre-release commit `62f515f318d440d91ed9aa297ada28fe061982a4`
- Dates: 2026-09-02 to 2026-09-03
- Environment: Windows 11 host, Ubuntu 24.04 under WSL2, pinned R 4.3.2 container
- Workers: 2
- Test type: clean-machine reproduction test on a separate computer; not an
  independent replication

The repository was obtained as a clean clone. The licensed inputs were kept
outside the repository and mounted read-only. No private source repository,
cached author-side output, or undocumented empirical input was used.

## Outcome

The complete licensed-data workflow finished in 2 hours 51 minutes. It scanned
50,490,867 option rows, constructed the four Step 1 samples with the expected row
counts, rebuilt the public auxiliary inputs, and completed every currently
covered SPX, NDX, and DJX optimization mode.

All covered empirical comparisons passed the declared numerical policy:

| Validation group | Comparisons | Policy failures |
|---|---:|---:|
| Main and small-position performance | 399 | 0 |
| Midprice robustness | 63 | 0 |
| Equivalent-safe-rate calculations | 63 | 0 |
| Margin percentages | 18 | 0 |
| Cross-index option summary | 12 | 0 |
| Five-year panels | 330 | 0 |
| Effective positions | 108 | 0 |
| Wealth endpoints | 21 | 0 |

The public synthetic integration test also passed all 46 checks, with maximum
checkpoint error `4.27e-14`. The proprietary-data audit passed all 13 checks.

## Release hardening after the run

The separate-machine test exposed portability issues in CSV input handling,
Step 1 fingerprinting, supplemental public closes, and FRED transport. They did
not change the selected samples or cause a paper-value failure. The release code
corrects these issues and includes targeted cross-platform regression tests.
The preserved Step 1 output was also checked under the corrected canonical
comparison, confirming agreement after the documented quoted-close adjustment.

A second complete licensed-data optimization was not performed after these
release-hardening changes. Accordingly, this record supports the completed
empirical reproduction above together with targeted verification of the final
portability repairs; it is not represented as an end-to-end clean-machine run of
the final release commit.
