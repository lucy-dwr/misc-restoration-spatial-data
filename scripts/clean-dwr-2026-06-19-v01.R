source("R/cleaning-utils.R")

paths <- submission_paths("dwr", "2026-06-19-v01")
source_layer <- "restoration_projects"

dir_create_submission(paths)

schema_profile <- load_schema_profile(paths$schema_file)
schema <- schema_profile$schema
attribute_fields <- schema_profile$attribute_fields
required_attribute_fields <- schema_profile$required_attribute_fields

submission <- read_submission_layer(paths$source_gpkg, source_layer, paths$inventory_csv)
inventory <- submission$inventory
raw <- submission$raw

cleaned <- raw |>
  dplyr::mutate(
    submitted_funding_sources = funding_sources,
    project_name = null_to_na_chr(project_name),
    project_description = stringr::str_trunc(null_to_na_chr(project_description), 500, ellipsis = ""),
    project_stage = normalize_semicolon_values(project_stage),
    contact_name = null_to_na_chr(contact_name),
    contact_email = stringr::str_to_lower(null_to_na_chr(contact_email)),
    lead_entity = normalize_semicolon_values(lead_entity),
    contractors = normalize_semicolon_values(contractors),
    early_implementation = as.logical(early_implementation),
    construction_start_year = as.integer(construction_start_year),
    construction_completion_year = as.integer(construction_completion_year),
    construction_completion_year_comments =
      stringr::str_trunc(null_to_na_chr(construction_completion_year_comments), 250, ellipsis = ""),
    estimated_budget = as.integer(round(estimated_budget)),
    estimated_budget_comments = stringr::str_trunc(null_to_na_chr(estimated_budget_comments), 500, ellipsis = ""),
    funding_secured = as.integer(round(funding_secured)),
    funding_gap = dplyr::if_else(
      !is.na(estimated_budget) & !is.na(funding_secured),
      estimated_budget - funding_secured,
      NA_integer_
    ),
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
    target_species = normalize_semicolon_values(target_species)
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
    "Read ", inventory$features[[1]], " features from ", source_layer,
    "; source CRS: ", inventory$crs_name[[1]], "."
  )
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

funding_source_changes <- raw |>
  sf::st_drop_geometry() |>
  dplyr::transmute(
    feature_id = project_name,
    submitted = funding_sources,
    standardized = cleaned$funding_sources
  ) |>
  dplyr::filter(!is.na(submitted), submitted != standardized)

for (i in seq_len(nrow(funding_source_changes))) {
  validation <- append_validation(
    validation, "warning", "value_repair", funding_source_changes$feature_id[[i]], "funding_sources",
    funding_source_changes$submitted[[i]], funding_source_changes$standardized[[i]],
    "Normalized semicolon-delimited serialization and dropped empty submitted list elements."
  )
}

funding_gap_derived <- cleaned |>
  sf::st_drop_geometry() |>
  dplyr::filter(!is.na(funding_secured), !is.na(funding_gap))

for (i in seq_len(nrow(funding_gap_derived))) {
  validation <- append_validation(
    validation, "info", "derived_value", funding_gap_derived$project_name[[i]], "funding_gap",
    NA_character_, funding_gap_derived$funding_gap[[i]],
    "Source did not include funding_gap; derived as estimated_budget - funding_secured."
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
  "- `project_id` and `update_date`: omitted as program-assigned canonical-record fields.",
  "- Source did not include `funding_gap`; where `estimated_budget` and `funding_secured` were both submitted, `funding_gap` was derived as `estimated_budget - funding_secured`.",
  "- `funding_sources`, `project_stage`, `project_type`, `contractors`, `lead_entity`, and `target_species`: normalized semicolon-delimited serialization.",
  "- `funding_sources`: dropped empty submitted list elements.",
  "  - `Prop 68; CVPIA; ; DWR` -> `Prop 68; CVPIA; DWR`",
  "- `estimated_budget`, `funding_secured`, `funding_gap`, and construction years: wrote integer values required by the schema.",
  "- Text length limits from the pinned schema were checked and enforced for description and comment fields.",
  "- Submitted acreage values are preserved rather than replaced with geometry-derived acreage.",
  "- Geometry was transformed from NAD83 / California Albers to EPSG:3310 and Z/M ordinates were dropped."
)

review_items <- c(
  "- Eleven records are missing required `funding_secured`; supply funding-secured values or confirm the schema should allow missing values for this submission.",
  "- `Dos Rios Norte` is missing required `construction_start_year`, `construction_completion_year`, and `funding_secured`; supply those values before the record can pass validation."
)

write_qc_report(
  path = paths$qc_md,
  title = "DWR 2026-06-19-v01 QC Report",
  source_file = paths$source_gpkg,
  source_layer = source_layer,
  inventory = inventory,
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
  omitted_program_fields = c("project_id", "update_date")
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
