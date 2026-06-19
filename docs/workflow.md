# Standardization Workflow

This workflow turns raw submitted spatial files into HRL-standardized
GeoPackages. It assumes inputs may be GeoPackages, shapefiles, zipped
shapefiles, related spatial file bundles, or spatial files paired with separate
attribute workbooks.

## 1. Locate Source Materials

Store each submission under `data-raw/` without editing the original files. Use
a stable folder name such as:

```text
data-raw/<entity-or-system>/<YYYY-MM-DD-or-batch-name>/
```

Do not recreate intake metadata in this repository. Submitter, receipt date,
original file names, storage locations, and delivery notes live in submission
manifests in the DWR Azure Data Lake. Use those manifests as the authoritative
record for intake metadata.

## 2. Inventory

For every submitted file, inspect:

- File format
- Layer names
- Feature count per layer
- Geometry type per layer
- CRS per layer
- Attribute names and types
- Whether project attributes are embedded in the spatial file or supplied in a
  separate table such as an XLSX workbook
- Join keys or row-order assumptions needed to connect separate attributes to
  geometry
- Empty geometries
- Obvious duplicate features

The inventory should be scriptable where possible and saved to `reports/`.

## 3. Target Profile

Choose the output profile before transforming fields:

- `RestorationProjectSubmission` for schema-compliant submitted records.
- `RestorationProjectCanonicalRecord` only when the workflow is intentionally
  assigning canonical fields such as `project_id`, `funding_gap`, and
  `update_date`.

Default assumption for this repository: create standardized submission-profile
GeoPackages unless the user decides this repo should also perform canonical
ingestion.

## 4. Field Mapping

Build a mapping from submitted fields to HRL schema fields. Some submissions
may include all attributes in a GeoPackage layer; others may provide geometry
in a spatial file and project attributes in a separate XLSX workbook. In those
cases, the cleaning process must explicitly join or otherwise align the
attribute rows to the spatial features before writing the standardized
GeoPackage.

The current submission profile expects these shared project fields:

```text
project_name
project_description
project_stage
contact_name
contact_email
lead_entity
contractors
early_implementation
construction_start_year
construction_completion_year
construction_completion_year_comments
estimated_budget
estimated_budget_comments
funding_secured
funding_gap
funding_sources
system
project_type
acreage
acreage_bypass_floodplain
acreage_fish_food
acreage_tributary_floodplain
acreage_tributary_rearing
acreage_tributary_spawning
acreage_tidal_wetland
target_species
geometry
```

Document mappings that are not one-to-one. Examples:

- Renamed fields
- Attributes joined from an external workbook
- Join keys used to connect tabular attributes to spatial features
- Row-order alignments, if no key exists
- Combined fields
- Split multivalue fields
- Controlled vocabulary normalization
- Numeric cleaning, such as removing `$` or comma separators
- Text truncation to schema limits
- Values inferred from file name, folder name, or submission context
- Fields left blank because the raw submission did not contain enough
  information

## 5. Value Repair And Submission-Specific Cleaning

Some submissions may contain weird, missing, or idiosyncratic values that need
targeted cleaning before they can pass schema validation. This can include
misspelled controlled vocabulary values, inconsistent date or year formats,
currency strings in numeric fields, blank strings that should become missing
values, multiple values packed into one cell, or attributes that need to be
recovered from notes, filenames, workbook tabs, or other submitted context.

Use repeatable cleaning code for these repairs, even when the logic is specific
to one submitter or one submission. Submission-specific code is acceptable when
the raw data are idiosyncratic, but the script or QC report must make clear:

- Which raw value was repaired
- What standardized value was written
- Why the repair was made
- Whether the repair was mechanical or interpretive
- Which values remain missing because the raw submission did not contain enough
  information

If a repair requires an assumption that is not obvious from the submitted data,
Azure manifest, known background information, or HRL context, pause and confirm
the assumption with the data submitter. Do not invent missing project facts
solely to satisfy the schema.

## 6. Geometry Standardization

The schema policy allows submitted `POLYGON`, `MULTIPOLYGON`, `POINT`, and
`MULTIPOINT`. Standardized outputs should use `EPSG:3310`.

Geometry QA should check:

- CRS is present
- CRS can be transformed to `EPSG:3310`
- Geometries are non-empty
- Geometries are valid
- Features fall within the expected California extent
- Slivers or tiny artifacts are flagged using agreed thresholds
- Duplicate geometries are flagged
- Geometry type is consistent with `project_type`

Expected geometry interpretation:

- Restoration areas are normally polygons or multipolygons
- Fish passage and fish screen installation or improvement may be represented
  as points or multipoints

## 7. Business Rules

Apply or report these checks:

- `construction_completion_year` should not be earlier than
  `construction_start_year`
- `funding_gap` should equal `estimated_budget - funding_secured` when those
  values are available
- Lead entity and contacts may need review against program-level reference
  tables
- Program-assigned fields should not be introduced unless producing canonical
  records

## 8. Output

Write one standardized GeoPackage per cleaned submission or per agreed delivery
unit:

```text
data-standardized/<entity-or-system>/<submission-name>.gpkg
```

Use clear layer names. A practical default is:

```text
restoration_projects
```

Each output run should have a companion report:

```text
reports/<entity-or-system>/<submission-name>_validation.csv
reports/<entity-or-system>/<submission-name>_qc.md
```

Quality control reports should be generous, well-formatted, and
human-readable. They should explain:

- Which fields, values, or geometries failed schema, vocabulary, business-rule,
  or geometry checks
- How each failure was corrected in this repository's cleaning process
- Which submitted values were normalized, calculated, truncated, joined from a
  workbook, or otherwise transformed
- Which required or expected fields remain blank in the standardized output
  because the raw submission did not include the needed data
- Which records or datasets could not be cleaned or repaired, such as
  submissions with missing geometry
- Suggested remedies for missing, ambiguous, or unrecoverable data

Validation CSVs can support scripting and review, but the Markdown QC report is
the primary human-facing artifact.

## 9. Review

Before considering a standardized GeoPackage ready:

- Confirm field names match the target schema profile
- Confirm required fields are populated or explicitly reported
- Confirm controlled vocabularies match schema values exactly
- Confirm CRS is `EPSG:3310`
- Confirm geometry validity checks pass or are documented
- Confirm separately submitted workbook attributes, if any, were joined to the
  intended spatial features
- Confirm all interpretive edits are listed in the report or decision log

## 10. Schema Updates

If the workflow reveals a missing field, unclear vocabulary, or unrealistic
business rule, record it in `docs/decisions.md`. Actual schema updates should be
made in `lucy-dwr/hrl-restoration-schema`, then consumed here through updated
schema artifacts.
