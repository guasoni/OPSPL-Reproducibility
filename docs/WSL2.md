# Clean-machine replication with WSL2

## Purpose

WSL2 provides a clean Linux execution environment on a second Windows computer.
It tests installation, Linux path and filename behavior, package restoration,
source acquisition, and numerical portability. If an original author operates
the second computer, describe the result as a **clean-machine replication by the
authors**, not as an independent replication.

The optional container fixes R at version 4.3.2. It does not change the research
implementation: data construction, estimation, optimization, output generation,
and validation remain R-only. The container launcher only prepares the operating
environment and mounts the user-supplied files.

## Prerequisites

- A fresh 64-bit WSL2 Linux distribution.
- Git and Docker available from inside that distribution. Docker Desktop with
  WSL2 integration or Docker Engine inside WSL2 are both suitable.
- Internet access for the first package restore and the documented Yahoo, CRAN,
  and FRED retrievals.
- Preferably at least 40--50 GB of free storage and 16 GB of RAM for the complete
  paper-vintage run.

Follow the current official installation instructions for
[WSL](https://learn.microsoft.com/windows/wsl/install) and
[Docker on WSL2](https://docs.docker.com/desktop/features/wsl/). Confirm from the
WSL terminal that `git --version` and `docker version` both succeed.

## Storage boundary

Create both the clone and a separate private data directory inside the Linux
filesystem, for example:

```text
~/Option-Portfolio-Selection-Reproducibility
~/private/optionmetrics-paper-vintage
```

Do not put either directory under `/mnt/c`, OneDrive, Dropbox, or another synced
Windows directory. Microsoft recommends the WSL filesystem for Linux-command
performance, which is important for repeated scans of the 9.2 GB option export.

Place only the three licensed exports in the private data directory. For the
paper-vintage test their canonical names are:

```text
option_price_view_indices_2020.csv
closing_prices_2020.csv
zero_curve_2020.csv
```

The directory is mounted read-only inside the container. It must never be copied
into the repository or attached to a GitHub issue, workflow, release, or journal
submission.

## Obtain the release candidate

Before public release, authenticate to GitHub from WSL and clone the private
candidate directly:

```text
git clone https://github.com/guasoni/Option-Portfolio-Selection-Reproducibility.git
cd Option-Portfolio-Selection-Reproducibility
git status --short
git rev-parse HEAD
```

The status output must be empty. Record the commit printed by the final command.
Do not copy the development directory, its package library, `work/`, `outputs/`,
or an edited configuration file.

## Required clean-machine commands

Run these commands from the repository root, in order:

```text
./run-container.sh --source-tests
./run-container.sh --synthetic --cores 2
./run-container.sh --data-dir ~/private/optionmetrics-paper-vintage --mode paper-vintage --check-inputs
./run-container.sh --data-dir ~/private/optionmetrics-paper-vintage --mode paper-vintage --cores 8
./run-container.sh --audit-source
```

Choose a smaller worker count if the machine has fewer cores. The first command
builds the image and restores the locked R packages; later builds reuse Docker's
verified local layers. The base is fixed to the multi-platform manifest digest:

```text
rocker/r-ver:4.3.2@sha256:4e32addfc4da3e660f6e0d05ce5e43d3eceb9db58a60b9a142e0dde9a654ead1
```

The Docker build context excludes everything except `Dockerfile`, so neither the
source tree nor any accidentally adjacent data is copied into an image layer.
At runtime the repository is mounted read/write for ignored outputs, while the
OptionMetrics directory is mounted read-only at `/optionmetrics`.

## Evidence to retain

Complete the template in [`CLEAN_ROOM_REPLICATION.md`](CLEAN_ROOM_REPLICATION.md).
Retain the exact commit, image digest, commands, environment, elapsed time,
aggregate pass/fail results, and any warning or intervention. The public record
may include aggregate counts and cryptographic fingerprints, but it must not
include execution logs containing personal paths or any raw or row-level
OptionMetrics observation.

WSL2 is a Linux portability test, not a native-Windows test. The repository's
continuous-integration matrix separately exercises the synthetic workflow on
native Windows and Linux.
