source("R/cleaning-utils.R")

source_file <- "data-standardized/ywa/2026-05-23-v01.gpkg"
layer <- "restoration_projects"
report_dir <- "reports/yuba-lead-entity-correction"
project_names <- c(
  "Hallwood Side Channel and Floodplain Restoration Project",
  "Lower Long Bar Habitat Enhancement Project",
  "Upper Long Bar Habitat Enhancement Project",
  "Upper Rose Bar Habitat Enhancement Project"
)
updated_lead_entity <- "South Yuba River Citizens League; Yuba Water Agency"

data <- sf::st_read(source_file, layer = layer, quiet = TRUE)
audit <- data |>
  sf::st_drop_geometry() |>
  dplyr::filter(project_name %in% project_names) |>
  dplyr::transmute(
    project_name,
    previous_lead_entity = lead_entity,
    updated_lead_entity = updated_lead_entity
  )

if (nrow(audit) != length(project_names)) {
  stop("Not every requested Yuba project matched the standardized source file.", call. = FALSE)
}

data <- data |>
  dplyr::mutate(
    lead_entity = dplyr::if_else(
      project_name %in% project_names,
      updated_lead_entity,
      lead_entity
    )
  )

unlink(source_file)
sf::st_write(data, source_file, layer = layer, quiet = TRUE)

dir_create(report_dir)
report_date <- format(Sys.Date(), "%Y-%m-%d")
audit_csv <- file.path(report_dir, paste0(report_date, "_applied.csv"))
audit_md <- file.path(report_dir, paste0(report_date, "_applied.md"))
readr::write_csv(audit, audit_csv, na = "")
readr::write_lines(
  c(
    paste0("# Yuba Lead-Entity Correction ", report_date),
    "",
    "## Summary",
    "",
    "- Assigned South Yuba River Citizens League and Yuba Water Agency as co-lead entities for Hallwood, Lower Long Bar, Upper Long Bar, and Upper Rose Bar.",
    "- Raw submissions were not modified."
  ),
  audit_md
)

message("Updated lead entities for ", nrow(audit), " Yuba projects.")
message("Wrote ", audit_csv)
