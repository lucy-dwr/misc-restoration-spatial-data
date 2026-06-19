# Raw Submissions

This directory contains raw spatial data submissions received from HRL data
contributors. These files are source material for the cleaning and
standardization workflow.

The same raw files also live in a DWR Azure Data Lake with submission manifests.
Those manifests are the authoritative record for submission metadata such as
submitter, receipt date, original file names, storage location, and any delivery
notes. This directory is a local working copy for processing.

## Current Organization

Files are grouped by submitting entity:

```text
data-raw/<submitting-entity>/<received-date>_<version>.<extension>
```

Current submitter folders:

| Folder | Submitter |
| --- | --- |
| `ebmud/` | East Bay Municipal Utilities District |
| `sbfca/` | Sutter Buttes Flood Control Agency |
| `scwa/` | Solano County Water Agency |
| `sfpuc/` | San Francisco Public Utilities Commission |
| `water-forum/` | Water Forum |
| `ywa/` | Yuba Water Agency |

## Handling Rules

- Treat raw files as immutable. Do not edit, overwrite, rename, or re-save them
  in place.
- Put standardized outputs in `data-standardized/`.
- Put inventories, validation reports, and QA notes in `reports/`.
- Document interpretation, corrections, or source-data issues in
  `docs/decisions.md` or the relevant report.
- If a local file differs from the Azure Data Lake copy or manifest, resolve the
  discrepancy before using it as input.

## Versioning Notes

The dated `vNN` or `vNN-N` suffixes are submission versions, not schema
versions. Schema versions are tracked separately under `schemas/`.

Large raw spatial files may be ignored by Git. Use `git status` to confirm what
is actually tracked before assuming these local files are part of repository
history.
