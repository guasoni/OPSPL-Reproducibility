# Releases and citation

## One repository, versioned research objects

This repository is the canonical implementation supporting both the Journal of
Empirical Finance article and a planned companion methods article. It should not
be copied into separate paper-specific repositories while both articles refer to
the same computational method.

Every scholarly citation must identify an immutable release rather than relying
only on the moving `main` branch. Each public release is tagged in GitHub. If a
later Zenodo deposit is created:

- the Zenodo **version DOI** identifies the exact files used for a particular
  validation or article;
- the Zenodo **concept DOI** identifies the repository across all releases; and
- the Git commit recorded in the validation report identifies the exact source
  state even before a release DOI is minted.

No DOI is inserted into repository metadata until the corresponding archive
exists and has been verified.

## Initial release

`v1.0.0` is reserved for the audited JEF reproduction scope stated in
`docs/COVERAGE.md`. The tag is created only after the proprietary-data audit,
the documented separate-machine reproduction and post-run regression checks,
private-remote checks, and public-source archive review have been completed.

Later additions use a new version:

- a patch release corrects documentation or code without changing inputs,
  outputs, or numerical interpretation;
- a minor release adds backward-compatible exhibits, tests, or documented
  capabilities; and
- a major release changes an input contract, public interface, or substantive
  interpretation incompatibly.

Future substantive code or fixed-input changes that could affect empirical
results require the relevant numerical and clean-machine checks to be repeated,
regardless of version label. The narrow post-test portability changes preceding
`v1.0.0`, and the absence of a second complete licensed-data optimization after
them, are disclosed in `docs/CLEAN_MACHINE_REPORT.md`.

## What to cite

Before permanent identifiers are available, users should cite the accepted JEF
article and identify the GitHub release and Git commit in prose. After an archive
and companion article exist, the repository README and `CITATION.cff` will
contain complete formatted references.

The intended citation rule is:

- cite the JEF article when using the financial model, empirical design, or
  reported economic findings;
- cite the companion methods article when using or adapting the computational
  workflow, data-construction protocol, or validation design;
- cite the exact Zenodo version DOI when computational provenance matters; and
- cite both articles when both the substantive method and its reproducible
  implementation are material to the new work.

The repository archive is classified as software even if an associated article
is published as a methods article. The BSD 3-Clause software license, the
article's publication license, and third-party data terms remain separate.
