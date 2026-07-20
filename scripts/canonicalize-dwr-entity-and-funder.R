source("R/cleaning-utils.R")

funding_review_csv <- "funding-source-updates.csv"
report_dir <- "reports/dwr-name-canonicalization"
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

canonical_name <- "California Department of Water Resources"

canonicalize_values <- function(values) {
  purrr::map_chr(values, function(value) {
    if (is.na(value)) {
      return(NA_character_)
    }

    parts <- stringr::str_split(value, ";\\s*")[[1]]
    parts[parts == "DWR"] <- canonical_name
    paste(parts, collapse = "; ")
  })
}

applied <- purrr::pmap_dfr(submissions, function(source_slug, source_file) {
  data <- sf::st_read(source_file, layer = layer, quiet = TRUE)
  before <- data |>
    sf::st_drop_geometry() |>
    dplyr::transmute(
      source_slug,
      project_name,
      previous_lead_entity = lead_entity,
      updated_lead_entity = canonicalize_values(lead_entity),
      previous_funding_sources = funding_sources,
      updated_funding_sources = canonicalize_values(funding_sources)
    ) |>
    dplyr::filter(
      previous_lead_entity != updated_lead_entity |
        previous_funding_sources != updated_funding_sources
    )

  data <- data |>
    dplyr::mutate(
      lead_entity = canonicalize_values(lead_entity),
      funding_sources = canonicalize_values(funding_sources)
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
    paste0("# DWR Name Canonicalization ", report_date),
    "",
    "## Summary",
    "",
    paste0("- Updated ", nrow(applied), " standardized project records."),
    "- Replaced standalone `DWR` values in `lead_entity` and semicolon-delimited `funding_sources` with `California Department of Water Resources`.",
    "- Updated the funding-source review CSV so rerunning its update workflow preserves the canonical name.",
    "- Raw submissions were not modified."
  ),
  audit_md
)

message("Updated ", nrow(applied), " project records.")
message("Wrote ", audit_csv)
