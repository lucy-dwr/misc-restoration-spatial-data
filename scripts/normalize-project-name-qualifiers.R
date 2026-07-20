source("R/cleaning-utils.R")

layer <- "restoration_projects"
report_dir <- "reports/project-name-corrections"
review_files <- c("funding-source-updates.csv", "project-description-updates.csv")

corrections <- tibble::tribble(
  ~source_file, ~project_name, ~updated_project_name,
  "data-standardized/dwr/2026-06-19-v01.gpkg", "McCormack-Williamson Tract - Phase B", "McCormack-Williamson Tract (Phase B)",
  "data-standardized/dwr/2026-06-19-v01.gpkg", "Dutch Slough Tidal Restoration Project - Phase 2", "Dutch Slough Tidal Restoration Project (Phase 2)",
  "data-standardized/ebmud/2026-05-22-v01.gpkg", "Mokelumne River Gravel Maintenance Project - Early Implementation", "Mokelumne River Gravel Maintenance Project (Early Implementation)",
  "data-standardized/ebmud/2026-05-22-v01.gpkg", "Mokelumne River Floodplain Restoration Project - Early Implementation", "Mokelumne River Floodplain Restoration Project (Early Implementation)",
  "data-standardized/water-forum/2026-05-27-v01.gpkg", "Upper River Bend, Phase 1", "Upper River Bend (Phase 1)"
)

for (source_file in unique(corrections$source_file)) {
  file_corrections <- corrections |>
    dplyr::filter(source_file == !!source_file)
  data <- sf::st_read(source_file, layer = layer, quiet = TRUE)
  matches <- data |>
    sf::st_drop_geometry() |>
    dplyr::filter(project_name %in% file_corrections$project_name)

  if (nrow(matches) != nrow(file_corrections)) {
    stop("Not every requested correction matched ", source_file, call. = FALSE)
  }

  name_map <- stats::setNames(file_corrections$updated_project_name, file_corrections$project_name)
  data <- data |>
    dplyr::mutate(project_name = dplyr::recode(project_name, !!!name_map))

  unlink(source_file)
  sf::st_write(data, source_file, layer = layer, quiet = TRUE)
}

name_map <- stats::setNames(corrections$updated_project_name, corrections$project_name)
for (review_file in review_files[file.exists(review_files)]) {
  review <- readr::read_csv(review_file, show_col_types = FALSE) |>
    dplyr::mutate(project_name = dplyr::recode(project_name, !!!name_map))
  readr::write_csv(review, review_file, na = "")
}

dir_create(report_dir)
report_date <- format(Sys.Date(), "%Y-%m-%d")
audit_csv <- file.path(report_dir, paste0(report_date, "_qualifier_normalization.csv"))
audit_md <- file.path(report_dir, paste0(report_date, "_qualifier_normalization.md"))
readr::write_csv(corrections |>
  dplyr::select(project_name, updated_project_name), audit_csv)
readr::write_lines(
  c(
    paste0("# Project-Name Qualifier Normalization ", report_date),
    "",
    "## Summary",
    "",
    "- Normalized phase and implementation qualifiers as parenthetical project-name modifiers.",
    "- Updated the funding-source and project-description review CSVs to preserve project-name matching in future update runs.",
    "- Raw submissions were not modified."
  ),
  audit_md
)

message("Normalized ", nrow(corrections), " project names.")
message("Wrote ", audit_csv)
