# Decisions And Open Questions

Use this file for repository-wide workflow choices. Keep submission- and
agency-specific assumptions in separate files under `docs/decisions/` so this
index stays readable.

## Decisions

- Raw submissions in `data-raw/` are treated as immutable source material.
- Standardized GeoPackages are written to `data-standardized/`.
- Validation and QA reports are written to `reports/`.
- The upstream schema repository remains the schema source of truth.
- This repo pins schema artifacts under `schemas/` from tagged releases of the
  schema repository.
- A GitHub Action should open a pull request here whenever the schema repository
  publishes a new tagged release.
- Default output profile is `RestorationProjectSubmission` unless Lucy decides
  this repository should assign canonical fields.
- Raw submitter folder names use short lowercase slugs mapped to full submitter
  names in `data-raw/README.md`.
- Standardized GeoPackages in this repository should target
  `RestorationProjectSubmission`.
- The standard output layer should be `restoration_projects`.
- Failed submissions should produce both corrected GeoPackages and well-formatted,
  human-readable validation reports.
- Geometry QA will initially flag polygon slivers under 0.01 acres, exact
  duplicate geometries, near duplicates within 1 meter and 1 percent area
  difference, and features outside California. Sliver and near-duplicate checks
  are warnings pending manual review; empty, invalid, or clearly out-of-state
  geometries are errors.
- Submission- and agency-specific decision logs are stored under
  `docs/decisions/`.

## Submission-Specific Logs

- [EBMUD 2026-05-22-v01](decisions/ebmud-2026-05-22-v01.md)

## Open Questions

1. Should large raw submissions and standardized GeoPackages be tracked in Git,
   Git LFS, or kept outside version control?
2. What are the authoritative program-level reference tables for lead entities,
   contacts, project IDs, and known aliases?
3. What review process should apply before overwriting a submitter-provided
   value with an inferred or calculated value?
