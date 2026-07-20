source("R/cleaning-utils.R")

source_file <- "data-standardized/ywa/2026-05-23-v01.gpkg"
layer <- "restoration_projects"
report_dir <- "reports/yuba-total-acreage-correction"

acreage_corrections <- c(
  "Hallwood Side Channel and Floodplain Restoration Project" = 158,
  "Lower Long Bar Habitat Enhancement Project" = 62.4,
  "Upper Rose Bar Habitat Enhancement Project" = 43
)

data <- sf::st_read(source_file, layer = layer, quiet = TRUE)
audit <- data |>
  sf::st_drop_geometry() |>
  dplyr::filter(project_name %in% names(acreage_corrections)) |>
  dplyr::transmute(
    project_name,
    previous_acreage = acreage,
    updated_acreage = unname(acreage_corrections[project_name])
  )

if (nrow(audit) != length(acreage_corrections)) {
  stop("Not every requested Yuba project matched the standardized source file.", call. = FALSE)
}

data <- data |>
  dplyr::mutate(
    acreage = dplyr::if_else(
      project_name %in% names(acreage_corrections),
      unname(acreage_corrections[project_name]),
      acreage
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
    paste0("# Yuba Total-Acreage Correction ", report_date),
    "",
    "## Summary",
    "",
    "- Updated total project acreage for Hallwood, Lower Long Bar, and Upper Rose Bar.",
    "- Habitat-type acreage fields were preserved.",
    "- Raw submissions were not modified."
  ),
  audit_md
)

message("Updated total acreage for ", nrow(audit), " Yuba projects.")
message("Wrote ", audit_csv)
