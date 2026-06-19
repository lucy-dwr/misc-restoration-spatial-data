# Repository Guidelines

This repository cleans and standardizes submitted restoration spatial datasets
into GeoPackages that follow the HRL restoration schema.

## Source Of Truth

- The authoritative schema is
  `lucy-dwr/hrl-restoration-schema`, especially
  `schemas/hrl_restoration_project.yaml`.
- Do not duplicate schema rules here unless they are pinned as generated
  artifacts or documented as a temporary local decision.
- Program-assigned fields such as `project_id` and `update_date` belong to the
  canonical record profile, not ordinary submitter-provided inputs.

## Data Handling

- Treat `data-raw/` as immutable. Do not edit files in place.
- Write cleaned outputs to `data-standardized/`.
- Put validation reports, QA summaries, and manual review notes in `reports/`.
- Keep submission-specific assumptions and unresolved questions in
  `docs/decisions.md`.
- Large spatial files may be intentionally untracked. Check `.gitignore` and
  `git status` before assuming a file is committed.

## Workflow Expectations

For each submission:

1. Inventory the input file names, layers, geometry types, CRS, feature counts,
   and fields.
2. Decide whether the output targets `RestorationProjectSubmission` or
   `RestorationProjectCanonicalRecord`.
3. Map source fields to schema fields with explicit transformations.
4. Preserve raw values when possible, but normalize controlled vocabularies,
   multivalue fields, numeric types, dates, CRS, and geometry types as required.
5. Document destructive or interpretive changes before applying them.
6. Generate a validation or QA report with enough detail to reproduce the
   result.

## Coding Conventions

- This is an R-first repository. Default to R scripts and R project conventions
  unless the user explicitly asks for another language.
- Prefer repeatable scripts over one-off manual edits.
- Use `rg` for searching files.
- Use `sf` for spatial vector data, including reading GeoPackages/shapefiles,
  inspecting layers, transforming CRS, validating geometries, and writing
  GeoPackages.
- Prefer tidyverse-style data manipulation when it keeps transformations clear,
  especially `dplyr`, `stringr`, `readr`, `purrr`, and `tibble`.
- Use `yaml` or another structured parser for schema files; do not parse YAML
  with ad hoc string operations.
- Keep scripts scoped to one clear operation or submission until a reusable
  pattern emerges.
- Avoid hard-coding schema values in multiple places. Pull from pinned schema
  artifacts when possible.
- If Python or command-line GDAL tools are useful for a specific task, document
  why in the script or report. Do not introduce a parallel Python project
  structure unless requested.

## R Project Expectations

- Dependency management is handled with `renv`.
- Run `renv::restore()` before relying on project packages in a fresh checkout.
- After adding, removing, or upgrading R packages, run `renv::snapshot()` and
  commit the updated `renv.lock`.
- Do not install packages ad hoc inside processing scripts. Put package
  installation and dependency changes through `renv`.
- Put reusable R scripts under `scripts/` until a stronger package structure is
  justified.
- Prefer script entry points that can run with `Rscript --vanilla`.
- Keep exploratory notebooks or Quarto reports separate from reproducible
  cleaning scripts.
- Avoid editing raw spatial files in R sessions. Always write new files to
  `data-standardized/` or another documented derived-output location.

## Validation Priorities

Validation and QA should check at minimum:

- Required attributes for the selected schema profile.
- Controlled vocabulary values.
- Semicolon-delimited multivalue fields where applicable.
- Email format for `contact_email`.
- Year and numeric ranges.
- `construction_completion_year >= construction_start_year`.
- `funding_gap = estimated_budget - funding_secured` when applicable.
- CRS presence and transformability to `EPSG:3310`.
- Non-empty, valid geometries.
- Expected geometry type for the project type.

## Collaboration Notes

- Ask before making irreversible changes to submitted content or inventing
  values that are not present in the source material.
- If a submitted value is ambiguous, prefer a documented warning and a review
  queue over silent coercion.
- If schema rules need to change, notify the user and propose an issue that can
  be opened in the schema repository to update the rules.
