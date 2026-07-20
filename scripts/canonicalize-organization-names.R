source("R/cleaning-utils.R")

funding_review_csv <- "funding-source-updates.csv"
report_dir <- "reports/organization-name-canonicalization"
layer <- "restoration_projects"

submissions <- tibble::tribble(
  ~source_slug, ~source_file,
  "dwr", "data-standardized/dwr/2026-06-19-v01.gpkg",
  "ebmud", "data-standardized/ebmud/2026-05-22-v01.gpkg",
  "sbfca", "data-standardized/sbfca/2026-05-22-v01.gpkg",
  "scwa", "data-standardized/scwa/2026-05-22-v01.gpkg",
  "sfpuc", "data-standardized/sfpuc/2026-05-22-v01.gpkg",
  "water-forum", "data-standardized/water-forum/2026-05-27-v01.gpkg",
  "ywa", "data-standardized/ywa/2026-05-23-v01.gpkg"
)

organization_names <- c(
  EBMUD = "East Bay Municipal Utility District",
  SFPUC = "San Francisco Public Utilities Commission",
  SCWA = "Solano County Water Agency",
  MID = "Modesto Irrigation District",
  TID = "Turlock Irrigation District",
  CDFW = "California Department of Fish and Wildlife",
  CNRA = "California Natural Resources Agency",
  USFWS = "U.S. Fish and Wildlife Service"
)

canonicalize_values <- function(values) {
  purrr::map_chr(values, function(value) {
    if (is.na(value)) {
      return(NA_character_)
    }

    result <- value
    for (acronym in names(organization_names)) {
      result <- gsub(
        paste0("(?<![[:alnum:]])", acronym, "(?![[:alnum:]])"),
        organization_names[[acronym]],
        result,
        perl = TRUE
      )
    }
    result
  })
}

applied <- purrr::pmap_dfr(submissions, function(source_slug, source_file) {
  data <- sf::st_read(source_file, layer = layer, quiet = TRUE)
  attributes <- sf::st_drop_geometry(data)
  character_fields <- names(attributes)[vapply(attributes, is.character, logical(1))]
  value_fields <- setdiff(character_fields, "project_name")

  before <- attributes |>
    dplyr::mutate(source_slug = source_slug, .before = 1) |>
    dplyr::select(source_slug, project_name, dplyr::all_of(value_fields)) |>
    tidyr::pivot_longer(
      dplyr::all_of(value_fields),
      names_to = "field",
      values_to = "previous_value"
    ) |>
    dplyr::mutate(updated_value = canonicalize_values(previous_value)) |>
    dplyr::filter(!is.na(previous_value), previous_value != updated_value)

  data <- data |>
    dplyr::mutate(
      dplyr::across(dplyr::all_of(character_fields), canonicalize_values)
    )

  unlink(source_file)
  sf::st_write(data, source_file, layer = layer, quiet = TRUE)
  before
})

if (file.exists(funding_review_csv)) {
  funding_review <- readr::read_csv(funding_review_csv, show_col_types = FALSE) |>
    dplyr::mutate(
      current_funding_sources = canonicalize_values(current_funding_sources),
      updated_funding_sources = canonicalize_values(updated_funding_sources)
    )
  readr::write_csv(funding_review, funding_review_csv, na = "")
}

dir_create(report_dir)
report_date <- format(Sys.Date(), "%Y-%m-%d")
audit_csv <- file.path(report_dir, paste0(report_date, "_applied.csv"))
audit_md <- file.path(report_dir, paste0(report_date, "_applied.md"))
readr::write_csv(applied, audit_csv, na = "")
readr::write_lines(
  c(
    paste0("# Organization-Name Canonicalization ", report_date),
    "",
    "## Summary",
    "",
    paste0("- Applied ", nrow(applied), " field-level acronym expansions."),
    "- Expanded EBMUD, SFPUC, SCWA, MID, TID, CDFW, CNRA, and USFWS in standardized text fields.",
    "- Updated the funding-source review CSV so future funding-update runs preserve these full names.",
    "- Raw submissions were not modified."
  ),
  audit_md
)

message("Applied ", nrow(applied), " field-level organization-name updates.")
message("Wrote ", audit_csv)
