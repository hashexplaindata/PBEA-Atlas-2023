# Pakistan Census 2023 — DataCard (Quick Reference)

**Print this page and keep it next to your desk.**

---

## DATASET AT A GLANCE

| Attribute | Value |
|-----------|-------|
| **Districts** | 136 (4 provinces + ICT) |
| **Population Covered** | ~170M (~85% of Pakistan) |
| **Missing:** | AJK (⚠️), GB (⚠️) |
| **Unit of Analysis** | District |
| **Year** | Census 2023 |
| **Tables Merged** | 8 (3 FCI + 3 CI + 2 SLII) |

---

## THE THREE-LAYER INTEGRITY MODEL

```
┌─────────────────────────────────────────────────────┐
│ LAYER 1: DENOMINATOR ANCHOR                         │
│ Every numerator paired with denominator             │
│ • FCI (Energy/Water/Sanitation): ÷ HOUSEHOLDS       │
│ • CI (Language/Disability): ÷ POPULATION            │
│ • CI (Literacy/Attendance): ÷ AGE-SPECIFIC POP      │
│ VALIDATION: All rates ∈ [0, 1.0]                   │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ LAYER 2: GEOGRAPHIC SCOPE DECLARATION               │
│ Explicit: "Four-Province Behavioral Atlas"          │
│ EXCLUDES: AJK, GB                                   │
│ STATUS: Document clearly in methods section         │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ LAYER 3: LOUD WARNINGS                              │
│ String distance >0.15? → STOP (no silent failures)  │
│ Rate >1.0? → FLAG (document anomaly)                │
│ Join match <95%? → WARN (see unmatched list)        │
└─────────────────────────────────────────────────────┘
```

---

## CAUSAL MODEL: NUMERATOR ÷ DENOMINATOR

### **Facilities Count Index (FCI)** — All ÷ HOUSEHOLDS

```
ENERGY LIGHTING:
  Energy_Access_Electricity     = LIGHT_ELECT / HOUSEHOLDS         [0,1]
  Energy_Access_Solar           = LIGHT_SOLAR / HOUSEHOLDS         [0,1]

ENERGY FUEL:
  Energy_Fuel_Gas               = FUEL_GAS / HOUSEHOLDS            [0,1]
  Energy_Fuel_LPGCNG            = FUEL_LPGCNG / HOUSEHOLDS         [0,1]
  Energy_Fuel_Firewood          = FUEL_FIREWOOD / HOUSEHOLDS       [0,1]

SANITATION:
  Sanitation_Toilet_Separate    = TOILET_SEPARATE / HOUSEHOLDS     [0,1]
  Sanitation_Toilet_Flush       = TOILET_FLUSH / HOUSEHOLDS        [0,1]
  Sanitation_Washroom_Separate  = WASHROOM_SEPARATE / HOUSEHOLDS   [0,1]

WATER:
  Water_Access_Improved         = DRINK_WTR_IMPROVE / HOUSEHOLDS   [0,1]
  Water_Source_Tap              = DRINK_WTR_TAP / HOUSEHOLDS       [0,1]
```

### **Census Index (CI)** — All ÷ POPULATION (or age-specific)

```
LANGUAGE:
  Lang_Urdu                     = (Urdu speakers) / POPULATION      [0,1]
  Lang_Punjabi, Sindhi, Pashto, Balochi, Brahvi, OTHER

DISABILITY:
  Disab_Seeing                  = (See difficulty) / POPULATION     [0,1]
  Disab_Hearing, Physical, Mental, Speech

LITERACY:
  Literacy_Rate                 = (Literate ≥10) / (Pop ≥10)        [0,1]

SCHOOL ATTENDANCE:
  Attendance_Rate               = (Ever attended ≥5) / (Pop ≥5)     [0,1]
```

### **Structural Level Indices (SLII)** — Absolute Counts (Not Rates)

```
AGE STRUCTURE:
  Age_TotalPop                  = Total population (count)
  Age_Male, Age_Female, Age_Trans, Age_Rural, Age_Urban

MARITAL STATUS:
  Marital_Single                = (Pop ≥15, never married) / (Pop ≥15)  [0,1]
  Marital_Married, Widow, Divorced
```

---

## KEY COLUMNS IN OUTPUT

| Purpose | Column Pattern | Examples |
|---------|---------------|----------|
| **Denominators** | `*_HOUSEHOLDS` or raw counts | `Energy_HOUSEHOLDS`, `Age_TotalPop` |
| **Numerators (Counts)** | `*_[CATEGORY]` | `Energy_LIGHT_ELECT`, `Lang_URDU` |
| **Computed Rates** | `*_Access_*` or `*_01` | `Energy_Access_Electricity`, `Literacy_01` |
| **Quality Flags** | `*_Flag` | `Energy_Flag_Elec`, `Sanitation_Flag` |

---

## DATA QUALITY FLAGS (What They Mean)

| Flag | Meaning | Action |
|------|---------|--------|
| **✓** | Rate valid (0 ≤ rate ≤ 1) | Use normally |
| **⚠️ RATE>1** | Numerator > denominator (impossible) | Investigate; likely overlapping categories |
| **DENOM_ZERO** | Denominator = 0 (division by zero) | Set rate = NA; exclude from analysis |
| **UNMATCHED** | District in spine but no data | Check raw .csv files for typos |

---

## COMMON ANALYSIS QUERIES

### **Q1: Which districts have lowest electricity access?**
```r
merged %>%
  arrange(Energy_Access_Electricity) %>%
  head(10) %>%
  select(District, Energy_HOUSEHOLDS, Energy_LIGHT_ELECT, Energy_Access_Electricity)
```

### **Q2: Compare literacy by province**
```r
merged %>%
  group_by(Province) %>%
  summarise(
    Avg_Literacy = mean(Literacy_01, na.rm = TRUE),
    Districts = n()
  ) %>%
  arrange(desc(Avg_Literacy))
```

### **Q3: Districts with data anomalies (rates >1)?**
```r
merged %>%
  select(District, contains("_Flag")) %>%
  filter_if(is.character, any_vars(. == "⚠️ RATE>1"))
```

### **Q4: Language diversity in a district**
```r
district_langs <- merged %>%
  filter(District == "Karachi Central") %>%
  select(starts_with("Lang_")) %>%
  pivot_longer(everything()) %>%
  arrange(desc(value)) %>%
  head(5)
print(district_langs)
```

---

## FILE STRUCTURE

```
Census 2023/
├── data/
│   └── Merged_Districts_Census2023.csv        [MAIN OUTPUT]
├── documentation/
│   ├── METHODS_AND_SCOPE.md                   [Publication-ready]
│   ├── RESEARCH_PLAN_2023.md                  [Strategic plan]
│   ├── DENOMINATOR_AUDIT_LOG.csv              [QA proof]
│   └── Merge_Audit_Trail.csv                  [Rate validation]
├── datasets_Census23_CranR/
│   ├── [8 original .csv files]
│   ├── PHASE1_DENOMINATOR_AUDIT.R
│   └── merge_districts_REFACTORED.R
│
└── [This file: DATACARD.md]
```

---

## BEFORE YOU PUBLISH: CHECKLIST

- [ ] Ead METHODS_AND_SCOPE.md → Verify geographic scope statement is clear
- [ ] Check for rates >1.0 in output → Document if found
- [ ] Verify "Four-Province Atlas" appears in title/abstract
- [ ] Note AJK/GB exclusion in methods section
- [ ] Cite Census 2023 official source: Pakistan Bureau of Statistics
- [ ] Include link to: Merge_Audit_Trail.csv (if publishing data)
- [ ] Archive legacy files (merge_districts.R → merge_districts_LEGACY.R)

---

## INTERPRETATION TIPS

### ✅ DO:
- Report rates as proportions (0-1) or percentages (0-100%)
- Group by Province for higher-level analysis
- Use confidence intervals for small counts
- Cross-check with raw .csv if specific values seem large/small
- Document any outliers found

### ❌ DON'T:
- Compare electricity access rates without checking denominators
- Mix FCI rates (÷ households) with CI rates (÷ population)
- Analyze AJK/GB data (not in this dataset)
- Assume regions are independent (may be nested geographies)
- Treat "Ever Attended" as "Currently Enrolled"

---

## TROUBLESHOOTING

**"I found a rate >1.0. What does it mean?"**
→ Likely overlapping Census categories. Example: FCI asks households "Do you have electricity? Do you have solar?" A household with both solar AND grid connection = counted twice as numerator, once as denominator = rate 1.5. Report as flag; exclude from aggregate analyses.

**"Can I reaggregate to urban/rural?"**
→ Raw .csv files have REGION={OVERALL, RURAL, URBAN}. Re-read FCI files and group by REGION before merging to master spine. CI/SLII already at district level.

**"Why isn't district X in my output?"**
→ Check: (1) Is it in Master_Districts.csv? (2) Check spelling/aliases (ICT→ISLAMABAD). (3) If not there, it's not in Census 2023 official spine.

**"What's the denominator for Marital status?"**
→ Marital columns are proportions of Population ≥15 years. Sum of all marital categories should ≈1.0 per district.

---

## CONTACT QUICK REFERENCE

| Question About | Contact |
|---|---|
| Data integration / refactored merge script | [Your Email] |
| Census 2023 definitions | PBS (https://www.pbs.gov.pk/) |
| District boundaries / AJK-GB status | NADRA |
| Methodology/Statistics | [Your Advisor/Institution] |

---

## VERSION HISTORY

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-05-11 | Initial: Three-Layer Integrity Model implemented |
| 1.1 | [TBD] | [Future updates] |

---

## LAST UPDATED
May 11, 2026 — 03:00 PM

**Status:** ✅ READY FOR USE

---

**Questions?** Consult RESEARCH_PLAN_2023.md (comprehensive) or METHODS_AND_SCOPE.md (publication-ready).

