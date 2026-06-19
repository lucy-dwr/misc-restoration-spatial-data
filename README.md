# Miscellaneous Restoration Spatial Data

This repository is a working area for converting restoration spatial data
submissions into standardized GeoPackages that follow the HRL restoration
spatial data model.

The schema source of truth lives in
[`lucy-dwr/hrl-restoration-schema`](https://github.com/lucy-dwr/hrl-restoration-schema).
This repository should consume that schema and keep data-cleaning decisions,
patches, validation reports, and standardized outputs organized by submission.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `data-raw/` | Original submitted files, grouped by submitting entity. Treat these as immutable source material. |
| `data-standardized/` | Derived GeoPackages that have been reshaped to the HRL submission or canonical model. |
| `docs/` | Workflow notes, decision logs, and project-specific guidance. |
| `reference/` | Local copies or generated artifacts from the schema repository, if needed for offline work. |
| `reports/` | Validation reports, QA summaries, and review notes. |
| `schemas/` | Pinned schema artifacts automatically copied from tagged releases of the schema repository. The upstream LinkML schema remains authoritative. |
| `scripts/` | Repeatable conversion, validation, and patching scripts. |

## Current Workflow

1. Preserve each incoming submission under `data-raw/`.
2. Inspect layers, geometry types, CRS, and available attributes.
3. Map submitted fields to the HRL schema.
4. Apply documented fixes or transformations in scripts.
5. Write standardized GeoPackage outputs under `data-standardized/`.
6. Produce validation or QA reports under `reports/`.
7. Record unresolved assumptions or manual decisions in `docs/decisions.md`.

See [docs/workflow.md](docs/workflow.md) for the detailed workflow.

## Schema Baseline

The schema repository currently defines:

- `RestorationProjectSubmission`: fields expected from submitting entities.
- `RestorationProjectCanonicalRecord`: standardized records after validation and
  ingestion, including program-assigned fields such as `project_id` and
  `update_date`.
- Geometry policy allowing submitted `POLYGON`, `MULTIPOLYGON`, `POINT`, and
  `MULTIPOINT`, with standardized CRS `EPSG:3310`.

When schema behavior is unclear, update this repository's decision log and, if
needed, make the actual schema change upstream in `hrl-restoration-schema`.

## Schema Updates

This repository should consume released schema snapshots. The intended
automation is:

1. A new tagged release is published in `lucy-dwr/hrl-restoration-schema`.
2. A GitHub Action opens a pull request here with updated files under
   `schemas/`.
3. The pull request is reviewed alongside any needed workflow or validation
   changes.
