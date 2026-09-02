# Data license notice

The BSD 3-Clause license in `LICENSE.txt` applies to the source code and original
repository documentation. It does not grant rights in third-party datasets.

This repository does not distribute OptionMetrics observations or option-level
derivatives. Users must obtain OptionMetrics access independently and create the
private extracts described in `docs/DATA_EXTRACTION.md`.

The sole empirical dataset under `data/public` is the minimum Oxford-Man
realized-volatility subset described in `data/public/provenance.csv`. It retains
the rights and attribution of its source provider and is not relicensed by the
BSD software license.

Yahoo, CRAN DJIA, FRED/Cboe, and derived return/forecast observations are not
distributed. The R workflow retrieves or constructs them in ignored local
storage for the user's reproduction. Each user remains responsible for the
source terms applicable to that retrieval. Source-current data may differ from
the authors' archive; the measured limitation and numerical policy are recorded
in `docs/AUXILIARY_SOURCE_COMPARISON.md` and
`docs/REPRODUCTION_POLICY.md`.

Generated files under `outputs` and `work` may contain licensed OptionMetrics
observations or derivatives. They are excluded from Git and must not be uploaded,
attached to issues, or published as workflow artifacts.

The synthetic fixture generated under `work/synthetic` is created entirely by
the repository code and contains no vendor observations. Its numerical values
are non-empirical and are not substitutes for the licensed data when reproducing
the paper.
