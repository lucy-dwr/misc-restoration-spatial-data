# DWR Name Canonicalization 2026-07-20

`scripts/canonicalize-dwr-entity-and-funder.R` replaces the standalone value
`DWR` with `California Department of Water Resources` in standardized
`lead_entity` values and semicolon-delimited `funding_sources` values.

Longer submitted terms are not changed unless they are the standalone list value
`DWR`. The funding-source review CSV is updated at the same time so subsequent
review-file applications do not reverse the canonicalization.
