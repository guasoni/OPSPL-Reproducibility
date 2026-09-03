script_hit <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_hit) != 1L) stop("Cannot locate src/scripts/generate_workflow_diagram.R")
root <- normalizePath(
  file.path(dirname(normalizePath(sub("^--file=", "", script_hit), winslash = "/")), "..", ".."),
  winslash = "/"
)

output_dir <- file.path(root, "docs", "figures")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_path <- file.path(output_dir, "workflow.svg")

xml_escape <- function(value) {
  value <- gsub("&", "&amp;", value, fixed = TRUE)
  value <- gsub("<", "&lt;", value, fixed = TRUE)
  value <- gsub(">", "&gt;", value, fixed = TRUE)
  value
}

box <- function(x, y, width, height, fill, stroke, title, lines) {
  title <- xml_escape(title)
  lines <- xml_escape(lines)
  text_lines <- c(
    sprintf('<text x="%.1f" y="%.1f" class="box-title" text-anchor="middle">%s</text>', x + width / 2, y + 33, title),
    vapply(seq_along(lines), function(i) {
      sprintf(
        '<text x="%.1f" y="%.1f" class="box-copy" text-anchor="middle">%s</text>',
        x + width / 2,
        y + 60 + (i - 1L) * 22,
        lines[[i]]
      )
    }, character(1L))
  )
  c(
    sprintf('<rect x="%d" y="%d" width="%d" height="%d" rx="15" fill="%s" stroke="%s" stroke-width="2"/>', x, y, width, height, fill, stroke),
    text_lines
  )
}

arrow <- function(x1, y1, x2, y2, dashed = FALSE) {
  dash <- if (dashed) ' stroke-dasharray="8 6"' else ""
  sprintf('<path d="M %d %d L %d %d" class="arrow"%s/>', x1, y1, x2, y2, dash)
}

svg <- c(
  '<?xml version="1.0" encoding="UTF-8"?>',
  '<svg xmlns="http://www.w3.org/2000/svg" width="1500" height="600" viewBox="0 0 1500 600" role="img" aria-labelledby="title description">',
  '<title id="title">Reproducible option portfolio workflow</title>',
  '<desc id="description">Licensed and public inputs pass through validation, monthly sample construction, filtering and forecasting, position-limited optimization, and numerical validation. A public synthetic fixture exercises the same computational path.</desc>',
  '<defs>',
  '  <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto"><polygon points="0 0, 10 3.5, 0 7" fill="#44546A"/></marker>',
  '  <style>',
  '    .title { font: 700 30px Arial, sans-serif; fill: #172B4D; }',
  '    .subtitle { font: 16px Arial, sans-serif; fill: #44546A; }',
  '    .box-title { font: 700 17px Arial, sans-serif; fill: #172B4D; }',
  '    .box-copy { font: 14px Arial, sans-serif; fill: #253858; }',
  '    .arrow { stroke: #44546A; stroke-width: 3; fill: none; marker-end: url(#arrowhead); }',
  '    .label { font: 700 13px Arial, sans-serif; fill: #6B778C; letter-spacing: 1px; }',
  '  </style>',
  '</defs>',
  '<rect width="1500" height="600" fill="#FFFFFF"/>',
  '<text x="750" y="45" class="title" text-anchor="middle">Reproducible option portfolio workflow</text>',
  '<text x="750" y="75" class="subtitle" text-anchor="middle">One R entry point · licensed observations remain outside the public repository</text>',
  '<text x="45" y="125" class="label">INPUTS</text>',
  box(35, 145, 235, 125, "#FFF3E0", "#D97706", "Licensed OptionMetrics", c("three documented exports", "quotes · index prices · rates")),
  box(35, 330, 235, 125, "#E8F3FF", "#1976D2", "Public auxiliary sources", c("Yahoo · pinned CRAN DJIA", "FRED VXD · Oxford-Man subset")),
  box(325, 235, 190, 135, "#F4F5F7", "#6B778C", "Input controls", c("schemas and dates", "fingerprints and provenance", "private-data boundary")),
  box(575, 235, 175, 135, "#E9F7EF", "#238636", "Step 1", c("monthly expirations", "underlying and rates", "canonical checks")),
  box(810, 235, 185, 135, "#E9F7EF", "#238636", "Prepare scenarios", c("parity filtering", "volatility forecasts", "bid-ask returns")),
  box(1055, 235, 185, 135, "#F3EEFF", "#7E57C2", "Optimize", c("position limit", "optional solvency", "margin diagnostic")),
  box(1300, 235, 165, 135, "#FFF0F6", "#C2185B", "Validate outputs", c("tables and wealth", "constraints", "paper tolerances")),
  box(325, 440, 190, 105, "#E8F3FF", "#1976D2", "Synthetic fixture", c("generated public inputs", "46 integration checks")),
  arrow(270, 207, 325, 270),
  arrow(270, 392, 325, 335),
  arrow(515, 302, 575, 302),
  arrow(750, 302, 810, 302),
  arrow(995, 302, 1055, 302),
  arrow(1240, 302, 1300, 302),
  arrow(515, 492, 662, 370, dashed = TRUE),
  '<text x="750" y="575" class="subtitle" text-anchor="middle">Rscript reproduce.R  →  data construction  →  portfolio results  →  numerical and provenance checks</text>',
  '</svg>'
)

writeLines(svg, output_path, useBytes = TRUE)
cat(sprintf("Wrote %s\n", output_path))
