#!/usr/bin/env Rscript

# Produce a pipeline-shaped smoke-test submission from a legacy standardized
# GeoPackage. This one-time transition utility makes only exact project-name
# matches to a selected immutable registry export and stops on every unresolved
# or non-eligible ID. Ordinary compilers must carry project_id from their
# registry lookup before this stage.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4) {
  stop(
    paste(
      "Usage: Rscript --vanilla scripts/backfill-project-ids-for-smoke-test.R",
      "<input.gpkg> <registry.csv> <schema.yaml> <output-directory>"
    ),
    call. = FALSE
  )
}

input_gpkg <- normalizePath(args[[1]], mustWork = TRUE)
registry_csv <- normalizePath(args[[2]], mustWork = TRUE)
schema_file <- normalizePath(args[[3]], mustWork = TRUE)
output_dir <- args[[4]]
output_gpkg <- file.path(output_dir, "projects.gpkg")
validation_csv <- file.path(output_dir, "project-id-validation.csv")
manifest_json <- file.path(output_dir, "submission.json")

if (file.exists("renv/activate.R")) {
  source("renv/activate.R")
}

source("R/cleaning-utils.R")

`%||%` <- function(value, default) if (is.null(value)) default else value
schema <- yaml::yaml.load_file(schema_file)

profile_fields <- function(class_name) {
  class_def <- schema$classes[[class_name]]
  if (is.null(class_def)) {
    stop("Schema class not found: ", class_name, call. = FALSE)
  }
  inherited <- if (is.null(class_def$is_a)) character() else profile_fields(class_def$is_a)
  unique(c(inherited, class_def$slots %||% character()))
}

registry <- readr::read_csv(
  registry_csv,
  show_col_types = FALSE,
  col_types = readr::cols(.default = readr::col_character())
)
required_registry_columns <- c("project_id", "status", "project_name")
missing_registry_columns <- setdiff(required_registry_columns, names(registry))
if (length(missing_registry_columns) > 0) {
  stop("Registry export is missing column(s): ", paste(missing_registry_columns, collapse = ", "), call. = FALSE)
}

registry <- registry |>
  dplyr::mutate(
    project_id = null_to_na_chr(project_id),
    project_name = null_to_na_chr(project_name),
    status = null_to_na_chr(status)
  )

if (anyDuplicated(registry$project_id[!is.na(registry$project_id)])) {
  stop("Registry export contains duplicate project_id values.", call. = FALSE)
}
if (anyDuplicated(registry$project_name[!is.na(registry$project_name)])) {
  stop("Registry export contains duplicate project_name values; exact legacy matching is unsafe.", call. = FALSE)
}

input <- sf::st_read(input_gpkg, layer = "restoration_projects", quiet = TRUE) |>
  sf::st_zm(drop = TRUE, what = "ZM") |>
  sf::st_transform(3310) |>
  dplyr::mutate(project_name = null_to_na_chr(project_name))

if (anyDuplicated(input$project_name[!is.na(input$project_name)])) {
  stop("Input contains duplicate project_name values; exact legacy matching is unsafe.", call. = FALSE)
}

linked <- input |>
  dplyr::left_join(
    dplyr::select(registry, project_name, project_id, registry_status = status),
    by = "project_name"
  )

validation <- linked |>
  sf::st_drop_geometry() |>
  dplyr::transmute(
    severity = dplyr::case_when(
      is.na(project_name) ~ "error",
      is.na(project_id) ~ "error",
      registry_status != "eligible" ~ "error",
      TRUE ~ "info"
    ),
    check = dplyr::case_when(
      is.na(project_name) ~ "project_id_missing_project_name",
      is.na(project_id) ~ "project_id_unknown",
      registry_status != "eligible" ~ "project_id_not_eligible",
      TRUE ~ "project_id_registry_match"
    ),
    feature_id = dplyr::coalesce(project_name, "<missing project_name>"),
    field = "project_id",
    submitted_value = NA_character_,
    standardized_value = project_id,
    message = dplyr::case_when(
      is.na(project_name) ~ "Cannot resolve project_id without project_name.",
      is.na(project_id) ~ "No exact project-name match exists in the selected registry export.",
      registry_status != "eligible" ~ paste0("Registry status is ", registry_status, "; project_id is not eligible."),
      TRUE ~ "Exact project-name match to an eligible registry record."
    )
  )

dir_create(output_dir)
readr::write_csv(validation, validation_csv, na = "")

if (any(validation$severity == "error")) {
  stop("Project-ID validation failed; see ", validation_csv, call. = FALSE)
}

submission_fields <- setdiff(profile_fields("RestorationProjectSubmission"), "geometry")
missing_submission_fields <- setdiff(submission_fields, names(linked))
if (length(missing_submission_fields) > 0) {
  stop("Input is missing schema field(s): ", paste(missing_submission_fields, collapse = ", "), call. = FALSE)
}

submission <- linked |>
  dplyr::select(dplyr::all_of(submission_fields))

if (file.exists(output_gpkg) || file.exists(manifest_json)) {
  stop("Refusing to overwrite an existing smoke-test submission: ", output_dir, call. = FALSE)
}

sf::st_write(submission, output_gpkg, layer = "restoration_projects", quiet = TRUE)
manifest <- list(
  submission_id = "legacy-multi-agency-registry-linked-smoke-test",
  organization = "Healthy Rivers and Landscapes",
  organization_code = "HRL",
  dataset_name = "Registry-linked legacy multi-agency smoke test",
  submission_type = "update",
  submission_scope = "partial_update",
  data_as_of = "2026-08-24",
  data_steward_name = "HRL Data Steward",
  data_steward_email = "data-steward@example.org",
  primary_file = basename(output_gpkg)
)
json_escape <- function(value) {
  value <- gsub("\\\\", "\\\\\\\\", value)
  gsub("\"", "\\\\\"", value, fixed = TRUE)
}
manifest_lines <- c(
  "{",
  paste0(
    "  \"", names(manifest), "\": \"", vapply(manifest, json_escape, character(1)),
    "\"", ifelse(seq_along(manifest) == length(manifest), "", ",")
  ),
  "}"
)
writeLines(manifest_lines, manifest_json, useBytes = TRUE)

message("Wrote ", output_gpkg)
message("Wrote ", validation_csv)
message("Wrote ", manifest_json)
