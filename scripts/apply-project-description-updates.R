source("R/cleaning-utils.R")

updates_csv <- "project-description-updates.csv"
report_dir <- "reports/project-description-updates"
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
  stop("Project-description update CSV not found: ", updates_csv, call. = FALSE)
}

updates <- readr::read_csv(
  updates_csv,
  show_col_types = FALSE,
  col_types = readr::cols(
    project_name = readr::col_character(),
    original_description = readr::col_character(),
    updated_description = readr::col_character(),
    .default = readr::col_character()
  )
) |>
  dplyr::mutate(
    original_description = null_to_na_chr(original_description),
    updated_description = null_to_na_chr(updated_description)
  )

if (anyDuplicated(updates$project_name) || any(is.na(updates$updated_description))) {
  stop("Each project must appear once and have an updated_description.", call. = FALSE)
}

if (any(nchar(updates$updated_description) > 500L)) {
  too_long <- updates$project_name[nchar(updates$updated_description) > 500L]
  stop("Updated description exceeds the schema limit for: ", paste(too_long, collapse = ", "), call. = FALSE)
}

all_projects <- purrr::pmap_dfr(submissions, function(source_slug, source_file) {
  sf::st_read(source_file, layer = layer, quiet = TRUE) |>
    sf::st_drop_geometry() |>
    dplyr::transmute(source_slug, project_name, project_description)
})

missing_projects <- dplyr::anti_join(updates, all_projects, by = "project_name")
duplicate_projects <- all_projects |>
  dplyr::semi_join(updates, by = "project_name") |>
  dplyr::count(project_name) |>
  dplyr::filter(n > 1)
if (nrow(missing_projects) > 0 || nrow(duplicate_projects) > 0) {
  stop("Each reviewed project must match exactly one standardized record.", call. = FALSE)
}

stale_values <- all_projects |>
  dplyr::inner_join(
    updates |>
      dplyr::select(project_name, expected_description = original_description),
    by = "project_name"
  ) |>
  dplyr::filter(!dplyr::coalesce(project_description == expected_description, FALSE))
if (nrow(stale_values) > 0) {
  stop(
    "Current descriptions no longer match the review CSV: ",
    paste(stale_values$project_name, collapse = ", "),
    call. = FALSE
  )
}

applied <- purrr::pmap_dfr(submissions, function(source_slug, source_file) {
  data <- sf::st_read(source_file, layer = layer, quiet = TRUE)
  source_updates <- updates |>
    dplyr::semi_join(
      data |>
        sf::st_drop_geometry() |>
        dplyr::select(project_name),
      by = "project_name"
    )

  before <- data |>
    sf::st_drop_geometry() |>
    dplyr::select(project_name, previous_description = project_description) |>
    dplyr::inner_join(
      source_updates |>
        dplyr::select(project_name, updated_description),
      by = "project_name"
    ) |>
    dplyr::mutate(source_slug = source_slug, .before = 1)

  data <- data |>
    dplyr::left_join(
      source_updates |>
        dplyr::select(project_name, updated_description),
      by = "project_name"
    ) |>
    dplyr::mutate(project_description = dplyr::coalesce(updated_description, project_description)) |>
    dplyr::select(-updated_description)

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
    paste0("# Project-Description Updates ", report_date),
    "",
    "## Summary",
    "",
    paste0("- Applied ", nrow(applied), " reviewed project-description updates."),
    paste0("- Update input: `", updates_csv, "`."),
    paste0("- Change audit: `", audit_csv, "`."),
    "- Raw submissions were not modified.",
    "- Every replacement description was checked against the schema maximum of 500 characters."
  ),
  audit_md
)

message("Applied ", nrow(applied), " project-description updates.")
message("Wrote ", audit_csv)
message("Wrote ", audit_md)
