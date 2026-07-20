source("R/cleaning-utils.R")

source_file <- "data-standardized/ebmud/2026-05-22-v01.gpkg"
layer <- "restoration_projects"
report_dir <- "reports/project-name-corrections"
review_files <- c("funding-source-updates.csv", "project-description-updates.csv")

name_corrections <- c(
  "Mokelumne River - MRDUA Large Floodplain Project" =
    "Mokelumne River Day Use Area Large Floodplain Project",
  "Mokelumne River - Gravel Maintenance Project - Early Implementation Projects" =
    "Mokelumne River Gravel Maintenance Project - Early Implementation",
  "Mokelumne River - Floodplain Restoration Projects - Early Implementation Projects" =
    "Mokelumne River Floodplain Restoration Project - Early Implementation",
  "Mokelumne River - CE Large Floodplain Restoration Project" =
    "Mokelumne River Conservation Easement Large Floodplain Restoration Project",
  "Mokelumne River - In Channel Rearing Habitat Restoration Project" =
    "Mokelumne River In-Channel Rearing Habitat Restoration Project",
  "Mokelumne River - Gravel Maintenance Project – Current and Future Maintenance Projects" =
    "Mokelumne River Gravel Maintenance Project"
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
  stop("Not every requested Mokelumne project-name correction matched the EBMUD source file.", call. = FALSE)
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
audit_csv <- file.path(report_dir, paste0(report_date, "_mokelumne_applied.csv"))
audit_md <- file.path(report_dir, paste0(report_date, "_mokelumne_applied.md"))

readr::write_csv(matched, audit_csv)
readr::write_lines(
  c(
    paste0("# Mokelumne Project-Name Corrections ", report_date),
    "",
    "## Summary",
    "",
    paste0("- Applied ", nrow(matched), " requested EBMUD project-name corrections."),
    "- Updated the funding-source and project-description review CSVs to preserve project-name matching in future update runs.",
    "- Raw submissions were not modified."
  ),
  audit_md
)

message("Applied ", nrow(matched), " Mokelumne project-name corrections.")
message("Wrote ", audit_csv)
