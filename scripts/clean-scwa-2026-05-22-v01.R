source("R/cleaning-utils.R")

paths <- submission_paths("scwa", "2026-05-22-v01", source_ext = "zip")

source_zip <- paths$source_gpkg
source_workbook <- "putah resto acres for HRL GIS Lucy 2026.xlsx"
source_layer <- "workbook rows joined to named shapefiles"

dir_create_submission(paths)

schema_profile <- load_schema_profile(paths$schema_file)
schema <- schema_profile$schema
attribute_fields <- schema_profile$attribute_fields
required_attribute_fields <- schema_profile$required_attribute_fields

zip_listing <- utils::unzip(source_zip, list = TRUE)
extract_dir <- file.path(tempdir(), "scwa-2026-05-22-v01")
if (dir.exists(extract_dir)) {
  unlink(extract_dir, recursive = TRUE)
}
dir.create(extract_dir, recursive = TRUE)
utils::unzip(source_zip, exdir = extract_dir)

read_xlsx_sheet <- function(path, sheet = "sheet1") {
  read_zip_text <- function(member) {
    connection <- unz(path, member, open = "rt")
    on.exit(close(connection), add = TRUE)
    paste(readLines(connection, warn = FALSE), collapse = "")
  }

  decode_xml_text <- function(x) {
    x <- gsub("&amp;", "&", x, fixed = TRUE)
    x <- gsub("&lt;", "<", x, fixed = TRUE)
    x <- gsub("&gt;", ">", x, fixed = TRUE)
    x <- gsub("&quot;", "\"", x, fixed = TRUE)
    gsub("&apos;", "'", x, fixed = TRUE)
  }

  regex_matches <- function(x, pattern) {
    matches <- regmatches(x, gregexpr(pattern, x, perl = TRUE))[[1]]
    if (identical(matches, character(0)) || identical(matches, "-1")) {
      character()
    } else {
      matches
    }
  }

  attr_value <- function(x, attr) {
    pattern <- paste0(attr, "=\"([^\"]*)\"")
    value <- sub(pattern, "\\1", stringr::str_extract(x, pattern), perl = TRUE)
    if (is.na(value)) {
      NA_character_
    } else {
      value
    }
  }

  shared_strings_xml <- read_zip_text("xl/sharedStrings.xml")
  shared_strings <- regex_matches(shared_strings_xml, "<si>.*?</si>") |>
    purrr::map_chr(function(item) {
      text_nodes <- regex_matches(item, "<t[^>]*>.*?</t>")
      text_values <- gsub("^<t[^>]*>|</t>$", "", text_nodes, perl = TRUE)
      decode_xml_text(paste(text_values, collapse = ""))
    })

  sheet_xml <- read_zip_text(paste0("xl/worksheets/", sheet, ".xml"))
  rows <- regex_matches(sheet_xml, "<row[^>]*>.*?</row>")

  cells <- purrr::map_dfr(rows, function(row_xml) {
    row_index <- as.integer(attr_value(row_xml, "r"))
    regex_matches(row_xml, "<c[^>]*>.*?</c>") |>
      purrr::map_dfr(function(cell_xml) {
        cell_ref <- attr_value(cell_xml, "r")
        col_ref <- stringr::str_extract(cell_ref, "^[A-Z]+")
        value_match <- regex_matches(cell_xml, "<v>.*?</v>")
        value <- if (length(value_match) == 0) {
          NA_character_
        } else {
          gsub("^<v>|</v>$", "", value_match[[1]], perl = TRUE)
        }
        if (!is.na(value) && identical(attr_value(cell_xml, "t"), "s")) {
          value <- shared_strings[[as.integer(value) + 1L]]
        }
        tibble::tibble(row = row_index, col = col_ref, value = decode_xml_text(value))
      })
  })

  header <- cells |>
    dplyr::filter(row == min(row)) |>
    dplyr::arrange(match(col, unique(col))) |>
    dplyr::transmute(col, name = value)

  cells |>
    dplyr::filter(row > min(row)) |>
    dplyr::mutate(col = factor(col, levels = header$col)) |>
    tidyr::complete(row, col = factor(header$col, levels = header$col)) |>
    tidyr::pivot_wider(names_from = col, values_from = value) |>
    dplyr::select(-row, dplyr::all_of(header$col)) |>
    stats::setNames(header$name) |>
    dplyr::filter(!is.na(project_name))
}

submitted_null_to_na <- function(x) {
  x <- null_to_na_chr(x)
  dplyr::if_else(stringr::str_to_lower(x) == "null", NA_character_, x)
}

to_integer <- function(x) {
  parsed <- readr::parse_number(submitted_null_to_na(x), locale = readr::locale(grouping_mark = ","))
  as.integer(round(parsed))
}

to_double <- function(x) {
  readr::parse_number(submitted_null_to_na(x), locale = readr::locale(grouping_mark = ","))
}

source_files <- c(
  "Nishikawa on Putah Creek" = "Nishikawa hrl habitat 2026.shp",
  "Putah Gravel Augmentation and Scarification" = "Gravel HRL habitat 2026.shp",
  "Putah Creek fish passage at Los Rios Check Dam" = "Los Rios Check Dam HRL habitat 2026.shp",
  "Putah Creek fish passage at County Rd 106a" = "106a HRL habitat 2026.shp"
)

channel_buffer_m <- 10

workbook_path <- file.path(extract_dir, source_workbook)
workbook <- read_xlsx_sheet(workbook_path)

inventory_spatial <- purrr::map_dfr(source_files, function(file_name) {
  source_path <- file.path(extract_dir, file_name)
  source_data <- sf::st_read(source_path, quiet = TRUE)
  tibble::tibble(
    source_file = file.path(dirname(source_zip), basename(source_zip)),
    archive_member = file_name,
    source_role = "geometry",
    layer_name = tools::file_path_sans_ext(file_name),
    geometry_type = paste(unique(as.character(sf::st_geometry_type(source_data))), collapse = "; "),
    features = nrow(source_data),
    fields = ncol(sf::st_drop_geometry(source_data)),
    crs_name = sf::st_crs(source_data)$input
  )
})

inventory_workbook <- tibble::tibble(
  source_file = file.path(dirname(source_zip), basename(source_zip)),
  archive_member = source_workbook,
  source_role = "attributes",
  layer_name = "sheet1",
  geometry_type = NA_character_,
  features = nrow(workbook),
  fields = ncol(workbook),
  crs_name = NA_character_
)

inventory <- dplyr::bind_rows(inventory_workbook, inventory_spatial)
readr::write_csv(inventory, paths$inventory_csv)

read_project_geometry <- function(project_name) {
  project_name <- stringr::str_squish(project_name)
  source_path <- file.path(extract_dir, source_files[[project_name]])
  source_data <- sf::st_read(source_path, quiet = TRUE) |>
    sf::st_zm(drop = TRUE, what = "ZM") |>
    sf::st_make_valid() |>
    sf::st_transform(3310)

  geometry_type <- unique(as.character(sf::st_geometry_type(source_data)))
  if (all(geometry_type %in% c("POINT", "MULTIPOINT"))) {
    point_geometry <- source_data |>
      sf::st_geometry() |>
      sf::st_cast("POINT")

    if (length(point_geometry) == 1L) {
      point_buffer <- point_geometry |>
        sf::st_sfc(crs = 3310) |>
        sf::st_buffer(channel_buffer_m) |>
        sf::st_make_valid() |>
        sf::st_geometry()
      return(point_buffer[[1]])
    }

    line_coordinates <- sf::st_coordinates(point_geometry)[, c("X", "Y"), drop = FALSE]
    ordering_axis <- if (diff(range(line_coordinates[, "X"])) >= diff(range(line_coordinates[, "Y"]))) {
      "X"
    } else {
      "Y"
    }
    line_coordinates <- line_coordinates[order(line_coordinates[, ordering_axis]), , drop = FALSE]
    line_buffer <- sf::st_linestring(line_coordinates) |>
      sf::st_sfc(crs = 3310) |>
      sf::st_buffer(channel_buffer_m, endCapStyle = "ROUND", joinStyle = "ROUND") |>
      sf::st_make_valid() |>
      sf::st_geometry()
    return(line_buffer[[1]])
  }

  geometry <- sf::st_geometry(source_data)

  if (length(geometry) == 1L) {
    geometry[[1]]
  } else {
    sf::st_combine(geometry)[[1]]
  }
}

project_geometries <- sf::st_sfc(
  purrr::map(workbook$project_name, read_project_geometry),
  crs = 3310
)

raw <- sf::st_as_sf(workbook, geometry = project_geometries)

cleaned <- raw |>
  dplyr::mutate(
    source_project_name = project_name,
    submitted_contractors = contractors,
    submitted_early_implementation = early_implementation,
    submitted_construction_start_year = construction_start_year,
    submitted_construction_completion_year = construction_completion_year,
    submitted_funding_gap = funding_gap,
    project_name = stringr::str_squish(project_name),
    project_description = stringr::str_trunc(submitted_null_to_na(project_description), 500, ellipsis = ""),
    project_stage = normalize_semicolon_values(project_stage),
    contact_name = submitted_null_to_na(contact_name),
    contact_email = stringr::str_to_lower(submitted_null_to_na(contact_email)),
    lead_entity = submitted_null_to_na(lead_entity),
    contractors = normalize_semicolon_values(contractors),
    early_implementation = dplyr::case_when(
      submitted_null_to_na(early_implementation) == "1" ~ TRUE,
      submitted_null_to_na(early_implementation) == "0" ~ FALSE,
      TRUE ~ NA
    ),
    construction_start_year = to_integer(construction_start_year),
    construction_completion_year = to_integer(construction_completion_year),
    construction_completion_year_comments =
      stringr::str_trunc(submitted_null_to_na(construction_completion_year_comments), 250, ellipsis = ""),
    estimated_budget = to_integer(estimated_budget),
    estimated_budget_comments = stringr::str_trunc(submitted_null_to_na(estimated_budget_comments), 500, ellipsis = ""),
    funding_secured = to_integer(funding_secured),
    funding_gap = dplyr::case_when(
      !is.na(to_integer(funding_gap)) ~ to_integer(funding_gap),
      !is.na(estimated_budget) & !is.na(funding_secured) ~ estimated_budget - funding_secured,
      TRUE ~ NA_integer_
    ),
    funding_sources = normalize_semicolon_values(funding_sources),
    system = submitted_null_to_na(system),
    project_type = normalize_semicolon_values(project_type),
    acreage = to_double(acreage),
    acreage_bypass_floodplain = to_double(acreage_bypass_floodplain),
    acreage_fish_food = to_double(acreage_fish_food),
    acreage_tributary_floodplain = to_double(acreage_tributary_floodplain),
    acreage_tributary_rearing = to_double(acreage_tributary_rearing),
    acreage_tributary_spawning = to_double(acreage_tributary_spawning),
    acreage_tidal_wetland = to_double(acreage_tidal_wetland),
    target_species = normalize_semicolon_values(target_species)
  ) |>
  dplyr::select(dplyr::all_of(attribute_fields))

validation <- validation_tbl()

validation <- append_validation(
  validation,
  "info",
  "source_inventory",
  message = paste0(
    "Read ", nrow(workbook), " project rows from workbook and ",
    sum(inventory_spatial$features), " geometry features from four shapefiles in the submitted zip."
  )
)

validation <- append_validation(
  validation,
  "info",
  "profile",
  message = "Output targets RestorationProjectSubmission; workbook project_id and update_date were omitted."
)

validation <- append_validation(
  validation,
  "info",
  "geometry_standardization",
  message = paste0(
    "Extracted zipped shapefiles to a temporary directory, dropped Z/M ordinates, ",
    "repaired geometries with sf::st_make_valid(), transformed to EPSG:3310, ",
    "and converted submitted point geometries to channel polygons with a ",
    channel_buffer_m,
    " meter buffer."
  )
)

validation <- append_validation(
  validation,
  "warning",
  "geometry_approximation",
  "Putah Gravel Augmentation and Scarification",
  "geometry",
  "91 submitted points",
  paste0(channel_buffer_m, " meter buffered line polygon"),
    "Ordered submitted points along their dominant coordinate axis, connected them into a line, and buffered the line to approximate the mapped stream channel and banks."
)

validation <- append_validation(
  validation,
  "warning",
  "geometry_approximation",
  "Putah Creek fish passage at Los Rios Check Dam",
  "geometry",
  "1 submitted point",
  paste0(channel_buffer_m, " meter buffered point polygon"),
  "Buffered the submitted point to create a visible project-area polygon for mapping."
)

contractor_changes <- raw |>
  sf::st_drop_geometry() |>
  dplyr::transmute(
    feature_id = stringr::str_squish(project_name),
    submitted = contractors,
    standardized = cleaned$contractors
  ) |>
  dplyr::filter(submitted != standardized)

for (i in seq_len(nrow(contractor_changes))) {
  validation <- append_validation(
    validation, "warning", "value_repair", contractor_changes$feature_id[[i]], "contractors",
    contractor_changes$submitted[[i]], contractor_changes$standardized[[i]],
    "Normalized semicolon-delimited contractor serialization while preserving submitted values."
  )
}

early_implementation_changes <- raw |>
  sf::st_drop_geometry() |>
  dplyr::transmute(
    feature_id = stringr::str_squish(project_name),
    submitted = early_implementation,
    standardized = cleaned$early_implementation
  )

for (i in seq_len(nrow(early_implementation_changes))) {
  validation <- append_validation(
    validation, "warning", "value_repair", early_implementation_changes$feature_id[[i]], "early_implementation",
    early_implementation_changes$submitted[[i]], early_implementation_changes$standardized[[i]],
    "Converted submitted integer flag to schema boolean value."
  )
}

derived_funding_gap <- raw |>
  sf::st_drop_geometry() |>
  dplyr::transmute(
    feature_id = stringr::str_squish(project_name),
    submitted = funding_gap,
    standardized = cleaned$funding_gap
  ) |>
  dplyr::filter(is.na(submitted_null_to_na(submitted)), !is.na(standardized))

for (i in seq_len(nrow(derived_funding_gap))) {
  validation <- append_validation(
    validation, "warning", "value_repair", derived_funding_gap$feature_id[[i]], "funding_gap",
    derived_funding_gap$submitted[[i]], derived_funding_gap$standardized[[i]],
    "Derived missing funding_gap as estimated_budget - funding_secured."
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
  missing_construction_year_allowed <- missing_required$field[[i]] %in%
    c("construction_start_year", "construction_completion_year") &&
    missing_required$project_name[[i]] %in%
      c(
        "Putah Creek fish passage at Los Rios Check Dam",
        "Putah Creek fish passage at County Rd 106a"
      )

  validation <- append_validation(
    validation,
    if (missing_construction_year_allowed) "warning" else "error",
    if (missing_construction_year_allowed) "temporary_missing_accepted" else "required_field",
    missing_required$project_name[[i]],
    missing_required$field[[i]], NA_character_, NA_character_,
    if (missing_construction_year_allowed) {
      "Construction year is missing after standardization; accepted as a temporary local decision for this planning-stage SCWA submission."
    } else {
      "Required field is missing after standardization."
    }
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
    (!is.na(construction_start_year) & (construction_start_year < 2018 | construction_start_year > 2035)) |
      (!is.na(construction_completion_year) & (construction_completion_year < 2018 | construction_completion_year > 2040)) |
      (!is.na(construction_start_year) & !is.na(construction_completion_year) &
         construction_completion_year < construction_start_year)
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

readr::write_csv(validation, paths$validation_csv)

transformations <- c(
  "- Extracted the submitted zip to a temporary directory at runtime; raw files under `data-raw/` are not modified.",
  "- Used workbook rows as project attributes and matched each row to a named shapefile geometry by project name.",
  paste0("- Converted submitted point geometries to approximate channel polygons using a ", channel_buffer_m, " meter buffer in EPSG:3310."),
  "- `Putah Gravel Augmentation and Scarification`: ordered the 91 submitted points along their dominant west-east coordinate axis, connected them into a line, and buffered the resulting line to represent the stream channel and banks.",
  "- `Putah Creek fish passage at Los Rios Check Dam`: buffered the single submitted point to create a visible project-area polygon.",
  "- Repaired the invalid submitted Nishikawa polygon with `sf::st_make_valid()`.",
  "- Transformed all geometries from WGS 84 to EPSG:3310.",
  "- `project_id` and `update_date`: omitted as program-assigned canonical-record fields.",
  "- `early_implementation`: converted submitted `0`/`1` flags to logical values.",
  "- `contractors`, `project_stage`, `project_type`, `funding_sources`, and `target_species`: normalized semicolon-delimited serialization.",
  "- `funding_gap`: derived as `estimated_budget - funding_secured` when missing from the workbook.",
  "- Workbook literal `null` values are treated as missing, not as text.",
  "- Missing construction years for the two planning-stage fish-passage projects are retained as missing values for now by local review decision.",
  "- Individual gravel point attributes are intentionally ignored; workbook-level project/group observation attributes are used for the standardized gravel project record.",
  "- Submitted acreage values are preserved rather than replaced with geometry-derived acreage."
)

review_items <- c(
  "- `Putah Gravel Augmentation and Scarification` has submitted construction start year `2016`, which is outside the current schema validation range starting at 2018; confirm whether this long-running project needs a schema exception or a different start-year interpretation."
)

inventory_summary <- tibble::tibble(
  features = nrow(workbook),
  geometry_type = paste(unique(geom_types), collapse = "; "),
  crs_name = "WGS 84 source geometries; standardized to EPSG:3310",
  fields = ncol(workbook)
)

write_qc_report(
  path = paths$qc_md,
  title = "SCWA 2026-05-22-v01 QC Report",
  source_file = source_zip,
  source_layer = source_layer,
  inventory = inventory_summary,
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
  omitted_source_fields = c(
    "source_project_name",
    "submitted_contractors",
    "submitted_early_implementation",
    "submitted_construction_start_year",
    "submitted_construction_completion_year",
    "submitted_funding_gap"
  )
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
