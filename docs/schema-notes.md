# Schema Notes

The HRL restoration schema is maintained at
<https://github.com/lucy-dwr/hrl-restoration-schema>.

This repository should keep a pinned copy of released schema artifacts under
`schemas/`. Do not update those files from the schema repository's live `main`
branch for routine processing; use tagged releases submitted to this repository 
with a GitHub Actions-driven pull request so that each standardized output can
be tied to a known schema version.

Important current schema facts for this repository:

- The maintained source of truth is `schemas/hrl_restoration_project.yaml` in
  the schema repository.
- `RestorationProjectSubmission` describes fields expected from submitters.
- `RestorationProjectCanonicalRecord` adds program-assigned and
  system-maintained fields.
- Submitters should not provide `project_id` or `update_date`.
- Controlled vocabularies must match schema enum values.
- Multivalue fields may be serialized as semicolon-delimited strings in spatial
  files.
- Geometry is represented by the spatial feature geometry column, not a normal
  attribute field.
- Submitted geometry types may be `POLYGON`, `MULTIPOLYGON`, `POINT`, or
  `MULTIPOINT`.
- Standardized CRS is `EPSG:3310`.

## Controlled Vocabulary Fields

- `project_stage`
- `system`
- `project_type`
- `target_species`

## Multivalue Fields

- `project_stage`
- `contractors`
- `funding_sources`
- `project_type`
- `target_species`

## Program Or System Fields

These should only appear when producing canonical records:

- `project_id`
- `update_date`

`funding_gap` is stricter in canonical records and may be derived from
`estimated_budget - funding_secured`.
