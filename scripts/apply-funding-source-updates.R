source("R/cleaning-utils.R")

updates_csv <- "funding-source-updates.csv"
report_dir <- "reports/funding-source-updates"
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

if (!file.exists(updates_csv)) {
  stop("Funding-source update CSV not found: ", updates_csv, call. = FALSE)
}

updates <- readr::read_csv(
  updates_csv,
  show_col_types = FALSE,
  col_types = readr::cols(
    project_name = readr::col_character(),
    current_funding_sources = readr::col_character(),
    updated_funding_sources = readr::col_character()
  )
) |>
  dplyr::mutate(
    current_funding_sources = normalize_semicolon_values(current_funding_sources),
    updated_funding_sources = normalize_semicolon_values(updated_funding_sources)
  ) |>
  dplyr::filter(!is.na(updated_funding_sources))

if (anyDuplicated(updates$project_name) || nrow(updates) == 0) {
  stop("Review CSV must contain a non-empty update for each unique project_name.", call. = FALSE)
}

all_projects <- purrr::pmap_dfr(submissions, function(source_slug, source_file) {
  sf::st_read(source_file, layer = layer, quiet = TRUE) |>
    sf::st_drop_geometry() |>
    dplyr::transmute(source_slug, project_name, funding_sources)
})

missing_projects <- dplyr::anti_join(updates, all_projects, by = "project_name")
duplicate_projects <- all_projects |>
  dplyr::semi_join(updates, by = "project_name") |>
  dplyr::count(project_name) |>
  dplyr::filter(n > 1)

if (nrow(missing_projects) > 0 || nrow(duplicate_projects) > 0) {
  stop("Reviewed project names must each match one standardized record.", call. = FALSE)
}

current_values <- all_projects |>
  dplyr::inner_join(
    updates |>
      dplyr::select(project_name, expected_funding_sources = current_funding_sources),
    by = "project_name"
  ) |>
  dplyr::mutate(funding_sources = normalize_semicolon_values(funding_sources))

stale_values <- current_values |>
  dplyr::filter(!dplyr::coalesce(funding_sources == expected_funding_sources, FALSE))
if (nrow(stale_values) > 0) {
  stop(
    "Current funding-source values no longer match the review CSV: ",
    paste(stale_values$project_name, collapse = ", "),
    call. = FALSE
  )
}

applied <- purrr::pmap_dfr(submissions, function(source_slug, source_file) {
  data <- sf::st_read(source_file, layer = layer, quiet = TRUE)
  source_updates <- updates |>
    dplyr::inner_join(
      data |>
        sf::st_drop_geometry() |>
        dplyr::select(project_name),
      by = "project_name"
    )

  if (nrow(source_updates) == 0) {
    return(tibble::tibble())
  }

  before <- data |>
    sf::st_drop_geometry() |>
    dplyr::select(project_name, previous_funding_sources = funding_sources) |>
    dplyr::inner_join(
      source_updates |>
        dplyr::select(project_name, updated_funding_sources),
      by = "project_name"
    ) |>
    dplyr::mutate(source_slug = source_slug, .before = 1)

  data <- data |>
    dplyr::left_join(
      source_updates |>
        dplyr::select(project_name, updated_funding_sources),
      by = "project_name"
    ) |>
    dplyr::mutate(funding_sources = dplyr::coalesce(updated_funding_sources, funding_sources)) |>
    dplyr::select(-updated_funding_sources)

  unlink(source_file)
  sf::st_write(data, source_file, layer = layer, quiet = TRUE)
  before
})

dir_create(report_dir)
report_date <- format(Sys.Date(), "%Y-%m-%d")
audit_csv <- file.path(report_dir, paste0(report_date, "_applied.csv"))
audit_md <- file.path(report_dir, paste0(report_date, "_applied.md"))

readr::write_csv(applied, audit_csv, na = "")
readr::write_lines(
  c(
    paste0("# Funding-Source Updates ", report_date),
    "",
    "## Summary",
    "",
    paste0("- Applied ", nrow(applied), " reviewed funding-source updates."),
    paste0("- Update input: `", updates_csv, "`."),
    paste0("- Change audit: `", audit_csv, "`."),
    "- Raw submissions were not modified.",
    "- Updated values use semicolon-delimited text supplied in the review CSV."
  ),
  audit_md
)

message("Applied ", nrow(applied), " funding-source updates.")
message("Wrote ", audit_csv)
message("Wrote ", audit_md)
