if (!requireNamespace("renv", quietly = TRUE)) {
  stop(
    paste(
      "renv did not activate.",
      "Start R from the repository root and source renv/activate.R, then rerun this script."
    )
  )
}
renv::restore(prompt = FALSE)
cat("Locked R environment restored.\n")
