#' Create a Directory If Needed
#'
#' Creates a directory recursively when it does not already exist.
#'
#' @param path Character path to create.
#'
#' @return The input path, invisibly.
dir_create <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE)
  }
  invisible(path)
}

#' Build Standard Submission Paths
#'
#' Creates the standard raw, standardized output, and report paths for a
#' submission that follows the repository naming conventions.
#'
#' @param slug Submitter slug used under `data-raw/`, `data-standardized/`, and
#'   `reports/`.
#' @param version Submission version in output naming format, such as
#'   `2026-05-22-v01`.
#' @param source_ext Source file extension without a leading dot.
#' @param schema_file Path to the schema YAML file.
#' @param out_layer Standardized output layer name.
#'
#' @return A named list of paths and standard output metadata.
submission_paths <- function(slug, version, source_ext = "gpkg",
                             schema_file = "schemas/hrl_restoration_project.yaml",
                             out_layer = "restoration_projects") {
  raw_version <- stringr::str_replace(version, "-v([0-9]+)$", "_v\\1")
  out_dir <- file.path("data-standardized", slug)
  report_dir <- file.path("reports", slug)

  list(
    schema_file = schema_file,
    source_gpkg = file.path("data-raw", slug, raw_version, paste0(raw_version, ".", source_ext)),
    out_dir = out_dir,
    report_dir = report_dir,
    out_gpkg = file.path(out_dir, paste0(version, ".gpkg")),
    out_layer = out_layer,
    inventory_csv = file.path(report_dir, paste0(version, "_inventory.csv")),
    validation_csv = file.path(report_dir, paste0(version, "_validation.csv")),
    qc_md = file.path(report_dir, paste0(version, "_qc.md")),
    qc_pdf = file.path(report_dir, paste0(version, "_qc.pdf"))
  )
}

#' Create Standard Submission Output Directories
#'
#' Creates the standardized data and report directories from a path list
#' returned by [submission_paths()].
#'
#' @param paths A submission path list.
#'
#' @return The input path list, invisibly.
dir_create_submission <- function(paths) {
  dir_create(paths$out_dir)
  dir_create(paths$report_dir)
  invisible(paths)
}

#' Normalize Blank Character Values to Missing
#'
#' Converts values to character, trims repeated whitespace, and converts empty
#' strings to `NA`.
#'
#' @param x A vector to normalize.
#'
#' @return A character vector.
null_to_na_chr <- function(x) {
  x <- as.character(x)
  x <- stringr::str_squish(x)
  dplyr::na_if(x, "")
}

#' Parse Currency-like Values as Integer Dollars
#'
#' Removes common currency formatting such as dollar signs and grouping commas,
#' then rounds to integer dollars.
#'
#' @param x A vector containing currency-like values.
#'
#' @return An integer vector.
parse_currency_integer <- function(x) {
  x <- null_to_na_chr(x)
  parsed <- readr::parse_number(x, locale = readr::locale(grouping_mark = ","))
  as.integer(round(parsed))
}

#' Split a Semicolon-delimited Value
#'
#' Splits one semicolon-delimited value into trimmed non-empty values.
#'
#' @param x A scalar character value.
#'
#' @return A character vector. Missing or empty input returns `character()`.
split_semicolon_values <- function(x) {
  if (is.na(x) || !nzchar(x)) {
    return(character())
  }

  stringr::str_split(x, "\\s*;\\s*", simplify = FALSE)[[1]] |>
    stringr::str_squish() |>
    purrr::discard(~ .x == "")
}

#' Normalize Semicolon-delimited Values
#'
#' Formats semicolon-delimited values with trimmed entries and a single space
#' after each delimiter. Blank values are returned as missing.
#'
#' @param x A vector containing semicolon-delimited values.
#'
#' @return A character vector.
normalize_semicolon_values <- function(x) {
  x <- null_to_na_chr(x)
  purrr::map_chr(x, function(value) {
    if (is.na(value)) {
      return(NA_character_)
    }
    paste(split_semicolon_values(value), collapse = "; ")
  })
}

#' Load a Restoration Schema Profile
#'
#' Loads the pinned HRL restoration schema and extracts field lists used by
#' cleaning scripts for a target schema class.
#'
#' @param schema_file Path to the schema YAML file.
#' @param class_name Schema class name to extract.
#'
#' @return A list containing the parsed schema, all fields, attribute fields,
#'   required fields, and required attribute fields.
load_schema_profile <- function(schema_file,
                                class_name = "RestorationProjectRecord") {
  schema <- yaml::yaml.load_file(schema_file)
  fields <- schema$classes[[class_name]]$slots
  required_fields <- names(purrr::keep(
    schema$classes[[class_name]]$slot_usage,
    ~ identical(.x$required, TRUE)
  ))

  list(
    schema = schema,
    fields = fields,
    attribute_fields = setdiff(fields, "geometry"),
    required_fields = required_fields,
    required_attribute_fields = setdiff(required_fields, "geometry")
  )
}

#' Read a Submission GeoPackage Layer
#'
#' Inventories a GeoPackage, optionally writes that inventory to CSV, and reads
#' the requested source layer.
#'
#' @param source_gpkg Path to the source GeoPackage.
#' @param source_layer Layer name to read.
#' @param inventory_csv Optional path to write inventory CSV.
#'
#' @return A list with `inventory` and `raw` elements.
read_submission_layer <- function(source_gpkg, source_layer,
                                  inventory_csv = NULL) {
  inventory <- inventory_gpkg(source_gpkg)
  if (!is.null(inventory_csv)) {
    readr::write_csv(inventory, inventory_csv)
  }

  list(
    inventory = inventory,
    raw = sf::st_read(source_gpkg, layer = source_layer, quiet = TRUE)
  )
}

#' Get Permissible Values from a Schema Enum
#'
#' Extracts permissible value names from a parsed HRL LinkML schema.
#'
#' @param schema A parsed schema object, such as the result of
#'   [yaml::yaml.load_file()].
#' @param enum_name Name of the enum to extract.
#'
#' @return A character vector of permissible values.
schema_enum_values <- function(schema, enum_name) {
  names(schema$enums[[enum_name]]$permissible_values)
}

#' Create an Empty Validation Table
#'
#' Creates the standard validation table used by submission cleaning scripts.
#'
#' @return A tibble with validation columns.
validation_tbl <- function() {
  tibble::tibble(
    severity = character(),
    check = character(),
    feature_id = character(),
    field = character(),
    submitted_value = character(),
    standardized_value = character(),
    message = character()
  )
}

#' Append a Validation Row
#'
#' Adds one validation, warning, or informational row to a validation table.
#'
#' @param rows Existing validation table.
#' @param severity Severity string, usually `error`, `warning`, or `info`.
#' @param check Check name.
#' @param feature_id Optional feature identifier.
#' @param field Optional field name.
#' @param submitted_value Optional original value.
#' @param standardized_value Optional standardized value.
#' @param message Human-readable validation message.
#'
#' @return A validation tibble.
append_validation <- function(rows, severity, check, feature_id = NA_character_,
                              field = NA_character_,
                              submitted_value = NA_character_,
                              standardized_value = NA_character_,
                              message = NA_character_) {
  dplyr::bind_rows(
    rows,
    tibble::tibble(
      severity = severity,
      check = check,
      feature_id = as.character(feature_id),
      field = field,
      submitted_value = as.character(submitted_value),
      standardized_value = as.character(standardized_value),
      message = message
    )
  )
}

#' Validate a Semicolon-delimited Controlled Vocabulary Field
#'
#' Checks each semicolon-delimited value in a field against an allowed set and
#' appends validation errors for values outside the vocabulary.
#'
#' @param rows Existing validation table.
#' @param data An `sf` object or data frame.
#' @param field Field name to validate.
#' @param allowed Character vector of allowed values.
#' @param feature_id_col Column used to identify features in validation output.
#'
#' @return A validation tibble.
validate_enum_field <- function(rows, data, field, allowed,
                                feature_id_col = "project_name") {
  if (inherits(data, "sf")) {
    data <- sf::st_drop_geometry(data)
  }

  invalid <- data |>
    dplyr::transmute(
      feature_id = .data[[feature_id_col]],
      value = .data[[field]]
    ) |>
    dplyr::rowwise() |>
    dplyr::mutate(
      invalid_values = list(setdiff(split_semicolon_values(value), allowed))
    ) |>
    dplyr::ungroup() |>
    dplyr::filter(lengths(invalid_values) > 0)

  purrr::reduce(
    seq_len(nrow(invalid)),
    function(acc, i) {
      append_validation(
        acc,
        "error",
        "controlled_vocabulary",
        invalid$feature_id[[i]],
        field,
        invalid$value[[i]],
        NA_character_,
        paste("Invalid value(s):", paste(invalid$invalid_values[[i]], collapse = "; "))
      )
    },
    .init = rows
  )
}

#' Inventory Layers in a GeoPackage
#'
#' Reads layer metadata from a GeoPackage and returns a normalized inventory
#' table suitable for CSV reports.
#'
#' @param source_gpkg Path to a GeoPackage.
#'
#' @return A tibble with source file, layer name, geometry type, feature count,
#'   field count, and CRS name.
inventory_gpkg <- function(source_gpkg) {
  sf::st_layers(source_gpkg, do_count = TRUE) |>
    tibble::as_tibble() |>
    dplyr::transmute(
      source_file = source_gpkg,
      layer_name = name,
      geometry_type = purrr::map_chr(geomtype, paste, collapse = "; "),
      features,
      fields,
      crs_name = purrr::map_chr(crs, function(x) {
        if (is.null(x$input) || is.na(x$input)) {
          NA_character_
        } else {
          x$input
        }
      })
    )
}

#' Write a Standard Submission QC Report
#'
#' Writes the common Markdown QC report structure for standardized HRL
#' submissions. Submission-specific transformations and review items are passed
#' in as preformatted Markdown bullet lines so the report format is consistent
#' while assumptions remain explicit in each cleaning script.
#'
#' @param path Output Markdown path.
#' @param title Report title without the leading Markdown heading marker.
#' @param source_file Source data path.
#' @param source_layer Source layer name.
#' @param inventory One-row inventory table, such as the output from
#'   [inventory_gpkg()].
#' @param validation Validation table.
#' @param output_file Standardized output path.
#' @param output_layer Standardized output layer name.
#' @param output_rows Number of output features.
#' @param output_crs Output CRS label.
#' @param target_profile Target schema profile name.
#' @param transformations Character vector of Markdown bullet lines describing
#'   transformations.
#' @param review_items Character vector of Markdown bullet lines describing
#'   unresolved questions or manual-review items.
#' @param validation_file Path to the validation CSV.
#' @param pdf_path Optional output PDF path. When supplied, the Markdown report
#'   is also rendered to PDF with Quarto.
#' @param omitted_program_fields Optional character vector of omitted canonical
#'   or system fields.
#' @param omitted_source_fields Optional character vector of omitted raw/helper
#'   fields.
#'
#' @return The output path, invisibly.
write_qc_report <- function(path, title, source_file, source_layer,
                            inventory, validation, output_file,
                            output_layer, output_rows,
                            output_crs = "EPSG:3310",
                            target_profile = "RestorationProjectSubmission",
                            transformations = character(),
                            review_items = character(),
                            validation_file = NULL,
                            pdf_path = NULL,
                            omitted_program_fields = character(),
                            omitted_source_fields = character()) {
  errors <- validation |> dplyr::filter(severity == "error")
  warnings <- validation |> dplyr::filter(severity == "warning")
  infos <- validation |> dplyr::filter(severity == "info")

  validation_summary <- c(
    paste0("- Errors: ", nrow(errors)),
    paste0("- Warnings: ", nrow(warnings)),
    paste0("- Informational notes: ", nrow(infos))
  )

  omitted_lines <- character()
  if (length(omitted_program_fields) > 0) {
    omitted_lines <- c(
      omitted_lines,
      paste0(
        "- Program/system fields omitted from output: `",
        paste(omitted_program_fields, collapse = "`, `"),
        "`"
      )
    )
  }
  if (length(omitted_source_fields) > 0) {
    omitted_lines <- c(
      omitted_lines,
      paste0(
        "- Source helper fields omitted from output: `",
        paste(omitted_source_fields, collapse = "`, `"),
        "`"
      )
    )
  }

  if (length(transformations) == 0) {
    transformations <- "- No transformations documented."
  }
  if (length(review_items) == 0) {
    review_items <- "- No remaining review items documented."
  }

  validation_detail <- if (is.null(validation_file)) {
    "No validation CSV path supplied."
  } else {
    paste0("See `", validation_file, "` for row-level validation details.")
  }

  lines <- c(
    paste0("# ", title),
    "",
    "## Input Inventory",
    "",
    paste0("- Source file: `", source_file, "`"),
    paste0("- Source layer: `", source_layer, "`"),
    paste0("- Feature count: ", inventory$features[[1]]),
    paste0("- Geometry type: ", inventory$geometry_type[[1]]),
    paste0("- CRS: ", inventory$crs_name[[1]]),
    paste0("- Field count: ", inventory$fields[[1]]),
    "",
    "## Output",
    "",
    paste0("- Target profile: `", target_profile, "`"),
    paste0("- Output file: `", output_file, "`"),
    paste0("- Output layer: `", output_layer, "`"),
    paste0("- Output feature count: ", output_rows),
    paste0("- Output CRS: `", output_crs, "`"),
    omitted_lines,
    "",
    "## Transformations",
    "",
    transformations,
    "",
    "## Validation Summary",
    "",
    validation_summary,
    "",
    "## Remaining Review Items",
    "",
    review_items,
    "",
    "## Validation Details",
    "",
    validation_detail
  )

  readr::write_lines(lines, path)
  if (!is.null(pdf_path)) {
    render_qc_report_pdf(path, pdf_path)
  }
  invisible(path)
}

#' Render a QC Markdown Report to PDF
#'
#' Renders a Markdown QC report to PDF using Quarto's Typst format. This helper
#' is intentionally small: Markdown remains the primary report artifact, and PDF
#' rendering is a derived convenience copy.
#'
#' @param md_path Markdown report path.
#' @param pdf_path Output PDF path.
#'
#' @return The PDF path, invisibly.
render_qc_report_pdf <- function(md_path, pdf_path) {
  quarto <- Sys.which("quarto")
  if (!nzchar(quarto)) {
    warning("Quarto is not available; skipped PDF report: ", pdf_path, call. = FALSE)
    return(invisible(pdf_path))
  }

  report_dir <- dirname(pdf_path)
  dir_create(report_dir)

  qmd_path <- file.path(
    report_dir,
    paste0(".", tools::file_path_sans_ext(basename(pdf_path)), ".qmd")
  )
  typ_path <- sub("\\.qmd$", ".typ", qmd_path)
  support_dir <- file.path(
    report_dir,
    paste0(tools::file_path_sans_ext(basename(qmd_path)), "_files")
  )
  quarto_dir <- file.path(report_dir, ".quarto")

  readr::write_lines(
    c("---", "format: typst", "---", "", readr::read_lines(md_path)),
    qmd_path
  )

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  on.exit(unlink(c(qmd_path, typ_path, support_dir, quarto_dir), recursive = TRUE), add = TRUE)
  setwd(report_dir)

  result <- system2(
    quarto,
    c("render", basename(qmd_path), "--output", basename(pdf_path)),
    stdout = TRUE,
    stderr = TRUE
  )

  status <- attr(result, "status")
  if (!is.null(status) && !identical(status, 0L)) {
    warning(
      "Quarto PDF render failed for ",
      pdf_path,
      ":\n",
      paste(result, collapse = "\n"),
      call. = FALSE
    )
  }

  invisible(pdf_path)
}
