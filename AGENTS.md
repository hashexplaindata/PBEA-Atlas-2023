# AGENTS.md: Pakistan Digital Census Analysis Project

## Project Overview
This is a **single reproducible analysis document** using R/RMarkdown that constructs a district-level typology of digital readiness in Pakistan. The core file is `PBEA_Master_Analysis.Rmd`, which knits to generate HTML output, figures, and `PBEA_District_Results.csv`.

**Framework:** COM-B (Capability-Opportunity-Motivation-Behavior) mapping onto the Pakistan Digital Census 2023.

---

## Critical Build & Execution Pattern

**Knit the Rmd file to regenerate everything:**
- Command: In RStudio, `Ctrl+Shift+K` to knit `PBEA_Master_Analysis.Rmd`
- Generates: HTML report + PNG/PDF figures + CSV results
- Time: ~2–3 minutes depending on PERMANOVA iterations
- Reproducibility: Set seed set to 42 in setup chunk; all results are deterministic

**Dependencies (must be installed):**
```R
install.packages(c("PakPC2023", "data.table", "ggplot2", "dplyr", 
                   "tidyr", "cluster", "factoextra", "vegan", 
                   "corrplot", "knitr", "rmarkdown", "sf"))
```

---

## Data Pipeline Architecture

### The Four Indices
The project constructs exactly four composite indices from census tables, each with specific formulas:

1. **HCI (Human Capability Index):** Mean of normalized [literacy, enrolment rate, 1 - out-of-school rate]
   - Source: `TABLE_12` (disaggregated by age, education level, region)
   - Key operation: Aggregate tehsil-level counts to district level by summing populations and computing weighted rates
   - Code: Lines 196–246

2. **FCI (Friction Coefficient Index):** Mean of inverted [electrification, modern fuel, water, toilets, ownership] + crowding (1-room%)
   - Source: `TABLE_22`, `TABLE_23`, `TABLE_24`, `TABLE_25`
   - Key pattern: All tables have REGION column (OVERALL, RURAL, URBAN)—always filter to REGION == "OVERALL"
   - Code: Lines 250–311

3. **LAP (Linguistic Alignment Penalty):** Literacy rate × (1 - % Urdu speakers)
   - Source: `TABLE_11`
   - **Critical bug trap:** TABLE_11 includes a "TOTAL" row per tehsil that sums all languages. Must exclude with `TABLE_11[LANGUAGE != "TOTAL"]` or results double-count
   - Code: Lines 315–337

4. **SOI (Social Opportunity Index):** Mean of normalized [literacy as proxy for female literacy, 1 - dependency ratio, youth concentration, female ownership rate]
   - Source: `TABLE_05` (age groups), `TABLE_25` (female ownership)
   - Key pattern: Age groups have exact labels like "15 - 64" (with trailing spaces), not just "15_64"
   - Code: Lines 341–381

### Merge Pattern (data.table-specific)
All indices are merged sequentially by DISTRICT key:
```R
pbea <- hci_dist[fci_dist[lap_dist[soi_dist, on="DISTRICT"], on="DISTRICT"], on="DISTRICT"]
```
Check completeness before clustering: `sum(complete.cases(pbea[, .(hci, fci, lap, soi)]))` (n=135 district after excluding Islamabad).

---

## Project-Specific Conventions

### Min-Max Normalization
Custom function (not R's built-in scale):
```R
min_max <- function(x) {
  rng <- range(x, na.rm = TRUE)
  if (diff(rng) == 0) return(rep(0.5, length(x)))  # Handle flat columns
  (x - rng[1]) / diff(rng)
}
```
Used consistently across all index components.

### Two Archetype Classification Schemes
- **Tercile-based** (strict): Top/bottom 33% = High/Low—theoretically pure, but produces zero Coiled Springs
- **Median-split** (actionable): Top/bottom 50% = High/Low—identifies 18 "relative Coiled Springs" for strategic targeting
- Use `fcase()` (data.table's switch) for clean archetype assignment

### Cluster Validation Stack
- **Elbow method:** WSS on scaled 4D indices
- **Silhouette score:** Average silhouette width
- **PERMANOVA (9,999 permutations):** Tests statistical distinctness of k-means centroids (expect ~55% R² for k=4)
- k is theoretically fixed at 4 (matching COM-B's 4 archetypes), not data-driven

---

## Common Pitfalls & Workarounds

| Issue | Fix |
|-------|-----|
| LAP double-counts population | Exclude `TABLE_11[LANGUAGE == "TOTAL"]` before aggregating |
| Provinces don't align across tables | Create lookup table from TABLE_12, merge right (`prov_lookup[pbea, on="DISTRICT"]`) |
| Age group labels have trailing spaces | Use exact labels: `"15 - 64"` not `"15-64"` |
| Missing Islamabad | Expected (incomplete age data); n=135 districts in results |
| FCI interpretation backwards | Inverted (higher = more friction). LAP and SOI are also inverted. Check sign in index formulas. |
| Sparse REGION='URBAN' data | Always use REGION=="OVERALL" to avoid small-sample noise |
| k-means non-reproducible | Set seed before `kmeans()`: `set.seed(42)` |

---

## Key Files & Their Roles

| File | Purpose |
|------|---------|
| `PBEA_Master_Analysis.Rmd` | Master notebook: all analysis, figures, export (758 lines, knit to regenerate) |
| `PBEA_Master_Analysis.html` | Output: interactive HTML report with folded code |
| `PBEA_District_Results.csv` | Output: 135 rows × 13 columns (districts, indices, archetypes, component rates) |
| `.idea/rSettings.xml` | RStudio project config (IDE preferences) |
| `DDI_table_2024.pdf`, `National-Human-Development-Report-2024.pdf` | Reference documents (for context, not used in analysis) |
| `PBEA_District_Results.csv` | **Export target** for all results; replicated rows (see note below) |

**Note on CSV:** Rows are duplicated (one with PROVINCE, one without). This is intentional from the export logic; ignore duplicates when loading for analysis.

---

## Extending the Analysis

### Adding a New Census Table
1. Load via `data(TABLE_XX)`, append to "# Load" chunk (lines 171–187)
2. Understand the structure: is it OVERALL/RURAL/URBAN? Are tehsil totals separate?
3. Aggregate to district using `[, .(...), by=DISTRICT]`, merge with `pbea` key
4. Add new index or component rate to `export_cols` (line 699) and re-knit

### Modifying an Index Formula
- Edit the specific index construction chunk (HCI: 196–246, FCI: 250–311, LAP: 315–337, SOI: 341–381)
- Must re-run master merge (chunk 385–415) to propagate changes
- Re-knit entire document to regenerate downstream figures and PERMANOVA

### Geographic Disaggregation
- No district centroid coordinates in PakPC2023 → Moran's I not possible
- Current workaround: Chi-square for province-archetype association (lines 651–668)
- To add district-level mapping: source external shapefile, merge by DISTRICT=district name

---

## Workflow Tips

1. **For exploratory changes:** Knit only up to a specific chunk using RStudio "Run chunks up to here" rather than full knit
2. **For reproducibility checks:** Change `set.seed(42)` to a different value—if results stay stable, model is robust
3. **For stakeholder output:** HTML report (auto-generated) is the primary deliverable; CSV is for secondary analysis
4. **For debugging:** Print data dimensions at each merge step: `cat("Merged shape:", nrow(...), "x", ncol(...))`
5. **For pkg updates:** After installing new package versions, check that `min_max()` and aggregate logic still work (especially data.table syntax)

---

## External Dependencies & Limitations

- **PakPC2023 R package** is the single authoritative data source (tehsil-level census tabulations)
- No direct ICT data (internet, mobile, computer ownership) → uses general infrastructure as proxy
- The analysis is **descriptive, not causal:** district patterns ≠ individual behavior
- COM-B's **Motivation component is unmeasured** (census has no attitudinal data)
- **No temporal dynamics** (cross-sectional snapshot from March 2023)

---

## For AI Agents: Quick Mental Model

Think of this project as a **sterile, reproducible pipeline** for producing a district diagnostic typology:
- **Input:** 7 census tables, filtered & aggregated → 4 composite indices
- **Process:** k-means clustering on 4D space, validated with PERMANOVA
- **Output:** 135 district records with archetype labels (Vanguard/Anchor/Coiled Spring/Trapped) + component scores
- **Constraint:** Must maintain exact formulas & specific data.table operations; no substitutions without re-validating PERMANOVA

The archetypes are **not aspirational**—they describe the *structural* bundling of capability and friction as measured by census data. The analysis succeeds or fails on whether results are reproducible, statistically validated, and methodologically transparent.

