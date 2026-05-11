# Final QA Report - Census 2023 Merge

Date: 2026-05-11

## Scope
- Dataset: Four-Province Atlas + ICT
- District spine rows: 136
- Excludes: AJK, GB (not present in `PakPC2023PakDist`)

## Run Status
- Script: `datasets_Census23_CranR/merge_districts_REFACTORED.R`
- Status: PASS
- Output: `datasets_Census23_CranR/Merged_Districts_REFACTORED.csv`
- Audit: `datasets_Census23_CranR/Merge_Audit_Trail.csv`

## Integrity Checks
- Row count: 136
- Join match rates:
  - Disability: 136/136
  - Language: 136/136
  - Literacy: 136/136
  - Energy: 136/136
  - Sanitation: 136/136
  - Water: 136/136
  - Age: 135/136
  - Marital: 136/136
- Rate validation: all computed rate variables within [0,1]
- Non-negativity: all numeric count variables non-negative

## Known Limitation
- Missing age data for district `ICT` only.
- In output CSV, `ICT` has `NA` for `Age_*` columns.

## Recommendation
- Use the merged dataset as production-ready for current scope.
- Keep the age-data caveat in methods and any publication notes.
- If required, add a separate data-repair step for `ICT` age fields when source data is available.
