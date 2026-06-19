# Water Forum 2026-05-27-v01 Decisions

Decision log for the Water Forum submission standardized by
`scripts/clean-water-forum-2026-05-27-v01.R`.

## Decisions

- Standardized output targets `RestorationProjectSubmission`; submitted
  `project_id` and `update_date` are omitted as program-assigned
  canonical-record fields.
- Source field `construction_completion_year_co` is treated as the truncated
  source name for `construction_completion_year_comments`.
- Submitted `early_implementation` value `Yes` is standardized as `TRUE`.
- Submitted `estimated_budget_comments` value `N/A` is treated as missing.
- Submitted semicolon-delimited values are preserved but normalized to use a
  single space after each semicolon.
- Submitted acreage values are preserved rather than replaced with
  geometry-derived acreage.

## Open Questions

No open questions.
