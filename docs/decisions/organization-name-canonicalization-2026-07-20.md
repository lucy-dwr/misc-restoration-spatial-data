# Organization-Name Canonicalization 2026-07-20

`scripts/canonicalize-organization-names.R` expands the following standalone
organization abbreviations in every standardized character field:

- `EBMUD`: East Bay Municipal Utility District
- `SFPUC`: San Francisco Public Utilities Commission
- `SCWA`: Solano County Water Agency
- `MID`: Modesto Irrigation District
- `TID`: Turlock Irrigation District
- `CDFW`: California Department of Fish and Wildlife
- `CNRA`: California Natural Resources Agency
- `USFWS`: U.S. Fish and Wildlife Service

The funding-source review CSV is updated at the same time to preserve the
canonical names in future update runs. Raw submissions remain unchanged.
