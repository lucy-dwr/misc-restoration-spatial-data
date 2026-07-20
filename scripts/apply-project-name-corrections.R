source("R/cleaning-utils.R")

source_file <- "data-standardized/dwr/2026-06-19-v01.gpkg"
layer <- "restoration_projects"
report_dir <- "reports/project-name-corrections"
review_files <- c("funding-source-updates.csv", "project-description-updates.csv")

name_corrections <- c(
  "McCormick-Williamson Tract (MWT) Monitoring Project (Phase B)" =
    "McCormack-Williamson Tract - Phase B",
  "Dutch Slough Tidal Restoration Project (Phase 2)" =
    "Dutch Slough Tidal Restoration Project - Phase 2",
  "P68 Feather River Salmon Habitat Improvement Project" =
    "Feather River Salmonid Spawning Habitat Improvement - P68"
)

data <- sf::st_read(source_file, layer = layer, quiet = TRUE)
matched <- data |>
  sf::st_drop_geometry() |>
  dplyr::filter(project_name %in% names(name_corrections)) |>
  dplyr::transmute(
    project_name,
    updated_project_name = unname(name_corrections[project_name])
  )

if (nrow(matched) != length(name_corrections)) {
  stop("Not every requested project-name correction matched the DWR source file.", call. = FALSE)
}

data <- data |>
  dplyr::mutate(project_name = dplyr::recode(project_name, !!!name_corrections))

unlink(source_file)
sf::st_write(data, source_file, layer = layer, quiet = TRUE)

for (review_file in review_files[file.exists(review_files)]) {
  review <- readr::read_csv(review_file, show_col_types = FALSE) |>
    dplyr::mutate(project_name = dplyr::recode(project_name, !!!name_corrections))
  readr::write_csv(review, review_file, na = "")
}

dir_create(report_dir)
report_date <- format(Sys.Date(), "%Y-%m-%d")
audit_csv <- file.path(report_dir, paste0(report_date, "_applied.csv"))
audit_md <- file.path(report_dir, paste0(report_date, "_applied.md"))

readr::write_csv(matched, audit_csv)
readr::write_lines(
  c(
    paste0("# Project-Name Corrections ", report_date),
    "",
    "## Summary",
    "",
    paste0("- Applied ", nrow(matched), " requested DWR project-name corrections."),
    "- Updated the funding-source and project-description review CSVs to preserve project-name matching in future update runs.",
    "- Raw submissions were not modified."
  ),
  audit_md
)

message("Applied ", nrow(matched), " project-name corrections.")
message("Wrote ", audit_csv)
