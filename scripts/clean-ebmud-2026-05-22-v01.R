source("R/cleaning-utils.R")

source_gpkg <- "data-raw/ebmud/2026-05-22_v01-2/2026-05-22_v01-2.gpkg"
source_layer <- "LMR_HRL_Projects_Act_FINAL_1"
schema_file <- "schemas/hrl_restoration_project.yaml"

out_dir <- "data-standardized/ebmud"
report_dir <- "reports/ebmud"
out_gpkg <- file.path(out_dir, "2026-05-22-v01.gpkg")
out_layer <- "restoration_projects"
inventory_csv <- file.path(report_dir, "2026-05-22-v01_inventory.csv")
validation_csv <- file.path(report_dir, "2026-05-22-v01_validation.csv")
qc_md <- file.path(report_dir, "2026-05-22-v01_qc.md")
qc_pdf <- file.path(report_dir, "2026-05-22-v01_qc.pdf")

dir_create(out_dir)
dir_create(report_dir)

schema <- yaml::yaml.load_file(schema_file)
submission_fields <- schema$classes$RestorationProjectRecord$slots
attribute_fields <- setdiff(submission_fields, "geometry")
required_fields <- names(purrr::keep(
  schema$classes$RestorationProjectRecord$slot_usage,
  ~ identical(.x$required, TRUE)
))
required_attribute_fields <- setdiff(required_fields, "geometry")

inventory <- inventory_gpkg(source_gpkg)
readr::write_csv(inventory, inventory_csv)

raw <- sf::st_read(source_gpkg, layer = source_layer, quiet = TRUE)

stage_map <- c(
  "Design & Permitting" = "design; permitting",
  "Complete" = "post-construction monitoring and science",
  "On-going" = "construction"
)

project_type_map <- c(
  "Floodplain Habitat Restoration" = "tributary floodplain habitat",
  "Gravel Maintenance" = "spawning habitat",
  "In Channel Rearing Habitat Restoration" = "rearing habitat"
)

system_map <- c(
  "Mokelumne River" = "Mokelumne"
)

cleaned <- raw |>
  dplyr::mutate(
    source_feature_name = Name,
    source_site_name = Site_Name,
    submitted_project_stage = project_stage,
    submitted_project_type = project_type,
    submitted_system = system,
    submitted_funding_secured = funding_secured,
    submitted_funding_sources = funding_sources,
    estimated_budget = parse_currency_integer(estimated_budget),
    funding_gap = parse_currency_integer(funding_gap),
    funding_secured = dplyr::case_when(
      stringr::str_to_lower(submitted_funding_secured) == "yes" &
        !is.na(estimated_budget) & !is.na(funding_gap) ~ estimated_budget - funding_gap,
      stringr::str_to_lower(submitted_funding_secured) == "no" ~ 0L,
      TRUE ~ NA_integer_
    ),
    project_stage = dplyr::recode(project_stage, !!!stage_map, .default = project_stage),
    project_type = dplyr::recode(project_type, !!!project_type_map, .default = project_type),
    system = dplyr::recode(system, !!!system_map, .default = system),
    funding_sources = dplyr::case_when(
      stringr::str_to_lower(stringr::str_squish(submitted_funding_sources)) == "none" ~ NA_character_,
      submitted_funding_sources == "DWR FAIR Funding Agreement & EBMUD Capital" ~
        "DWR FAIR Funding Agreement; EBMUD Capital",
      submitted_funding_sources == "Prop 68 & EBMUD Capital" ~
        "Prop 68; EBMUD Capital",
      submitted_funding_sources == "EBMUD, USFWS, CNRA" ~
        "EBMUD; USFWS; CNRA",
      TRUE ~ null_to_na_chr(submitted_funding_sources)
    ),
    contractors = null_to_na_chr(contractors),
    project_description = stringr::str_trunc(null_to_na_chr(project_description), 500, ellipsis = ""),
    construction_completion_year_comments =
      stringr::str_trunc(null_to_na_chr(construction_completion_year_comments), 250, ellipsis = ""),
    estimated_budget_comments = stringr::str_trunc(null_to_na_chr(estimated_budget_comments), 500, ellipsis = ""),
    contact_email = stringr::str_to_lower(null_to_na_chr(contact_email)),
    early_implementation = as.logical(early_implementation)
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
  message = "Output targets RestorationProjectSubmission; canonical-only update_date was omitted."
)

validation <- append_validation(
  validation,
  "info",
  "geometry_standardization",
  message = "Dropped Z/M ordinates, repaired geometries with sf::st_make_valid(), and transformed to EPSG:3310."
)

stage_changes <- raw |>
  sf::st_drop_geometry() |>
  dplyr::transmute(feature_id = project_name, submitted = project_stage) |>
  dplyr::mutate(standardized = dplyr::recode(submitted, !!!stage_map, .default = submitted)) |>
  dplyr::filter(submitted != standardized)

for (i in seq_len(nrow(stage_changes))) {
  validation <- append_validation(
    validation, "warning", "value_repair", stage_changes$feature_id[[i]], "project_stage",
    stage_changes$submitted[[i]], stage_changes$standardized[[i]],
    "Mapped submitted project-stage label to schema enum value; review interpretation."
  )
}

type_changes <- raw |>
  sf::st_drop_geometry() |>
  dplyr::transmute(feature_id = project_name, submitted = project_type) |>
  dplyr::mutate(standardized = dplyr::recode(submitted, !!!project_type_map, .default = submitted)) |>
  dplyr::filter(submitted != standardized)

for (i in seq_len(nrow(type_changes))) {
  validation <- append_validation(
    validation, "warning", "value_repair", type_changes$feature_id[[i]], "project_type",
    type_changes$submitted[[i]], type_changes$standardized[[i]],
    "Mapped submitted project-type label to schema enum value based on habitat acreage fields and project description."
  )
}

funding_changes <- raw |>
  sf::st_drop_geometry() |>
  dplyr::transmute(
    feature_id = project_name,
    submitted = funding_secured,
    standardized = cleaned$funding_secured
  )

for (i in seq_len(nrow(funding_changes))) {
  validation <- append_validation(
    validation, "warning", "value_repair", funding_changes$feature_id[[i]], "funding_secured",
    funding_changes$submitted[[i]], funding_changes$standardized[[i]],
    "Converted submitted yes/no funding status to schema dollar value using funding gap and estimated budget."
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

readr::write_csv(validation, validation_csv)

transformations <- c(
  "- `project_stage`: mapped submitted labels to schema enum values.",
  "  - `Design & Permitting` → `design; permitting`",
  "  - `Complete` → `post-construction monitoring and science`",
  "  - `On-going` → `construction`",
  "- `project_type`: mapped submitted labels to schema enum values.",
  "  - `Floodplain Habitat Restoration` → `tributary floodplain habitat`",
  "  - `Gravel Maintenance` → `spawning habitat`",
  "  - `In Channel Rearing Habitat Restoration` → `rearing habitat`",
  "- `system`: mapped submitted river-system labels to schema enum values.",
  "  - `Mokelumne River` → `Mokelumne`",
  "- `estimated_budget` and `funding_gap`: removed currency symbols and grouping separators, then wrote integer dollar values.",
  "- `funding_secured`: converted submitted yes/no values to dollar values.",
  "  - `No` → `0`",
  "  - `Yes` → `estimated_budget - funding_gap`",
  "- `funding_sources`: converted known combined-source strings to semicolon-delimited values and wrote `None` as missing.",
  "  - `DWR FAIR Funding Agreement & EBMUD Capital` → `DWR FAIR Funding Agreement; EBMUD Capital`",
  "  - `Prop 68 & EBMUD Capital` → `Prop 68; EBMUD Capital`",
  "  - `EBMUD, USFWS, CNRA` → `EBMUD; USFWS; CNRA`",
  "  - `None` → missing",
  "- `early_implementation`: converted submitted integers to logical values.",
  "  - `0` → `FALSE`",
  "  - `1` → `TRUE`",
  "- Text length limits from the pinned schema were enforced for description and comment fields.",
  "- Geometry was transformed from WGS84 to EPSG:3310 and Z/M ordinates were dropped."
)

review_items <- c(
  "- Confirm whether mapping `On-going` gravel maintenance to `construction` is the intended HRL project-stage representation."
)

write_qc_report(
  path = qc_md,
  title = "EBMUD 2026-05-22-v01 QC Report",
  source_file = source_gpkg,
  source_layer = source_layer,
  inventory = inventory,
  validation = validation,
  output_file = out_gpkg,
  output_layer = out_layer,
  output_rows = nrow(cleaned),
  output_crs = "EPSG:3310",
  target_profile = "RestorationProjectSubmission",
  transformations = transformations,
  review_items = review_items,
  validation_file = validation_csv,
  pdf_path = qc_pdf,
  omitted_program_fields = "update_date",
  omitted_source_fields = c("Name", "Site_Name", "geometry", "Shape")
)

if (file.exists(out_gpkg)) {
  unlink(out_gpkg)
}
sf::st_write(cleaned, out_gpkg, layer = out_layer, quiet = TRUE)

message("Wrote ", out_gpkg)
message("Wrote ", inventory_csv)
message("Wrote ", validation_csv)
message("Wrote ", qc_md)
message("Wrote ", qc_pdf)
