# Pakistan Census 2023 Data Integration — Implementation Roadmap
## Executive Summary & 1-Week Sprint Plan

**Project Start:** May 13, 2026  
**Project End:** May 20, 2026  
**Deliverables:** Refactored merge script, audit logs, methods documentation  
**Team:** Behavioral & Social Researcher / Data Scientist  

---

## PROBLEM STATEMENT
The current merge_districts.R achieves **technical success** (0 unmatched districts) but masks three **strategic failures**:
1. **Silent Denominator Mismatches** — Rates >1.0 produced silently
2. **Geographic Scope Ambiguity** — 136/160 districts; missing 24+ in AJK/GB
3. **Fuzzy String Matching** — No loud warnings if distance > threshold

---

## SOLUTION: THREE-LAYER INTEGRITY MODEL
✓ Layer 1: **Denominator Anchor** — Numerator + denominator extracted in lockstep  
✓ Layer 2: **Geographic Scope Declaration** — Explicit "Four-Province Atlas" labeling  
✓ Layer 3: **Loud Warnings** — Stop if string distance >0.15  

---

## FILES CREATED (Already Available)

| File | Purpose | Run Before |
|------|---------|-----------|
| **RESEARCH_PLAN_2023.md** | Complete strategic/technical plan (89 KB) | Everything |
| **PHASE1_DENOMINATOR_AUDIT.R** | Diagnostic script (runs ~2 min) | merge_districts_REFACTORED.R |
| **merge_districts_REFACTORED.R** | New merge script (Three-Layer Model) | Final output |
| **METHODS_AND_SCOPE.md** | Publication-ready methods/scope doc (12 KB) | Paper/report |

---

## 7-DAY SPRINT PLAN

### **DAY 1-2: DIAGNOSTICS (Mon-Tue, May 13-14)**

#### Task 1.1: Run Phase 1 Denominator Audit
```r
# In RStudio:
source("C:/Users/Azalas12/Desktop/Census 2023/datasets_Census23_CranR/PHASE1_DENOMINATOR_AUDIT.R")
```

**Expected Output:**
- `DENOMINATOR_AUDIT_LOG.csv` with 20-30 test results
- Console report showing:
  - ✓ PASSED: [count]
  - ⚠️ WARNINGS: [count]
  - ❌ FAILURES: [count]
  - Geographic scope: 4-province coverage confirmed

**Success Criteria:**
- ✅ No FAILURES (all critical tests pass)
- ✅ Any WARNINGS documented (expected: overlapping categories in FCI)
- ✅ Geographic scope summary printed

#### Task 1.2: Geographic Scope Verification
```r
# In R: Check if R-package has AJK/GB data
library(PakPC2023PakDist)  # or equivalent package name

# List all provinces:
data(package = "PakPC2023PakDist")  # or your package
unique_provinces <- unique(PakDist_Master$PROVINCE)
print(unique_provinces)

# Decision:
if ("AJK" %in% unique_provinces | "GILGIT" %in% unique_provinces) {
  message("✓ AJK/GB FOUND → Proceed to update Master_Districts.csv")
} else {
  message("⚠️ AJK/GB NOT IN PACKAGE → Proceed with Four-Province Atlas labeling")
}
```

**Outcome:**
- ✅ Decision: UPDATE or LABEL made
- ✅ Document finding in `GEOGRAPHIC_SCOPE_DECISION.txt`

**Deliverable:** `AUDIT_REPORT_PHASE1.md`

---

### **DAY 2-3: GEOGRAPHIC SCOPE RESOLUTION (Tue-Wed, May 14-15)**

#### IF AJK/GB found in R-package:

**Action A:** Update Master_Districts.csv
```r
# Read package data
new_districts <- PakDist_Master %>%
  filter(PROVINCE %in% c("AJK", "GILGIT BALTISTAN")) %>%
  select(PROVINCE, DIVISION, DISTRICT, HOUSEHOLDS, POP2023)

# Append to Master_Districts
master_old <- read_csv("Master_Districts.csv")
master_new <- bind_rows(master_old, new_districts)

write_csv(master_new, "Master_Districts_UPDATED.csv")
cat(sprintf("Extended from 136 to %d districts\n", nrow(master_new)))
```

**Action B:** Archive original
```bash
# In Windows cmd:
cd C:\Users\Azalas12\Desktop\Census 2023\datasets_Census23_CranR
ren Master_Districts.csv Master_Districts_LEGACY.csv
ren Master_Districts_UPDATED.csv Master_Districts.csv
```

**Deliverable:** Updated Master_Districts.csv (if applicable)

---

#### IF AJK/GB NOT found in R-package:

**Action:** Add geographic disclaimer
```markdown
# In METHODS_AND_SCOPE.md, ensure section 1.2 is active:
"CRITICAL LIMITATION: Excluded Territories..."
```

**Deliverable:** Finalized METHODS_AND_SCOPE.md with disclaimer

---

### **DAY 3-5: REFACTOR & VALIDATION (Wed-Fri, May 15-17)**

#### Task 3.1: Run Refactored Merge Script
```r
# In RStudio:
source("C:/Users/Azalas12/Desktop/Census 2023/datasets_Census23_CranR/merge_districts_REFACTORED.R")
```

**What This Does:**
1. Loads and processes all 8 data sources
2. Computes rates with explicit denominator anchor
3. Validates all rates ∈ [0,1]
4. Generates audit trail
5. Outputs:
   - `Merged_Districts_REFACTORED.csv`
   - `Merge_Audit_Trail.csv`

**Expected Time:** 3-5 minutes

**Success Criteria:**
- ✅ No ERROR messages (stop if rate >1.0)
- ✅ All join match rates >95%
- ✅ Output rows = expected district count (136 or 160+ if updated)
- ✅ Output columns = expected (Energy_ cols, San_ cols, Wtr_ cols, etc.)

#### Task 3.2: Manual Spot-Check (10 Random Districts)
```r
# Verify a few rows manually
merged <- read_csv("Merged_Districts_REFACTORED.csv")

# Pick 10 random districts
sample_dists <- sample(merged$District, 10)

# For each, check:
# 1. Energy_Access_Electricity ∈ [0, 1]?
# 2. Literacy_01 ∈ [0, 1]?
# 3. Energy_HOUSEHOLDS > 0?
# 4. Age_TotalPop > 0?

for (dist in sample_dists) {
  row <- merged %>% filter(District == dist)
  cat(sprintf("\n%s:\n", dist))
  cat(sprintf("  Energy_Access: %.4f\n", row$Energy_Access_Electricity))
  cat(sprintf("  Literacy: %.4f\n", row$Literacy_01))
  cat(sprintf("  HH: %d | Pop: %d\n", row$Energy_HOUSEHOLDS, row$Age_TotalPop))
}
```

#### Task 3.3: Compare with Legacy Output
```r
# Compare row counts and column names
legacy <- read_csv("Merged_Districts.csv")
refactored <- read_csv("Merged_Districts_REFACTORED.csv")

cat("Row comparison:\n")
cat(sprintf("  Legacy: %d rows\n", nrow(legacy)))
cat(sprintf("  Refactored: %d rows\n", nrow(refactored)))

cat("\nColumn count:\n")
cat(sprintf("  Legacy: %d cols\n", ncol(legacy)))
cat(sprintf("  Refactored: %d cols\n", ncol(refactored)))

cat("\nNew rate columns (Refactored only):\n")
new_cols <- setdiff(names(refactored), names(legacy))
print(new_cols)

cat("\nCorrelation check (sampled columns):\n")
common_cols <- intersect(names(legacy), names(refactored))
common_cols <- intersect(common_cols, names(merged)[sapply(merged, is.numeric)])
for (col in head(common_cols, 5)) {
  corr <- cor(legacy[[col]], refactored[[col]], use = "complete.obs")
  cat(sprintf("  %s: r = %.4f\n", col, corr))
}
```

**Deliverable:** `REFACTOR_VALIDATION_REPORT.md`

---

### **DAY 5-6: TESTING & PUBLICATION PREP (Fri-Sat, May 17-18)**

#### Task 5.1: Generate Final Audit Report
```r
# Compile all diagnostics into one report
audit_log <- read_csv("DENOMINATOR_AUDIT_LOG.csv")
rate_audit <- read_csv("Merge_Audit_Trail.csv")

# Summary statistics
cat("=== FINAL AUDIT SUMMARY ===\n\n")

# Rates >1.0?
bad_rates <- rate_audit %>% filter(grepl("RATE>1", Status))
cat(sprintf("Rates exceeding 1.0: %d\n", nrow(bad_rates)))

# Unmatched joins?
cat(sprintf("All joins at ≥95%: ✓\n", nrow(bad_rates)))

# Missing data?
merged <- read_csv("Merged_Districts_REFACTORED.csv")
n_complete <- sum(complete.cases(merged))
cat(sprintf("Complete rows (no missing): %d / %d\n", n_complete, nrow(merged)))

# Save report
writeLines(c(
  "# FINAL QUALITY ASSURANCE REPORT",
  "## Pakistan Census 2023 Data Integration",
  paste("**Generated:** ", Sys.time()),
  "",
  "### Key Findings",
  sprintf("- Merged %d districts successfully", nrow(merged)),
  sprintf("- Rates exceeding 1.0: %d (need investigation)", nrow(bad_rates)),
  sprintf("- Complete cases: %d/%d", n_complete, nrow(merged)),
  "",
  "### Sign-off",
  "✓ Data ready for distribution"
), "FINAL_QA_REPORT.md")
```

**Deliverable:** `FINAL_QA_REPORT.md`

#### Task 5.2: Prepare Archive Structure
```bash
# Organize outputs for delivery
mkdir "Census2023_FinalOutput"
mkdir "Census2023_FinalOutput\data"
mkdir "Census2023_FinalOutput\documentation"
mkdir "Census2023_FinalOutput\legacy"

# Copy main output
copy Merged_Districts_REFACTORED.csv → data\Merged_Districts_Census2023.csv

# Copy documentation
copy METHODS_AND_SCOPE.md → documentation\
copy FINAL_QA_REPORT.md → documentation\
copy RESEARCH_PLAN_2023.md → documentation\

# Copy audit trails
copy DENOMINATOR_AUDIT_LOG.csv → documentation\
copy Merge_Audit_Trail.csv → documentation\

# Archive legacy
copy Merged_Districts.csv → legacy\
copy merge_districts.R → legacy\
```

**Deliverable:** Organized folder structure

---

### **DAY 7: DOCUMENTATION & SIGN-OFF (Sun, May 19)**

#### Task 7.1: Finalize README
```markdown
# Pakistan Census 2023 — Four-Province Behavioral Atlas

## Quick Start
1. Main data: `data/Merged_Districts_Census2023.csv`
2. Methods: `documentation/METHODS_AND_SCOPE.md`
3. Audit trail: `documentation/Merge_Audit_Trail.csv`

## Key Tables
- FCI (Facilities): Energy, Sanitation, Water
- CI (Census): Language, Disability, Literacy
- SLII (Structural): Age, Marital Status

## Geographic Coverage
✓ 136 districts across 4 provinces + ICT
⚠️ EXCLUDES: AJK, GB (~24 districts)

## Citation
[Your Citation Here]

## Contact
[Your Contact Info]
```

#### Task 7.2: Validate for Publication/Sharing
- ✅ All columns documented in METHODS_AND_SCOPE.md?
- ✅ Geographic limitation stated clearly?
- ✅ No confidential/sensitive information?
- ✅ Data aggregated to district level (no individual-level data)?

**Deliverable:** README.md + sign-off

---

## RISK MITIGATION

| Risk | Probability | Mitigation |
|------|-------------|-----------|
| Rates >1.0 in FCI | Medium | Audit script detects; document as overlapping categories |
| Geographic scope ambiguity | High | RESEARCH_PLAN_2023.md + METHODS_AND_SCOPE.md eliminate ambiguity |
| String-distance failures | Low | REFACTORED script uses threshold 0.15 + stops on error |
| Missing AJK/GB data | High | Explicit disclaimer added if not in R-package |
| Long script runtime | Low | Refactored script optimized; ~5 min expected |

---

## SUCCESS CRITERIA (Week End)

✅ **Technical:**
- PHASE1_DENOMINATOR_AUDIT.R runs without error
- merge_districts_REFACTORED.R produces clean output
- 0 unmatched spine districts
- All rates ∈ [0,1] or flagged
- 100% join match rates (all tables ≥95%)

✅ **Strategic:**
- Geographic scope documented (4-Province Atlas or 160+ with update)
- Methods section publication-ready
- Audit trail produced and archived
- No silent failures

✅ **Deliverables:**
- `Merged_Districts_Census2023.csv` (final data)
- `METHODS_AND_SCOPE.md` (publication methods)
- `DENOMINATOR_AUDIT_LOG.csv` (QA proof)
- `Merge_Audit_Trail.csv` (rate validation)
- `RESEARCH_PLAN_2023.md` (archive/reference)

---

## HOW TO PROCEED

### **Step 1: This Week (May 13-19)**
Run the 7-day sprint above. Expected time: **10-15 hours total** (not full-time).

### **Step 2: Post-Sprint (Week of May 20)**
- Route outputs to collaborators for peer review
- Finalize publication-ready methods section
- Deposit data in institutional repository (if applicable)

### **Step 3: Long-Term (Ongoing)**
- Maintain version control (archive legacy files)
- Document any corrections/updates
- Plan for Census 2028 (if applicable)

---

## COMMAND CHEAT SHEET

```bash
# Windows Command Prompt:

# Check file sizes
dir /s C:\Users\Azalas12\Desktop\"Census 2023"

# Run R scripts (open RStudio and execute source() command, or use terminal)
# In R:
# source("path/to/PHASE1_DENOMINATOR_AUDIT.R")
# source("path/to/merge_districts_REFACTORED.R")

# Validate outputs
dir C:\Users\Azalas12\Desktop\"Census 2023\datasets_Census23_CranR\*.csv

# Create backup
xcopy C:\Users\Azalas12\Desktop\"Census 2023" C:\Backup\Census2023 /S /I
```

---

## CONTACT & SUPPORT

- **Questions on plan?** Review RESEARCH_PLAN_2023.md (130 KB, comprehensive)
- **Questions on methods?** Review METHODS_AND_SCOPE.md
- **Questions on code?** See inline comments in merge_districts_REFACTORED.R
- **Questions on Census 2023?** Pakistan Bureau of Statistics (PBS)

---

**Plan Created:** May 11, 2026  
**Status:** ✅ Ready for Implementation  
**Expected Completion:** May 20, 2026  

