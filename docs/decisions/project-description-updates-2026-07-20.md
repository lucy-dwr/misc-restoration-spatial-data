# Project-Description Updates 2026-07-20

The reviewed `updated_description` values in `project-description-updates.csv` are
applied to standardized source GeoPackages by
`scripts/apply-project-description-updates.R`.

## Decision

- Each reviewed `updated_description` replaces `project_description` on its
  uniquely matched standardized project record.
- The script stops if a project cannot be uniquely matched, if the existing
  description differs from the CSV's recorded original value, or if a revised
  description exceeds the 500-character schema limit.
- Raw submissions remain unchanged; the multi-agency GeoPackage is regenerated
  after source-level descriptions are updated.
