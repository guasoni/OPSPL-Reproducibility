## Purpose

Describe the correction or improvement and state whether it affects the fixed
JEF profile, reusable workflow, synthetic fixture, data boundary, or numerical
interpretation.

## Validation

- [ ] `Rscript tests/run_tests.R` passes.
- [ ] `Rscript reproduce.R --synthetic --cores 2` passes.
- [ ] Any result-affecting change has received the required licensed-data review.
- [ ] Expected values or tolerances were not changed solely to make a test pass.

## Data safety

- [ ] This pull request, its commits, messages, screenshots, logs, and attachments
      contain no OptionMetrics observations, row-level derivatives, credentials,
      or personal paths.
