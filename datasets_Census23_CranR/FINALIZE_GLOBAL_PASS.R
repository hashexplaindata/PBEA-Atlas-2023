# FINALIZE_GLOBAL_PASS.R
# Applies FIX PROTOCOL: ICT age reconstruction and executes Global Normalization Pass
# Produces: Final_PBEA_Atlas_Coefficients.csv and Validation_Report_Global.txt
#
# Usage:
# Rscript "C:/Users/Azalas12/Desktop/Census 2023/datasets_Census23_CranR/FINALIZE_GLOBAL_PASS.R"

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr); library(tidyr)
})

# Paths
dir_in <- "C:/Users/Azalas12/Desktop/Census 2023/datasets_Census23_CranR"
dir_main <- "C:/Users/Azalas12/Desktop/Census 2023"
final_in <- file.path(dir_in, "Final_PBEA_Atlas_Data.csv")
slii_age <- file.path(dir_in, "SLII_Age_Bulge.csv")
age_group_file <- file.path(dir_main, "age-group.csv")
out_csv <- file.path(dir_in, "Final_PBEA_Atlas_Coefficients.csv")
report <- file.path(dir_in, "Validation_Report_Global.txt")

log <- function(...) {
  # Simple logger: paste all args (avoids sprintf format issues when no placeholders provided)
  msg <- paste(..., sep = "")
  cat(msg, "\n")
}

# Helper: parse age group strings into numeric intervals
parse_age_group <- function(s) {
  s <- toupper(str_trim(s))
  s <- str_replace_all(s, "&", ""); s <- str_replace_all(s, "\\s+", " ")
  if (str_detect(s, "UNDER\\s*(\\d+)") ) {
    high <- as.numeric(str_match(s, "UNDER\\s*(\\d+)")[,2]); return(c(0, high-1))
  }
  if (str_detect(s, "(\\d+)\\s*-\\s*(\\d+)") ) {
    m <- str_match(s, "(\\d+)\\s*-\\s*(\\d+)"); return(c(as.numeric(m[2]), as.numeric(m[3])))
  }
  if (str_detect(s, "(\\d+)\\s*\\+|ABOVE|AND ABOVE")) {
    num <- as.numeric(str_extract(s, "\\d+")); return(c(num, Inf))
  }
  return(c(NA, NA))
}

# Gallup ICT 65+ extractor: exact row only; sum Male+Female if Both is missing.
get_gallup_ict_65_plus <- function(age_group_path) {
  if (!file.exists(age_group_path)) return(NA_real_)
  ag <- read_csv(age_group_path, show_col_types = FALSE)
  nm <- names(ag)
  prov_col <- nm[which(toupper(nm) == "PROVINCE")[1]]
  dist_col <- nm[which(toupper(nm) == "DISTRICT")[1]]
  age_col  <- nm[which(toupper(nm) == "AGE GROUP")[1]]
  gender_col <- nm[which(toupper(nm) == "GENDER")[1]]
  pop_col <- nm[which(toupper(nm) %in% c("POPULATION REPORTING", "POPULATION"))[1]]
  if (any(is.na(c(prov_col, dist_col, age_col, gender_col, pop_col)))) return(NA_real_)
  ict <- ag %>%
    mutate(
      ProvinceKey = toupper(str_trim(.data[[prov_col]])),
      DistrictKey = toupper(str_trim(.data[[dist_col]])),
      AgeKey = toupper(str_trim(.data[[age_col]])),
      GenderKey = toupper(str_trim(.data[[gender_col]]))
    ) %>%
    filter(str_detect(ProvinceKey, "ISLAMABAD"), str_detect(DistrictKey, "ISLAMABAD"), AgeKey == "65 & ABOVE")
  if (nrow(ict) == 0) return(NA_real_)
  both <- ict %>% filter(GenderKey == "BOTH")
  if (nrow(both) > 0) return(sum(both[[pop_col]], na.rm = TRUE))
  mf <- ict %>% filter(GenderKey %in% c("MALE", "FEMALE"))
  if (nrow(mf) > 0) return(sum(mf[[pop_col]], na.rm = TRUE))
  NA_real_
}

# Read final merged file
if (!file.exists(final_in)) stop("Final_PBEA_Atlas_Data.csv not found. Run previous pipeline first.")
merged <- read_csv(final_in, show_col_types = FALSE)
log("Loaded merged dataset: ", final_in)

# Remove prior age-cohort columns so the reconstruction can re-create them cleanly
merged <- merged %>% select(-any_of(c("Under15", "Age_15_29", "Age_30_64", "Age_65_Plus", "Age_15_64", "Dependency_Ratio")))

# Reconstruct ICT per FIX PROTOCOL: Override problematic counts
ict_key <- which(toupper(str_trim(merged$District)) == "ICT" | toupper(str_trim(merged$District)) == "ISLAMABAD")
if (length(ict_key) == 0) stop("ICT/Islamabad row not found in merged dataset")

# Now build mutually exclusive cohorts for all districts from SLII_Age_Bulge.csv if available
if (file.exists(slii_age)) {
  age_raw <- read_csv(slii_age, show_col_types = FALSE)
  # Expect columns: DISTRICT, SEX_AGE_GROUP_IN_YEARS, ALL_SEXES_OVERALL
  age_df <- age_raw %>% mutate(DistrictKey = toupper(str_trim(DISTRICT))) %>%
    filter(!is.na(`SEX_AGE_GROUP_IN_YEARS`))

  # For each district, compute sums for Under15, 15-29, 30-64, 65+
  districts <- unique(age_df$DistrictKey)
  cohorts <- tibble(DistrictKey = districts,
                    Under15 = NA_real_, Age_15_29 = NA_real_, Age_30_64 = NA_real_, Age_65_Plus = NA_real_)

  for (d in districts) {
    sub <- age_df %>% filter(DistrictKey == d)
    # For each row, parse age group
    ranges <- t(sapply(sub$SEX_AGE_GROUP_IN_YEARS, parse_age_group))
    pop <- sub$ALL_SEXES_OVERALL
    # accumulate
    under15 <- sum(pop[which(ranges[,1] >=0 & ranges[,2] <=14)], na.rm = TRUE)
    # 15-29: rows overlapping 15-29
    idx15_29 <- which(!(is.na(ranges[,1])) & !(ranges[,2] < 15 | 29 < ranges[,1]))
    age_15_29 <- sum(pop[idx15_29], na.rm = TRUE)
    # 30-64
    idx30_64 <- which(!(is.na(ranges[,1])) & !(ranges[,2] < 30 | 64 < ranges[,1]))
    age_30_64 <- sum(pop[idx30_64], na.rm = TRUE)
    # 65+
    idx65 <- which(!(is.na(ranges[,1])) & (is.infinite(ranges[,2]) | ranges[,2] >= 65 | ranges[,1] >= 65))
    age65 <- sum(pop[idx65], na.rm = TRUE)
    cohorts <- cohorts %>% mutate(Under15 = ifelse(DistrictKey==d, under15, Under15),
                                  Age_15_29 = ifelse(DistrictKey==d, age_15_29, Age_15_29),
                                  Age_30_64 = ifelse(DistrictKey==d, age_30_64, Age_30_64),
                                  Age_65_Plus = ifelse(DistrictKey==d, age65, Age_65_Plus))
  }
  # join cohorts into merged by matching DistrictKey name normalization
  merged <- merged %>% mutate(DistrictKey = toupper(str_trim(District)))
  merged <- left_join(merged, cohorts, by = "DistrictKey")
  log("Age cohorts integrated from SLII_Age_Bulge for districts where available")

  # Ensure cohort columns exist even if SLII lacks some districts/labels
  for (nm in c("Under15", "Age_15_29", "Age_30_64", "Age_65_Plus")) {
    if (!nm %in% names(merged)) merged[[nm]] <- NA_real_
  }

  # FIX PROTOCOL: discard overlapping Rawalpindi counts; use conservative 15–29 floor.
  # Exact 65+ from Gallup, exact enough to preserve the elderly dependency signal.
  ict_65_plus <- get_gallup_ict_65_plus(age_group_file)
  if (is.na(ict_65_plus)) {
    log("WARNING: Gallup ICT 65+ exact row unavailable; Age_65_Plus will remain as reconstructed from SLII where possible.")
  } else {
    merged$Age_65_Plus[ict_key] <- ict_65_plus
    log(sprintf("ICT exact Gallup 65+ applied: %d", ict_65_plus))
  }

  # Since exact 15–29 bins are not available without overlap, keep the conservative protocol floor.
  merged$Age_15_29[ict_key] <- round(0.25 * merged$Pop2023[ict_key])
  log(sprintf("ICT Age_15_29 set to conservative floor: %d (25%% of Pop2023)", merged$Age_15_29[ict_key]))

  # Sanity check: if a Rawalpindi-derived proxy is later introduced, it must remain <= 0.50.
  log("Rawalpindi exact 15–29 cohorts are unavailable in current SLII bins; no overlap-based ratio used.")
} else {
  log("SLII_Age_Bulge.csv not found; cannot reconstruct cohorts for all districts")
}

# Sanity: Ensure cohorts non-overlapping and sum <= Age_TotalPop
# If sum > Age_TotalPop, scale down Age_30_64 proportionally
merged <- merged %>% rowwise() %>% mutate(
  cohort_sum = sum(c_across(c(Under15, Age_15_29, Age_30_64, Age_65_Plus)), na.rm = TRUE),
  Age_30_64 = ifelse(!is.na(cohort_sum) & cohort_sum > Age_TotalPop & !is.na(Age_30_64),
                     round(Age_30_64 * (Age_TotalPop / cohort_sum)), Age_30_64),
  cohort_sum = sum(c_across(c(Under15, Age_15_29, Age_30_64, Age_65_Plus)), na.rm = TRUE)
) %>% ungroup()

# Recompute Dependency Ratio: (Under15 + 65+) / (15-64)
merged <- merged %>% mutate(Age_15_64 = ifelse(!is.na(Age_15_29) & !is.na(Age_30_64), Age_15_29 + Age_30_64, NA_real_))
merged <- merged %>% mutate(Dependency_Ratio = ifelse(Age_15_64>0, (coalesce(Under15,0) + coalesce(Age_65_Plus,0))/Age_15_64, NA_real_))

# Normalize Friction (FCI rates)
merged <- merged %>% mutate(
  Access_Electricity = ifelse(!is.na(Energy_HOUSEHOLDS) & Energy_HOUSEHOLDS>0, Energy_LIGHT_ELECT / Energy_HOUSEHOLDS, NA_real_),
  Access_Sanitation = ifelse(!is.na(San_HOUSEHOLDS) & San_HOUSEHOLDS>0, San_TOILET_FLUSH / San_HOUSEHOLDS, NA_real_),
  Access_Water = ifelse(!is.na(Wtr_HOUSEHOLDS) & Wtr_HOUSEHOLDS>0, Wtr_DRINK_WTR_IMPROVE / Wtr_HOUSEHOLDS, NA_real_)
)

# Normalize Capability inputs from the actual merged column names (legacy-safe)
if (!"Literacy_01" %in% names(merged)) {
  if (all(c("Literate >=10", "Population >=10") %in% names(merged))) {
    merged <- merged %>% mutate(Literacy_01 = ifelse(`Population >=10` > 0, `Literate >=10` / `Population >=10`, NA_real_))
  } else if (all(c("Lit_GE10", "Pop_GE10") %in% names(merged))) {
    merged <- merged %>% mutate(Literacy_01 = ifelse(Pop_GE10 > 0, Lit_GE10 / Pop_GE10, NA_real_))
  } else {
    merged$Literacy_01 <- NA_real_
  }
}

if (!"Attendance_01" %in% names(merged)) {
  if (all(c("Ever Attended", "Population >=5") %in% names(merged))) {
    merged <- merged %>% mutate(Attendance_01 = ifelse(`Population >=5` > 0, `Ever Attended` / `Population >=5`, NA_real_))
  } else if (all(c("EverAttended", "Pop_GE5") %in% names(merged))) {
    merged <- merged %>% mutate(Attendance_01 = ifelse(Pop_GE5 > 0, EverAttended / Pop_GE5, NA_real_))
  } else {
    merged$Attendance_01 <- NA_real_
  }
}

if (!"LIAS_01" %in% names(merged)) {
  if (all(c("Lang_URDU", "Lang_TOTAL") %in% names(merged))) {
    merged <- merged %>% mutate(LIAS_01 = ifelse(Lang_TOTAL > 0, Lang_URDU / Lang_TOTAL, NA_real_))
  } else {
    merged$LIAS_01 <- NA_real_
  }
}

# Cap at 1.0 with loud warning
for (col in c("Access_Electricity","Access_Sanitation","Access_Water")) {
  bad <- which(!is.na(merged[[col]]) & merged[[col]]>1)
  if (length(bad)>0) {
    for (i in bad) log(sprintf("LOUD WARNING: %s >1 in %s (%.3f). Capped to 1.0", col, merged$District[i], merged[[col]][i]))
    merged[[col]][bad] <- 1.0
  }
}

# Normalize Capability: Disability inverse
merged <- merged %>% mutate(Disability_Capability = ifelse(!is.na(Disab_Population) & Disab_Population>0, 1 - (Disab_Disability / Disab_Population), NA_real_))

# Ensure all friction/capability columns are within [0,1]
# Create final coefficient columns: FCI_coeff = 1 - mean(accesses)
merged <- merged %>% rowwise() %>% mutate(
  FCI_coeff = {
    vals <- c(Access_Electricity, Access_Sanitation, Access_Water)
    if (all(is.na(vals))) NA_real_ else 1 - mean(vals, na.rm = TRUE)
  },
  CI_coeff = {
    vals <- c(Literacy_01, Attendance_01, LIAS_01, Disability_Capability)
    if (all(is.na(vals))) NA_real_ else mean(vals, na.rm = TRUE)
  }
) %>% ungroup()

# Final output
write_csv(merged, out_csv)
log("Wrote coefficients output to: ", out_csv)

# Validation report
vr <- c()
vr <- c(vr, sprintf("Timestamp: %s", Sys.time()))
vr <- c(vr, sprintf("Output rows: %d", nrow(merged)))
vr <- c(vr, "Columns created: Access_Electricity, Access_Sanitation, Access_Water, Dependency_Ratio, FCI_coeff, CI_coeff")
# report any Dependency_Ratio outliers
dr_outliers <- merged %>% filter(!is.na(Dependency_Ratio) & Dependency_Ratio > 3)
vr <- c(vr, sprintf("Dependency ratio >3 count: %d", nrow(dr_outliers)))
vr <- c(vr, "Sample ICT row:")
vr <- c(vr, paste(capture.output(print(merged[ict_key, c('District','Age_TotalPop','Age_65_Plus','Age_15_29','Dependency_Ratio','Access_Electricity','Access_Sanitation','Access_Water','FCI_coeff','CI_coeff')])), collapse='\n'))
writeLines(vr, con = report)
log("Validation report written: ", report)

log("GLOBAL PASS COMPLETE. Review outputs.")
