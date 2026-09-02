# Changelog

## 1.0.0 (release candidate)

- Reimplement the covered paper pipeline in R with a locked environment.
- Generate the four Step 1 files directly from user-supplied OptionMetrics exports.
- Validate covered tables, numerical series, portfolio constraints, and data boundaries.
- Add a deterministic, non-empirical synthetic integration fixture.
- Organize the executable implementation under `src/` as a reusable, archival
  research object suitable for the JEF reproduction and a companion methods article.
- Document the boundary between the reusable workflow and the fixed JEF
  replication profile, together with release, citation, and clean-room policies.
- Configure public-data and synthetic integration checks on both Windows and Linux.
- Add a strict Git-index, history, and unreachable-object audit for licensed-data
  leakage, credentials, personal paths, archives, and binary payloads.
- Replace redistributed Yahoo and Bloomberg-era derived checkpoints with an
  executable R acquisition/reconstruction stage using Yahoo, checksum-pinned
  CRAN `stevedata` DJIA, and FRED VXD.
- Add the exact minimum Oxford-Man realized-volatility subset required by the
  forecast estimator, with full-source and subset checksums.
- Document and test the observation-level, forecast-level, and portfolio-level
  effect of the public-source substitutions.
- Add an optional WSL2 container launcher with a digest-pinned Rocker R 4.3.2
  base, read-only licensed-data mount, minimal Docker build context, and a
  documented clean-machine protocol.

The version becomes released only when the public Git tag and archival deposit are created.
