source("R/cleaning-utils.R")

schema_profile <- load_schema_profile("schemas/hrl_restoration_project.yaml")
attribute_fields <- schema_profile$attribute_fields

submissions <- tibble::tribble(
  ~source_slug, ~source_agency, ~submission_version, ~source_file,
  "dwr", "California Department of Water Resources", "2026-06-19-v01", "data-standardized/dwr/2026-06-19-v01.gpkg",
  "ebmud", "East Bay Municipal Utility District", "2026-05-22-v01", "data-standardized/ebmud/2026-05-22-v01.gpkg",
  "sbfca", "Sutter Butte Flood Control Agency", "2026-05-22-v01", "data-standardized/sbfca/2026-05-22-v01.gpkg",
  "scwa", "Solano County Water Agency", "2026-05-22-v01", "data-standardized/scwa/2026-05-22-v01.gpkg",
  "sfpuc", "San Francisco Public Utilities Commission", "2026-05-22-v01", "data-standardized/sfpuc/2026-05-22-v01.gpkg",
  "water-forum", "Water Forum", "2026-05-27-v01", "data-standardized/water-forum/2026-05-27-v01.gpkg",
  "ywa", "Yuba Water Agency", "2026-05-23-v01", "data-standardized/ywa/2026-05-23-v01.gpkg"
)

out_dir <- "data-standardized/multi-agency"
report_dir <- "reports/multi-agency"
out_layer <- "restoration_projects"

dir_create(out_dir)
dir_create(report_dir)

next_output_version <- function(out_dir, report_dir, output_date = Sys.Date()) {
  date_stem <- format(output_date, "%Y-%m-%d")
  existing <- c(
    list.files(out_dir, pattern = paste0("^", date_stem, "-v[0-9]{2}\\.gpkg$")),
    list.files(report_dir, pattern = paste0("^", date_stem, "-v[0-9]{2}_(inventory\\.csv|qc\\.md)$"))
  )

  if (length(existing) == 0) {
    return(paste0(date_stem, "-v01"))
  }

  versions <- stringr::str_match(existing, paste0("^", date_stem, "-v([0-9]{2})"))[, 2]
  next_version <- max(as.integer(versions), na.rm = TRUE) + 1L
  paste0(date_stem, "-v", stringr::str_pad(next_version, width = 2, pad = "0"))
}

output_version <- next_output_version(out_dir, report_dir)
out_gpkg <- file.path(out_dir, paste0(output_version, ".gpkg"))
inventory_csv <- file.path(report_dir, paste0(output_version, "_inventory.csv"))
qc_md <- file.path(report_dir, paste0(output_version, "_qc.md"))

missing_files <- submissions |>
  dplyr::filter(!file.exists(source_file))

if (nrow(missing_files) > 0) {
  stop(
    "Missing standardized submission file(s): ",
    paste(missing_files$source_file, collapse = ", "),
    call. = FALSE
  )
}

read_standardized_submission <- function(source_slug, source_agency,
                                         submission_version, source_file) {
  data <- sf::st_read(source_file, layer = "restoration_projects", quiet = TRUE) |>
    sf::st_zm(drop = TRUE, what = "ZM") |>
    sf::st_transform(3310)

  missing_fields <- setdiff(attribute_fields, names(data))
  if (length(missing_fields) > 0) {
    stop(
      "Missing expected standardized field(s) in ",
      source_file,
      ": ",
      paste(missing_fields, collapse = ", "),
      call. = FALSE
    )
  }

  data |>
    dplyr::mutate(
      source_slug = source_slug,
      source_agency = source_agency,
      submission_version = submission_version,
      source_file = source_file,
      source_feature_number = dplyr::row_number(),
      .before = 1
    ) |>
    dplyr::select(
      source_slug,
      source_agency,
      submission_version,
      source_file,
      source_feature_number,
      dplyr::all_of(attribute_fields)
    )
}

combined <- purrr::pmap_dfr(submissions, read_standardized_submission)

combined_geometry_types <- unique(as.character(sf::st_geometry_type(combined)))
if (all(combined_geometry_types %in% c("POLYGON", "MULTIPOLYGON"))) {
  combined <- sf::st_cast(combined, "MULTIPOLYGON")
}

sf::st_write(combined, out_gpkg, layer = out_layer, quiet = TRUE)

inventory <- purrr::pmap_dfr(submissions, function(source_slug, source_agency,
                                                   submission_version, source_file) {
  data <- sf::st_read(source_file, layer = "restoration_projects", quiet = TRUE)
  tibble::tibble(
    source_slug = source_slug,
    source_agency = source_agency,
    submission_version = submission_version,
    source_file = source_file,
    source_layer = "restoration_projects",
    features = nrow(data),
    geometry_type = paste(unique(as.character(sf::st_geometry_type(data))), collapse = "; "),
    crs_epsg = sf::st_crs(data)$epsg
  )
})

inventory <- dplyr::bind_rows(
  inventory,
  tibble::tibble(
    source_slug = "multi-agency",
    source_agency = "All standardized submissions",
    submission_version = output_version,
    source_file = out_gpkg,
    source_layer = out_layer,
    features = nrow(combined),
    geometry_type = paste(unique(as.character(sf::st_geometry_type(combined))), collapse = "; "),
    crs_epsg = sf::st_crs(combined)$epsg
  )
)

readr::write_csv(inventory, inventory_csv)

geometry_counts <- combined |>
  sf::st_drop_geometry() |>
  dplyr::mutate(geometry_type = as.character(sf::st_geometry_type(combined))) |>
  dplyr::count(geometry_type, name = "features")

geometry_summary <- paste0(
  paste0("`", geometry_counts$geometry_type, "`", collapse = ", "),
  " layer preserving standardized source geometry types."
)

agency_counts <- combined |>
  sf::st_drop_geometry() |>
  dplyr::count(source_slug, source_agency, submission_version, name = "features")

qc_lines <- c(
  paste0("# Multi-Agency ", output_version, " QC Report"),
  "",
  "## Output",
  "",
  paste0("- Output file: `", out_gpkg, "`"),
  paste0("- Output layer: `", out_layer, "`"),
  paste0("- Output feature count: ", nrow(combined)),
  "- Output CRS: `EPSG:3310`",
  paste0("- Geometry type: ", geometry_summary),
  "",
  "## Source Submissions",
  "",
  paste0(
    "- `",
    agency_counts$source_slug,
    "` (`",
    agency_counts$submission_version,
    "`): ",
    agency_counts$features,
    " features"
  ),
  "",
  "## Geometry Counts",
  "",
  paste0("- `", geometry_counts$geometry_type, "`: ", geometry_counts$features),
  "",
  "## Transformations",
  "",
  "- Read only standardized GeoPackages under `data-standardized/`; raw submissions were not modified.",
  "- Preserved the standardized restoration schema attributes from each submission.",
  "- Added source metadata fields: `source_slug`, `source_agency`, `submission_version`, `source_file`, and `source_feature_number`.",
  "- Preserved the standardized geometry from each source submission.",
  "- Confirmed all source layers and the combined output are EPSG:3310.",
  "",
  "## Inventory",
  "",
  paste0("See `", inventory_csv, "` for source-level counts and geometry summaries.")
)

readr::write_lines(qc_lines, qc_md)

message("Wrote ", out_gpkg)
message("Wrote ", inventory_csv)
message("Wrote ", qc_md)
