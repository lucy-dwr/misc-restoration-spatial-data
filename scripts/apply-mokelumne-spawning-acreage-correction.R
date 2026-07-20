source("R/cleaning-utils.R")

source_file <- "data-standardized/ebmud/2026-05-22-v01.gpkg"
layer <- "restoration_projects"
project_name <- "Mokelumne River Gravel Maintenance Project"
report_dir <- "reports/mokelumne-spawning-acreage-correction"

data <- sf::st_read(source_file, layer = layer, quiet = TRUE)
target <- data |>
  sf::st_drop_geometry() |>
  dplyr::filter(project_name == !!project_name) |>
  dplyr::select(project_name, acreage, acreage_tributary_spawning)

if (nrow(target) != 1 || is.na(target$acreage)) {
  stop("Expected one Mokelumne River Gravel Maintenance Project record with acreage.", call. = FALSE)
}

data <- data |>
  dplyr::mutate(
    acreage_tributary_spawning = dplyr::if_else(
      project_name == !!project_name,
      acreage,
      acreage_tributary_spawning
    )
  )

unlink(source_file)
sf::st_write(data, source_file, layer = layer, quiet = TRUE)

audit <- target |>
  dplyr::transmute(
    project_name,
    previous_acreage_tributary_spawning = acreage_tributary_spawning,
    updated_acreage_tributary_spawning = acreage
  )

dir_create(report_dir)
report_date <- format(Sys.Date(), "%Y-%m-%d")
audit_csv <- file.path(report_dir, paste0(report_date, "_applied.csv"))
audit_md <- file.path(report_dir, paste0(report_date, "_applied.md"))
readr::write_csv(audit, audit_csv, na = "")
readr::write_lines(
  c(
    paste0("# Mokelumne Spawning-Acreage Correction ", report_date),
    "",
    "## Summary",
    "",
    "- Assigned the project's existing total acreage to `acreage_tributary_spawning` for the Mokelumne River Gravel Maintenance Project.",
    "- Total project acreage was preserved.",
    "- Raw submissions were not modified."
  ),
  audit_md
)

message("Applied tributary-spawning acreage correction.")
message("Wrote ", audit_csv)
