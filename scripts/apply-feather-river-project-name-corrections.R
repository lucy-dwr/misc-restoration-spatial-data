source("R/cleaning-utils.R")

source_file <- "data-standardized/dwr/2026-06-19-v01.gpkg"
layer <- "restoration_projects"
report_dir <- "reports/project-name-corrections"
review_files <- c("funding-source-updates.csv", "project-description-updates.csv")

name_corrections <- c(
  "Feather River Salmonid Spawning Habitat Improvement - 2024" =
    "Feather River Salmonid Spawning Habitat Improvement (2024)",
  "Feather River Salmonid Spawning Habitat Improvement - P68" =
    "Feather River Salmonid Spawning Habitat Improvement (Proposition 68)"
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
  stop("Not every requested Feather River project-name correction matched the DWR source file.", call. = FALSE)
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
audit_csv <- file.path(report_dir, paste0(report_date, "_feather_river_applied.csv"))
audit_md <- file.path(report_dir, paste0(report_date, "_feather_river_applied.md"))

readr::write_csv(matched, audit_csv)
readr::write_lines(
  c(
    paste0("# Feather River Project-Name Corrections ", report_date),
    "",
    "## Summary",
    "",
    "- Replaced hyphenated project-name qualifiers with parenthetical qualifiers.",
    "- Expanded `P68` to `Proposition 68` in the project name.",
    "- Updated the funding-source and project-description review CSVs to preserve project-name matching in future update runs.",
    "- Raw submissions were not modified."
  ),
  audit_md
)

message("Applied ", nrow(matched), " Feather River project-name corrections.")
message("Wrote ", audit_csv)
