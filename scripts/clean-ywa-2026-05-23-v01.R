source("R/cleaning-utils.R")

paths <- submission_paths("ywa", "2026-05-23-v01")
source_layer <- "Yuba_HRL_Projects"
source_workbook <- file.path(dirname(paths$source_gpkg), "2026-05-23_v01.xlsx")

dir_create_submission(paths)

schema_profile <- load_schema_profile(paths$schema_file)
schema <- schema_profile$schema
attribute_fields <- schema_profile$attribute_fields
required_attribute_fields <- schema_profile$required_attribute_fields

inventory_gpkg_rows <- inventory_gpkg(paths$source_gpkg)
inventory_workbook <- tibble::tibble(
  source_file = source_workbook,
  layer_name = "project attribute tabs: HW; LLB; ULB; URB",
  geometry_type = NA_character_,
  features = 4L,
  fields = 26L,
  crs_name = NA_character_
)
inventory <- dplyr::bind_rows(inventory_gpkg_rows, inventory_workbook)
readr::write_csv(inventory, paths$inventory_csv)

inventory_source <- inventory_gpkg_rows |>
  dplyr::filter(layer_name == source_layer)
raw <- sf::st_read(paths$source_gpkg, layer = source_layer, quiet = TRUE)

first_semicolon_value <- function(x) {
  x <- null_to_na_chr(x)
  purrr::map_chr(x, function(value) {
    if (is.na(value)) {
      return(NA_character_)
    }
    values <- split_semicolon_values(value)
    if (length(values) == 0) {
      NA_character_
    } else {
      values[[1]]
    }
  })
}

target_species_map <- c(
  "Steelhead Trout" = "Steelhead trout"
)

cleaned <- raw |>
  dplyr::mutate(
    submitted_contact_name = contact_name,
    submitted_contact_email = contact_email,
    submitted_early_implementation = early_implementation,
    submitted_target_species = target_species,
    project_name = null_to_na_chr(project_name),
    project_description = stringr::str_trunc(null_to_na_chr(project_description), 500, ellipsis = ""),
    project_stage = normalize_semicolon_values(project_stage),
    contact_name = first_semicolon_value(contact_name),
    contact_email = stringr::str_to_lower(first_semicolon_value(contact_email)),
    lead_entity = normalize_semicolon_values(lead_entity),
    contractors = normalize_semicolon_values(contractors),
    early_implementation = dplyr::case_when(
      stringr::str_to_lower(null_to_na_chr(early_implementation)) == "true" ~ TRUE,
      stringr::str_to_lower(null_to_na_chr(early_implementation)) == "false" ~ FALSE,
      TRUE ~ NA
    ),
    construction_start_year = as.integer(construction_start_year),
    construction_completion_year = as.integer(constructon_completion_year),
    construction_completion_year_comments =
      stringr::str_trunc(null_to_na_chr(construction_completion_year_comments), 250, ellipsis = ""),
    estimated_budget = as.integer(round(estimated_budget)),
    estimated_budget_comments = stringr::str_trunc(null_to_na_chr(estimated_budget_comments), 500, ellipsis = ""),
    funding_secured = as.integer(round(funding_secured)),
    funding_gap = as.integer(round(funding_gap)),
    funding_sources = normalize_semicolon_values(funding_sources),
    system = null_to_na_chr(system),
    project_type = normalize_semicolon_values(project_type),
    acreage = as.numeric(acreage),
    acreage_bypass_floodplain = as.numeric(acreage_bypass_floodplain),
    acreage_fish_food = as.numeric(acreage_fish_food),
    acreage_tributary_floodplain = as.numeric(acreage_tributary_floodplain),
    acreage_tributary_rearing = as.numeric(acreage_tributary_rearing),
    acreage_tributary_spawning = as.numeric(acreage_tributary_spawning),
    acreage_tidal_wetland = as.numeric(acreage_tidal_wetland),
    target_species = purrr::map_chr(normalize_semicolon_values(target_species), function(value) {
      if (is.na(value)) {
        return(NA_character_)
      }
      values <- split_semicolon_values(value)
      paste(dplyr::recode(values, !!!target_species_map, .default = values), collapse = "; ")
    })
  ) |>
  sf::st_zm(drop = TRUE, what = "ZM") |>
  sf::st_make_valid() |>
  sf::st_transform(3310) |>
  dplyr::select(dplyr::all_of(attribute_fields))

validation <- validation_tbl()

validation <- append_validation(
  validation,
  "info",
  "source_inventory",
  message = paste0(
    "Read ", inventory_source$features[[1]], " features from ", source_layer,
    "; source CRS: ", inventory_source$crs_name[[1]], "."
  )
)

validation <- append_validation(
  validation,
  "info",
  "source_inventory",
  message = "Workbook project tabs were inventoried as supplemental submitted attributes; GeoPackage attributes were used with the submitted geometries."
)

validation <- append_validation(
  validation,
  "info",
  "profile",
  message = "Output targets RestorationProjectSubmission; project_id and update_date were omitted."
)

validation <- append_validation(
  validation,
  "info",
  "geometry_standardization",
  message = "Dropped Z/M ordinates, repaired geometries with sf::st_make_valid(), and transformed to EPSG:3310."
)

contact_changes <- raw |>
  sf::st_drop_geometry() |>
  dplyr::transmute(
    feature_id = project_name,
    contact_name_submitted = contact_name,
    contact_name_standardized = cleaned$contact_name,
    contact_email_submitted = contact_email,
    contact_email_standardized = cleaned$contact_email
  ) |>
  dplyr::filter(
    contact_name_submitted != contact_name_standardized |
      contact_email_submitted != contact_email_standardized
  )

for (i in seq_len(nrow(contact_changes))) {
  validation <- append_validation(
    validation, "warning", "value_repair", contact_changes$feature_id[[i]],
    "contact_name/contact_email",
    paste(contact_changes$contact_name_submitted[[i]], contact_changes$contact_email_submitted[[i]], sep = " / "),
    paste(contact_changes$contact_name_standardized[[i]], contact_changes$contact_email_standardized[[i]], sep = " / "),
    "Selected the first submitted semicolon-delimited contact as the schema primary contact."
  )
}

early_implementation_changes <- raw |>
  sf::st_drop_geometry() |>
  dplyr::transmute(
    feature_id = project_name,
    submitted = early_implementation,
    standardized = cleaned$early_implementation
  )

for (i in seq_len(nrow(early_implementation_changes))) {
  validation <- append_validation(
    validation, "warning", "value_repair", early_implementation_changes$feature_id[[i]], "early_implementation",
    early_implementation_changes$submitted[[i]], early_implementation_changes$standardized[[i]],
    "Converted submitted true/false text to schema boolean value."
  )
}

target_species_changes <- raw |>
  sf::st_drop_geometry() |>
  dplyr::transmute(
    feature_id = project_name,
    submitted = target_species,
    standardized = cleaned$target_species
  ) |>
  dplyr::filter(submitted != standardized)

for (i in seq_len(nrow(target_species_changes))) {
  validation <- append_validation(
    validation, "warning", "value_repair", target_species_changes$feature_id[[i]], "target_species",
    target_species_changes$submitted[[i]], target_species_changes$standardized[[i]],
    "Standardized target-species capitalization to schema enum value."
  )
}

missing_acreage <- cleaned |>
  sf::st_drop_geometry() |>
  dplyr::filter(is.na(acreage))

for (i in seq_len(nrow(missing_acreage))) {
  validation <- append_validation(
    validation, "warning", "acreage_missing", missing_acreage$project_name[[i]],
    "acreage", NA_character_, NA_character_,
    "Submitted acreage is missing; geometry-derived acreage was not substituted."
  )
}

completion_comment_issues <- cleaned |>
  sf::st_drop_geometry() |>
  dplyr::filter(
    stringr::str_detect(
      construction_completion_year_comments,
      "Dec 2026|May 2027"
    )
  )

for (i in seq_len(nrow(completion_comment_issues))) {
  validation <- append_validation(
    validation, "warning", "date_consistency", completion_comment_issues$project_name[[i]],
    "construction_completion_year/construction_completion_year_comments",
    paste(
      completion_comment_issues$construction_completion_year[[i]],
      completion_comment_issues$construction_completion_year_comments[[i]],
      sep = " / "
    ),
    paste(
      completion_comment_issues$construction_completion_year[[i]],
      completion_comment_issues$construction_completion_year_comments[[i]],
      sep = " / "
    ),
    "Completion-year comment references dates later than the submitted completion year; retained submitted values pending review."
  )
}

budget_comment_issues <- cleaned |>
  sf::st_drop_geometry() |>
  dplyr::filter(stringr::str_detect(estimated_budget_comments, "NEEDS CONSTRUCTION COST"))

for (i in seq_len(nrow(budget_comment_issues))) {
  validation <- append_validation(
    validation, "warning", "budget_consistency", budget_comment_issues$project_name[[i]],
    "estimated_budget_comments",
    budget_comment_issues$estimated_budget_comments[[i]],
    budget_comment_issues$estimated_budget_comments[[i]],
    "Budget comment indicates construction cost is still needed; retained submitted budget and funding values pending review."
  )
}

missing_required <- cleaned |>
  sf::st_drop_geometry() |>
  dplyr::select(project_name, dplyr::all_of(required_attribute_fields)) |>
  tidyr::pivot_longer(
    -project_name,
    names_to = "field",
    values_to = "value",
    values_transform = list(value = as.character)
  ) |>
  dplyr::filter(is.na(value) | stringr::str_squish(as.character(value)) == "")

for (i in seq_len(nrow(missing_required))) {
  validation <- append_validation(
    validation, "error", "required_field", missing_required$project_name[[i]],
    missing_required$field[[i]], NA_character_, NA_character_,
    "Required field is missing after standardization."
  )
}

validation <- validate_enum_field(
  validation, cleaned, "project_stage", schema_enum_values(schema, "ProjectStageEnum")
)
validation <- validate_enum_field(
  validation, cleaned, "system", schema_enum_values(schema, "SystemEnum")
)
validation <- validate_enum_field(
  validation, cleaned, "project_type", schema_enum_values(schema, "ProjectTypeEnum")
)
validation <- validate_enum_field(
  validation, cleaned, "target_species", schema_enum_values(schema, "TargetSpeciesEnum")
)

bad_email <- cleaned |>
  sf::st_drop_geometry() |>
  dplyr::filter(!stringr::str_detect(contact_email, "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"))

for (i in seq_len(nrow(bad_email))) {
  validation <- append_validation(
    validation, "error", "email_format", bad_email$project_name[[i]], "contact_email",
    bad_email$contact_email[[i]], bad_email$contact_email[[i]],
    "Email does not match schema email pattern."
  )
}

year_issues <- cleaned |>
  sf::st_drop_geometry() |>
  dplyr::filter(
    construction_start_year < 2018 | construction_start_year > 2035 |
      construction_completion_year < 2018 | construction_completion_year > 2040 |
      construction_completion_year < construction_start_year
  )

for (i in seq_len(nrow(year_issues))) {
  validation <- append_validation(
    validation, "error", "year_range", year_issues$project_name[[i]],
    "construction_start_year/construction_completion_year",
    paste(year_issues$construction_start_year[[i]], year_issues$construction_completion_year[[i]], sep = "/"),
    paste(year_issues$construction_start_year[[i]], year_issues$construction_completion_year[[i]], sep = "/"),
    "Construction years are outside schema range or completion year is before start year."
  )
}

funding_issues <- cleaned |>
  sf::st_drop_geometry() |>
  dplyr::filter(!is.na(estimated_budget), !is.na(funding_secured), !is.na(funding_gap)) |>
  dplyr::filter(funding_gap != estimated_budget - funding_secured)

for (i in seq_len(nrow(funding_issues))) {
  validation <- append_validation(
    validation, "error", "funding_gap", funding_issues$project_name[[i]],
    "funding_gap",
    funding_issues$funding_gap[[i]], funding_issues$estimated_budget[[i]] - funding_issues$funding_secured[[i]],
    "Funding gap does not equal estimated_budget - funding_secured."
  )
}

negative_numeric <- cleaned |>
  sf::st_drop_geometry() |>
  dplyr::select(project_name, estimated_budget, funding_secured, funding_gap, dplyr::starts_with("acreage")) |>
  tidyr::pivot_longer(-project_name, names_to = "field", values_to = "value") |>
  dplyr::filter(!is.na(value), value < 0)

for (i in seq_len(nrow(negative_numeric))) {
  validation <- append_validation(
    validation, "error", "numeric_range", negative_numeric$project_name[[i]],
    negative_numeric$field[[i]], negative_numeric$value[[i]], negative_numeric$value[[i]],
    "Numeric value is below the schema minimum of zero."
  )
}

if (is.na(sf::st_crs(cleaned))) {
  validation <- append_validation(validation, "error", "crs", message = "Output CRS is missing.")
} else if (sf::st_crs(cleaned)$epsg != 3310) {
  validation <- append_validation(validation, "error", "crs", message = "Output CRS is not EPSG:3310.")
}

empty_geom <- sf::st_is_empty(cleaned)
for (i in which(empty_geom)) {
  validation <- append_validation(
    validation, "error", "geometry_empty", cleaned$project_name[[i]], "geometry",
    NA_character_, NA_character_, "Geometry is empty."
  )
}

invalid_geom <- !sf::st_is_valid(cleaned)
for (i in which(invalid_geom)) {
  validation <- append_validation(
    validation, "error", "geometry_validity", cleaned$project_name[[i]], "geometry",
    NA_character_, NA_character_, "Geometry is invalid after standardization."
  )
}

geom_types <- as.character(sf::st_geometry_type(cleaned))
bad_geom_type <- !geom_types %in% c("POLYGON", "MULTIPOLYGON", "POINT", "MULTIPOINT")
for (i in which(bad_geom_type)) {
  validation <- append_validation(
    validation, "error", "geometry_type", cleaned$project_name[[i]], "geometry",
    geom_types[[i]], geom_types[[i]], "Geometry type is not allowed by the schema."
  )
}

area_acres <- as.numeric(sf::st_area(cleaned)) / 4046.8564224
for (i in which(area_acres < 0.01)) {
  validation <- append_validation(
    validation, "warning", "geometry_sliver", cleaned$project_name[[i]], "geometry",
    area_acres[[i]], area_acres[[i]], "Polygon area is below 0.01 acres."
  )
}

cleaned_4326 <- sf::st_transform(cleaned, 4326)
bboxes <- purrr::map(sf::st_geometry(cleaned_4326), sf::st_bbox)
outside_ca <- purrr::map_lgl(bboxes, \(bb) bb[["xmax"]] < -125 || bb[["xmin"]] > -114 ||
                              bb[["ymax"]] < 32 || bb[["ymin"]] > 42.5)
for (i in which(outside_ca)) {
  validation <- append_validation(
    validation, "error", "geometry_extent", cleaned$project_name[[i]], "geometry",
    NA_character_, NA_character_, "Geometry bounding box is outside the expected California extent."
  )
}

equals <- sf::st_equals(cleaned)
for (i in seq_along(equals)) {
  previous_matches <- equals[[i]][equals[[i]] < i]
  if (length(previous_matches) > 0) {
    validation <- append_validation(
      validation, "warning", "geometry_duplicate_exact", cleaned$project_name[[i]], "geometry",
      cleaned$project_name[[previous_matches[[1]]]], cleaned$project_name[[i]],
      "Geometry exactly duplicates an earlier feature."
    )
  }
}

if (nrow(cleaned) > 1) {
  centroid_dist <- sf::st_distance(sf::st_centroid(cleaned))
  for (i in seq_len(nrow(cleaned) - 1)) {
    for (j in seq((i + 1), nrow(cleaned))) {
      area_diff <- abs(area_acres[[i]] - area_acres[[j]]) / max(area_acres[[i]], area_acres[[j]])
      if (as.numeric(centroid_dist[i, j]) <= 1 && area_diff <= 0.01) {
        validation <- append_validation(
          validation, "warning", "geometry_duplicate_near", cleaned$project_name[[j]], "geometry",
          cleaned$project_name[[i]], cleaned$project_name[[j]],
          "Centroids are within 1 meter and areas differ by 1 percent or less."
        )
      }
    }
  }
}

readr::write_csv(validation, paths$validation_csv)

transformations <- c(
  "- Used the submitted GeoPackage layer for geometry and attributes. The workbook project tabs were inventoried as supplemental submitted attributes but not joined into the standardized output.",
  "- `project_id` and `update_date`: omitted as program-assigned canonical-record fields.",
  "- Source field `constructon_completion_year` is treated as the misspelled source name for `construction_completion_year`.",
  "- `contact_name` and `contact_email`: selected the first submitted semicolon-delimited contact as the schema primary contact.",
  "- `early_implementation`: converted submitted true/false text to logical values.",
  "  - `True` -> `TRUE`",
  "- `target_species`: standardized capitalization to schema enum values.",
  "  - `Steelhead Trout` -> `Steelhead trout`",
  "- `project_stage`, `project_type`, `contractors`, `funding_sources`, and `target_species`: normalized semicolon-delimited serialization.",
  "- `estimated_budget`, `funding_secured`, `funding_gap`, and construction years: wrote integer values required by the schema.",
  "- Text length limits from the pinned schema were checked and enforced for description and comment fields.",
  "- Missing submitted acreage values are retained as missing; geometry-derived acreage was not substituted.",
  "- Geometry was transformed from NAD83 / California zone 2 (ftUS) to EPSG:3310 and Z/M ordinates were dropped."
)

review_items <- c(
  "- All four submitted records are missing `acreage`; supply restoration acreage values if they are available.",
  "- `Upper Rose Bar Habitat Enhancement Project` has submitted `construction_completion_year` 2024, but its completion-year comment references December 2026 and May 2027 dates. Confirm the intended completion year.",
  "- `Upper Long Bar Habitat Enhancement Project` has an estimated-budget comment saying `NEEDS CONSTRUCTION COST`, while `funding_gap` is submitted as `0`. Confirm whether the budget and funding values are final."
)

write_qc_report(
  path = paths$qc_md,
  title = "YWA 2026-05-23-v01 QC Report",
  source_file = paths$source_gpkg,
  source_layer = source_layer,
  inventory = inventory_source,
  validation = validation,
  output_file = paths$out_gpkg,
  output_layer = paths$out_layer,
  output_rows = nrow(cleaned),
  output_crs = "EPSG:3310",
  target_profile = "RestorationProjectSubmission",
  transformations = transformations,
  review_items = review_items,
  validation_file = paths$validation_csv,
  pdf_path = paths$qc_pdf,
  omitted_program_fields = c("project_id", "update_date"),
  omitted_source_fields = c("Shape")
)

if (file.exists(paths$out_gpkg)) {
  unlink(paths$out_gpkg)
}
sf::st_write(cleaned, paths$out_gpkg, layer = paths$out_layer, quiet = TRUE)

message("Wrote ", paths$out_gpkg)
message("Wrote ", paths$inventory_csv)
message("Wrote ", paths$validation_csv)
message("Wrote ", paths$qc_md)
message("Wrote ", paths$qc_pdf)
