source("renv/activate.R")

output_csv <- "funding-source-updates.csv"

input_files <- list.files(
  "data-standardized/multi-agency",
  pattern = "_attributes\\.csv$",
  full.names = TRUE
)

if (length(input_files) == 0) {
  stop("No combined attribute CSV found.", call. = FALSE)
}

input_csv <- tail(sort(input_files), 1)

review <- readr::read_csv(input_csv, show_col_types = FALSE) |>
  dplyr::transmute(
    project_name,
    current_funding_sources = funding_sources,
    updated_funding_sources = NA_character_
  ) |>
  dplyr::arrange(project_name)

readr::write_csv(review, output_csv, na = "")

message("Wrote ", output_csv)
