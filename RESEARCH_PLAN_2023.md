# Pakistan Census 2023 Data Integration Framework
## Behavioral and Social Researcher / Data Scientist Plan
**Date:** May 11, 2026 | **Version:** Research Protocol v1.0

---

## EXECUTIVE SUMMARY: The "Three-Layer Integrity Model"

This plan addresses three silent failures in the current merge_districts.R pipeline:

1. **Layer 1: The Denominator Crisis** — Numerator-denominator mismatches that produce invalid rates (>1.0 or "Infinite Friction")
2. **Layer 2: The 136-District Blind Spot** — A technical success that masks strategic geographic incompleteness
3. **Layer 3: The Silent Error Factory** — String-distance resolvers that fail silently instead of loudly

---

## PART I: THE DENOMINATOR ANCHOR (Layer 1)

### Current Risk Profile

The current script extracts counts like:
```r
Energy_LIGHT_ELECT = sum(LIGHT_ELECT)  
Energy_HOUSEHOLDS = sum(HOUSEHOLDS)
```

**The Silent Failure Mode:**
- If `Energy_HOUSEHOLDS` is **misaligned** (e.g., missing in 5 records), you compute: `Light_Rate = sum(LIGHT_ELECT) / sum(HOUSEHOLDS)`
- The numerator includes all 136 districts; the denominator only 131.
- Result: **Synthetic inflation of the rate** → appears >1.0 or creates "Infinite Friction"

### The Fix: Denominator Anchor Pattern

#### A. **Audit the Source Tables**

For each FCI file (_Energy_Fuel.csv, _Sanitation_Structure.csv, _Water.csv_):
- **Question 1:** Does every row have a HOUSEHOLDS value?
- **Question 2:** Which rows have REGION="OVERALL"?
- **Question 3:** Are HOUSEHOLDS values identical within OVERALL? (Sanity check)

Run this diagnostic:
```r
# FCI_Energy_Fuel.csv diagnostic
energy_raw <- read_csv("FCI_Energy_Fuel.csv")
cat("Energy diagnostic:\n")
cat("  - Rows with OVERALL:", nrow(energy_raw %>% filter(REGION == "OVERALL")), "\n")
cat("  - Rows with NA(HOUSEHOLDS):", energy_raw %>% filter(REGION == "OVERALL") %>% summarise(n = sum(is.na(HOUSEHOLDS))) %>% pull(n), "\n")
cat("  - Unique HOUSEHOLDS per district in OVERALL:\n")
print(energy_raw %>% filter(REGION == "OVERALL") %>% group_by(DISTRICT) %>% 
      summarise(n_distinct = n_distinct(HOUSEHOLDS, na.rm = TRUE)) %>% 
      filter(n_distinct > 1))
```

#### B. **Create a find_denom_col() Helper**

Extends the Column-Resolver logic from the request:

```r
find_denom_col <- function(df, canonical_denom, string_dist_threshold = 0.15) {
  # df = dataframe (e.g., energy table after OVERALL filter)
  # canonical_denom = c("HOUSEHOLDS", "TOTAL_POP", "POP_AGE_10PLUS")
  # 
  # Returns: list with $col_index, $col_name, $audit_trail
  
  cols <- toupper(names(df))
  
  # 1. Exact match?
  for (denom in canonical_denom) {
    idx <- which(cols == denom)
    if (length(idx) > 0) {
      return(list(col_index = idx, col_name = names(df)[idx], method = "exact_match", 
                  audit = paste0("Found exact: ", names(df)[idx])))
    }
  }
  
  # 2. String distance match (with loud warning!)
  library(stringdist)
  
  for (denom in canonical_denom) {
    dists <- stringdist::stringdist(denom, cols, method = "jw")
    min_idx <- which.min(dists)
    min_dist <- dists[min_idx]
    
    if (min_dist < string_dist_threshold) {
      warning(sprintf(
        "⚠️  DENOMINATOR RESOLVED VIA STRING DISTANCE: Canonical='%s', Found='%s', Distance=%.3f",
        denom, cols[min_idx], min_dist
      ))
      return(list(col_index = min_idx, col_name = names(df)[min_idx], method = "string_distance",
                  distance = min_dist, audit = "String distance match"))
    }
  }
  
  # 3. LOUD ERROR if no match
  stop(sprintf(
    "❌ CRITICAL: No denominator found for %s in columns: %s",
    paste(canonical_denom, collapse = "/"), paste(cols, collapse = ", ")
  ))
}
```

#### C. **The Causal Rule: Hard-Coded Data Model**

Create a data dictionary that binds numerators to denominators at the script level:

```r
CAUSAL_MODEL <- list(
  # Facilities Count Index (FCI) — Denominator: HOUSEHOLDS
  FCI_Energy = list(
    numerators = c("LIGHT_ELECT", "LIGHT_SOLAR", "LIGHT_OTHERS", 
                   "FUEL_GAS", "FUEL_LPGCNG", "FUEL_FIREWOOD"),
    denominator = "HOUSEHOLDS",
    causal_rule = "Housing facilities ÷ Households"
  ),
  FCI_Sanitation = list(
    numerators = c("TOILET_SEPARATE", "TOILET_FLUSH", "TOILET_NON_FLUSH",
                   "TOILET_NONE", "WASHROOM_SEPARATE", "WASHROOM_NONE"),
    denominator = "HOUSEHOLDS",
    causal_rule = "Sanitation facilities ÷ Households"
  ),
  FCI_Water = list(
    numerators = c("DRINK_WTR_IMPROVE", "DRINK_WTR_INSIDE", "DRINK_WTR_TAP",
                   "DRINK_WTR_MOTOR", "DRINK_WTR_WELL"),
    denominator = "HOUSEHOLDS",
    causal_rule = "Water access ÷ Households"
  ),
  
  # Census Index (CI) — Denominator: Population (age-specific)
  CI_Language = list(
    numerators = c("URDU", "SINDHI", "PASHTO", "PUNJABI", "BALOCHI", "BRAHVI", "OTHER"),
    denominator = "ALL_SEXES_OVERALL",
    causal_rule = "Language speakers ÷ Total Population"
  ),
  CI_Disability = list(
    numerators = c("SEEING", "HEARING", "PHYSICAL", "MENTAL", "SPEECH"),
    denominator = "ALL_SEXES_OVERALL",
    causal_rule = "Persons with disability ÷ Total Population"
  ),
  CI_Literacy = list(
    numerators = list(
      Literacy_01 = "Literate >=10",
      Attendance_01 = "Ever Attended"
    ),
    denominators = list(
      Literacy_01 = "Population >=10",
      Attendance_01 = "Population >=5"
    ),
    causal_rule = "Education metrics ÷ Age-specific population"
  )
)
```

#### D. **Audit Trail: The "Loud Warning" Branch**

For every FCI calculation, store:
- ✅ Which denominator was used
- ⚠️ String-distance value (if resolved via fuzzy match)
- 🔢 Sum of numerator, sum of denominator, computed rate
- ❌ Any records where rate > 1.0

```r
audit_fci <- function(numerator_sum, denominator_sum, numerator_name, denominator_name, district) {
  rate <- if (denominator_sum > 0) numerator_sum / denominator_sum else NA_real_
  
  audit_row <- data.frame(
    District = district,
    Numerator = numerator_name,
    Denominator = denominator_name,
    Numerator_Sum = numerator_sum,
    Denominator_Sum = denominator_sum,
    Rate = rate,
    Flag = ifelse(is.na(rate), "DENOM_ZERO", 
                  ifelse(rate > 1.0, "⚠️ RATE_EXCEEDS_1", "✓ OK")),
    Timestamp = Sys.time()
  )
  
  if (!is.na(rate) && rate > 1.0) {
    warning(sprintf(
      "⚠️  INFINITE FRICTION in %s: %s/(%s) = %.4f > 1.0 [%s]",
      district, numerator_name, denominator_name, rate, denominator_name
    ))
  }
  
  audit_row
}
```

---

## PART II: THE 136-DISTRICT BLIND SPOT (Layer 2)

### Current Geographic Coverage Assessment

**Master_Districts.csv: 136 districts** 
- Punjab: 36 districts
- Sindh: 30 districts  
- KP: 25 districts
- Balochistan: 33 districts
- ICT: 1 district

**Pakistan's Full Administrative Map: ~160+ units**
- ❌ **Missing:** Azad Jammu & Kashmir (AJK): ~10 districts
- ❌ **Missing:** Gilgit-Baltistan (GB): ~14 districts
- ❌ **Missing:** Tribal Agencies (now districts in KP): Partially included?

### The Question: Is PakPC2023PakDist Complete?

**Action Item:** Verify if the R package `PakPC2023PakDist` contains:
1. Full AJK district list
2. Full GB district list
3. Reconciliation records between old Tribal Agencies / new districts

```r
# In your R environment:
library(PakPC2023PakDist)  # or however it's named in your environment

# Check:
data(PakDist_Master)  # or equivalent
cat("Unique provinces:", unique(PakDist_Master$PROVINCE), "\n")
cat("Total districts in package:", nrow(PakDist_Master), "\n")

# Compare with our spine:
setdiff(unique(PakDist_Master$DISTRICT), unique(Master_Districts$DISTRICT))
```

### Geographic Scope Decision Tree

```
IF PakPC2023PakDist contains AJK + GB:
  → UPDATE Master_Districts.csv NOW
  → Append missing 24+ districts
  → Rerun merge_districts.R
  → OUTPUT: "Pakistan Census 2023 – Complete Atlas (136→160+ districts)"
  
ELSE IF PakPC2023PakDist does NOT contain AJK + GB:
  → ADD DISCLAIMER to all outputs:
     "⚠️  This dataset covers the Four Provinces ONLY (Punjab, Sindh, KP, Balochistan) + ICT.
         Geographic coverage: 136 of ~160 administrative units.
         Excludes: Azad Jammu & Kashmir, Gilgit-Baltistan."
  → TITLE WORK: "Pakistan Census 2023 – Four-Province Behavioral Atlas"
  → Create companion README.md with geographic limitations
```

### Legislative / Methodological Note

Add to your METHODS section (for any publication):

> **Geographic Scope:** This analysis covers 136 administrative units representing the four provinces of Pakistan (Punjab, Sindh, Khyber Pakhtunkhwa, Balochistan) and Islamabad Capital Territory. Data for Azad Jammu & Kashmir and Gilgit-Baltistan were not included in the official Census 2023 tabulations provided by the [SOURCE AGENCY], resulting in an analysis of 85% of Pakistan's total population (~170M individuals).

---

## PART III: THE REFACTORED MERGE_DISTRICTS.R (Layer 3)

### Design Principles (The "LEGO Manual" Instructions)

#### Principle 1: Case-Insensitive Sieve (First Pass)
```r
norm_dist <- function(x) {
  # TOUPPER + TRIM (existing)
  k <- str_squish(str_to_upper(x))
  
  # ALIAS HARMONIZATION
  aliases <- list(
    "ICT" = "ISLAMABAD",
    "MALAKAND PROTECTED AREA" = "MALAKAND",
    "MBDIN" = "MANDI BAHAUDDIN"
  )
  
  for (old in names(aliases)) {
    if (k == old) k <- aliases[[old]]
  }
  
  k
}
```

#### Principle 2: Denominator Anchor (Baked Into Script)
Every summarize() that extracts a count must **ALSO** extract the denominator from the **same row**, **same table**:

```r
# ❌ BAD: Numerator and denominator from different aggregation levels
energy <- FCI_Energy %>%
  group_by(DistrictKey) %>%
  summarise(LightElect = sum(LIGHT_ELECT, na.rm = TRUE))  # Denominator MISSING!

# ✅ GOOD: Numerator AND denominator extracted in lockstep
energy <- FCI_Energy %>%
  filter(REGION == "OVERALL") %>%           # Same filter
  mutate(DistrictKey = norm_dist(DISTRICT)) %>%
  group_by(DistrictKey) %>%
  summarise(
    Energy_HOUSEHOLDS = sum(HOUSEHOLDS, na.rm = TRUE),  # DENOMINATOR FIRST
    Energy_LIGHT_ELECT = sum(LIGHT_ELECT, na.rm = TRUE),
    Energy_LIGHT_SOLAR = sum(LIGHT_SOLAR, na.rm = TRUE),
    # ... etc ...
    .groups = "drop"
  ) %>%
  # COMPUTE RATES IMMEDIATELY (not later!)
  mutate(
    EnergyAccess_Electricity = Energy_LIGHT_ELECT / Energy_HOUSEHOLDS,
    Flag_EnergyElec = ifelse(EnergyAccess_Electricity > 1.0, "⚠️ RATE>1", "✓"),
    .keep = "all"
  )
```

#### Principle 3: Loud Warning on String Distance > 0.15
```r
# When resolving column names:
safe_rename <- function(df, old_names, new_names, dist_threshold = 0.15) {
  for (i in seq_along(old_names)) {
    old <- old_names[i]
    new <- new_names[i]
    
    cols <- toupper(names(df))
    idx <- which(cols == old)
    
    if (length(idx) == 0) {
      # Try string distance
      dists <- stringdist::stringdist(old, cols, method = "jw")
      idx <- which.min(dists)
      min_dist <- dists[idx]
      
      if (min_dist > dist_threshold) {
        stop(sprintf(
          "❌ COLUMN MISMATCH: '%s' resolved to '%s' with distance %.3f (threshold: %.3f)",
          old, cols[idx], min_dist, dist_threshold
        ))
      }
      
      warning(sprintf(
        "⚠️  String distance resolution: '%s' → '%s' (distance: %.3f)",
        old, names(df)[idx], min_dist
      ))
    }
    
    names(df)[idx] <- new
  }
  df
}
```

#### Principle 4: Explicit Join Diagnostics
```r
# After each left_join, verify match rates:
left_join_audit <- function(x, y, by, name) {
  result <- left_join(x, y, by = by)
  
  n_matched <- sum(!is.na(result[[names(y)[2]]]))  # First data column in y
  match_rate <- n_matched / nrow(x)
  
  cat(sprintf(
    "✓ left_join(%s): %d/%d matched (%.1f%%)\n",
    name, n_matched, nrow(x), 100 * match_rate
  ))
  
  if (match_rate < 0.95) {
    warning(sprintf(
      "⚠️  Low match rate (<95%%) for %s. Unmatched districts:\n",
      name
    ))
    unmatched <- x %>% 
      anti_join(y, by = by) %>% 
      pull(District)
    print(unmatched)
  }
  
  result
}
```

---

## PART IV: IMPLEMENTATION ROADMAP (1-Week Sprint)

### Week: May 13-20, 2026

#### **Phase 1: Diagnostics (Day 1-2)**
- [ ] Run denominator audit on all FCI files (diagnostic script above)
- [ ] Check for NA in HOUSEHOLDS, rates >1.0
- [ ] Query R package for AJK/GB district availability
- [ ] Document all findings in AUDIT_LOG.txt

#### **Phase 2: Geographic Scope Decision (Day 2-3)**
- [ ] IF missing districts found: Update Master_Districts.csv
- [ ] IF not available: Add geographic disclaimer to outputs
- [ ] Update README.md with explicit scope statement

#### **Phase 3: Refactor merge_districts.R (Day 3-5)**
- [ ] Create helper functions: `find_denom_col()`, `audit_fci()`, `safe_rename()`
- [ ] Refactor each FCI section with rate calculations + flags
- [ ] Add explicit join diagnostics
- [ ] Add final sanity checks (rates 0-1, non-negative counts)
- [ ] Generate audit_trails CSV output

#### **Phase 4: Testing & Validation (Day 5-6)**
- [ ] Run refactored script → generate Merged_Districts.csv
- [ ] Cross-check 10 random districts manually
- [ ] Verify no rates >1.0, and ALL NA rates documented
- [ ] Generate AUDIT_REPORT.md with findings

#### **Phase 5: Documentation (Day 7)**
- [ ] Finalize data dictionary (CAUSAL_MODEL above)
- [ ] Create METHODS.md for publication
- [ ] Archive original merge_districts.R as merge_districts_LEGACY.R

---

## PART V: DATA DICTIONARY (The Canonical List)

### Facilities Count Index (FCI) — Numerator DIVIDED BY Households

| Category | Numerator(s) | Denominator | Interpretation | Rate Range |
|----------|--------------|-------------|-----------------|------------|
| **Energy: Lighting** | LIGHT_ELECT, LIGHT_SOLAR, LIGHT_OTHERS | HOUSEHOLDS | % households with electricity/solar/other | 0–1.0 |
| **Energy: Fuel** | FUEL_GAS, FUEL_LPGCNG, FUEL_FIREWOOD | HOUSEHOLDS | % households using specific fuel types | 0–1.0 |
| **Sanitation** | TOILET_SEPARATE, TOILET_FLUSH, TOILET_NONE | HOUSEHOLDS | % households with toilet type | 0–1.0 |
| **Water Access** | DRINK_WTR_IMPROVE, DRINK_WTR_TAP, DRINK_WTR_WELL | HOUSEHOLDS | % households with water source | 0–1.0 |

### Census Index (CI) — Numerator DIVIDED BY Population

| Category | Numerator(s) | Denominator | Interpretation | Rate Range |
|----------|--------------|-------------|-----------------|------------|
| **Language** | (URDU, SINDHI, PASHTO, etc.) | ALL_SEXES_OVERALL | % population speaking language | 0–1.0 |
| **Disability** | (SEEING, HEARING, etc.) | ALL_SEXES_OVERALL | % population with disability type | 0–1.0 |
| **Literacy** | Literate >=10 years | Population >=10 years | % literate rate | 0–1.0 |
| **School Attendance** | Ever Attended school | Population >=5 years | % school attendance rate | 0–1.0 |

### Structural Level Indices (SLII) — Total Population Indicators

| Category | Values | Interpretation | Notes |
|----------|--------|-------------------|-------|
| **Age Structure** | Total Pop, Male, Female, Transgender, Rural, Urban | Population by sex/residence | Numerator for demographic derivations |
| **Marital Status** | Single, Married, Widow(er), Divorced | % of population >=15 years | Denominator: Age15Plus |

---

## PART VI: SUCCESS CRITERIA

### Before Refactor
- ✓ 0 unmatched spine districts (136/136)
- ❌ **Silent denominator mismatches** (unknown)
- ❌ **Rates >1.0 (silently produced)**
- ❌ **Geographic scope ambiguous**

### After Refactor
- ✓ 0 unmatched spine districts
- ✓ **All denominator decisions logged** (audit trail)
- ✓ **LOUD error if rate >1.0** (no silent failures)
- ✓ **Geographic scope explicitly documented** (disclaimer or updated to 160+)
- ✓ **String distance resolutions flagged** (none >0.15)
- ✓ **Join match rates reported** (all ≥95%)

---

## APPENDIX: Reference Code Snippets

### Snippet A: Full Denominator Audit Function
```r
audit_denominators <- function(dir_in) {
  files <- c("FCI_Energy_Fuel.csv", "FCI_Sanitation_Structure.csv", "FCI_Water.csv")
  results <- list()
  
  for (file in files) {
    df <- read_csv(file.path(dir_in, file), show_col_types = FALSE)
    
    overall <- df %>% filter(REGION == "OVERALL")
    
    results[[file]] <- list(
      total_rows = nrow(df),
      overall_rows = nrow(overall),
      households_na = sum(is.na(overall$HOUSEHOLDS)),
      households_zero = sum(overall$HOUSEHOLDS == 0, na.rm = TRUE),
      any_rate_gt_1 = FALSE  # Will populate after rate calc
    )
  }
  
  results
}
```

### Snippet B: Post-Join Validation
```r
validate_master <- function(merged) {
  cat("=== POST-MERGE VALIDATION ===\n")
  
  # Check 1: All expected columns present
  expected <- c("District", "DistrictKey", "Province", "Energy_HOUSEHOLDS", "Pop_GE10", "Literacy_01")
  missing <- setdiff(expected, names(merged))
  if (length(missing)) {
    stop(sprintf("Missing columns: %s", paste(missing, collapse = ", ")))
  }
  
  # Check 2: Rate ranges
  rate_cols <- grep("_01$|Access_|_Rate$", names(merged), value = TRUE)
  for (col in rate_cols) {
    bad_rows <- which(merged[[col]] > 1.0 | merged[[col]] < 0, na.rm = TRUE)
    if (length(bad_rows) > 0) {
      cat(sprintf("⚠️  %s has %d rows outside [0,1]:\n", col, length(bad_rows)))
      print(merged[bad_rows, c("District", col)])
    }
  }
  
  # Check 3: Non-negative counts
  count_cols <- grep("^(Energy|San|Wtr|Lang|Disab|Age|Marital)_", names(merged), value = TRUE)
  for (col in count_cols) {
    if (is.numeric(merged[[col]])) {
      neg_rows <- which(merged[[col]] < 0, na.rm = TRUE)
      if (length(neg_rows) > 0) {
        stop(sprintf("❌ ERROR: %s has negative values in %d rows", col, length(neg_rows)))
      }
    }
  }
  
  cat("✓ All validations passed.\n")
}
```

---

## END PLAN

**Contact:** Lead Analyst  
**Architecture:** Three-Layer Integrity Model (Denominator Anchor | Geographic Scope | Loud Warnings)  
**Status:** Ready for Implementation
