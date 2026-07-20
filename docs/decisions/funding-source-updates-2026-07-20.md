# Funding-Source Updates 2026-07-20

The reviewed values in the root-level `funding-source-updates.csv` are applied
to standardized source GeoPackages by `scripts/apply-funding-source-updates.R`.

## Decision

- A non-empty `updated_funding_sources` value replaces the corresponding
  standardized `funding_sources` value for the same unique `project_name`.
- Values are normalized as semicolon-delimited lists before application.
- The script stops if a reviewed project cannot be matched uniquely or if its
  current standardized value does not match the CSV's recorded prior value.
- Raw submissions remain unchanged; the multi-agency GeoPackage is regenerated
  after the source-level updates are applied.
