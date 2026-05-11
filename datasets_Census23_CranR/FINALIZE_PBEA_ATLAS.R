# FINALIZE_PBEA_ATLAS.R
# Final pipeline implementing the Three-Layer Integrity Model per PBEA_PROTOCOL
# Produces Final_PBEA_Atlas_Data.csv and Validation_Report.txt
#
# Usage:
# Rscript "C:/Users/Azalas12/Desktop/Census 2023/datasets_Census23_CranR/FINALIZE_PBEA_ATLAS.R"

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(purrr)
  library(stringdist)
})

# ---------------------------- Configuration ----------------------------
dir_in <- "C:/Users/Azalas12/Desktop/Census 2023/datasets_Census23_CranR"
dir_main <- "C:/Users/Azalas12/Desktop/Census 2023"
master_file <- file.path(dir_in, "Master_Districts.csv")
age_group_file <- file.path(dir_main, "age-group.csv")
final_out <- file.path(dir_in, "Final_PBEA_Atlas_Data.csv")
validation_out <- file.path(dir_in, "Validation_Report.txt")
threshold_stringdist <- 0.15

log_msgs <- list()
log <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n")
  log_msgs[[length(log_msgs) + 1]] <<- msg
}

# ---------------------------- Helpers ----------------------------
norm_dist <- function(x) {
  x0 <- toupper(str_trim(as.character(x)))
  x0 <- str_replace_all(x0, "\\s+", " ")
  x0 <- ifelse(x0 == "ICT", "ISLAMABAD", x0)
  x0 <- ifelse(x0 == "MALAKAND PROTECTED AREA", "MALAKAND", x0)
  x0
}

find_col_loud <- function(df, target_col, threshold = threshold_stringdist) {
  cols <- toupper(names(df))
  target <- toupper(target_col)
  if (target %in% cols) {
    idx <- which(cols == target)[1]
    return(list(index = idx, name = names(df)[idx], method = "exact", distance = 0))
  }
  distances <- stringdist::stringdist(target, cols, method = "jw")
  best_idx <- which.min(distances)
  best_dist <- distances[best_idx]
  if (best_dist > threshold) stop(sprintf("COLUMN RESOLUTION FAILED: Seeking '%s', best match '%s' has distance %.3f (threshold: %.3f)", target, cols[best_idx], best_dist, threshold))
  if (best_dist > 0) warning(sprintf("String-distance column resolution: '%s' -> '%s' (distance: %.3f)", target, names(df)[best_idx], best_dist))
  list(index = best_idx, name = names(df)[best_idx], method = "string_distance", distance = best_dist)
}

# Parse age-group strings like '15 - 49', 'UNDER 5', '65 &  ABOVE'
parse_age_group <- function(s) {
  s <- toupper(str_trim(s))
  s <- str_replace_all(s, "&", "")
  s <- str_replace_all(s, "\\s+", " ")
  if (str_detect(s, "UNDER\\s+(\\d+)")) {
    low <- 0
    high <- as.numeric(str_match(s, "UNDER\\s+(\\d+)")[,2])
    return(c(low, high))
  }
  if (str_detect(s, "(\\d+)\\s*-\\s*(\\d+)")) {
    m <- str_match(s, "(\\d+)\\s*-\\s*(\\d+)")
    return(c(as.numeric(m[2]), as.numeric(m[3])))
  }
  if (str_detect(s, "(\\d+)\\s*\\+|(\\d+)\\s*ABOVE|ABOVE\\s*(\\d+)")) {
    # interpret as 65 & ABOVE etc.
    nums <- str_extract_all(s, "\\d+", simplify = TRUE)
    if (length(nums) >= 1 && nums[1] != "") {
      low <- as.numeric(nums[1])
      high <- Inf
      return(c(low, high))
    }
  }
  return(c(NA, NA))
}

# overlap indicator between two intervals [a1,a2] and [b1,b2]
overlap <- function(a, b) {
  a1 <- a[1]; a2 <- a[2]; b1 <- b[1]; b2 <- b[2]
  if (is.infinite(a2) & is.infinite(b2)) return(TRUE)
  if (is.na(a1) | is.na(b1)) return(FALSE)
  return(!(a2 < b1 || b2 < a1))
}

# sum population for an interval range
sum_age_range <- function(df_age, low, high) {
  # df_age must have `Age Group` and `Population Reporting` and District + Region + Gender
  ranges <- t(apply(df_age["Age Group", drop = FALSE], 1, function(r) parse_age_group(r)))
  keep <- apply(ranges, 1, function(r) {
    rr <- as.numeric(r)
    if (any(is.na(rr))) return(FALSE)
    return(!(rr[2] < low || (high < rr[1])))
  })
  sum(df_age$`Population Reporting`[keep], na.rm = TRUE)
}

# ---------------------------- Load master spine ----------------------------
log("[1] Loading master spine and preparing DistrictKey...")
master <- read_csv(master_file, show_col_types = FALSE)
master <- master %>% mutate(DistrictKey = norm_dist(District))

# ---------------------------- Load tributaries & process ----------------------------
log("[2] Processing tributary files with denominator anchoring...")
# list known tributary files in folder (pattern)
files <- list.files(dir_in, pattern = "*.csv$", full.names = TRUE)
# exclude master, outputs
files <- files[!basename(files) %in% c("Master_Districts.csv", "Merged_Districts.csv", "Merged_Districts_REFACTORED.csv", basename(final_out))]

# We'll target a few known tables; generic processing for FCI and CI
# Define extraction rules: file -> numerator columns, denominator name
processing_plan <- list(
  FCI_Energy = list(file = file.path(dir_in, "FCI_Energy_Fuel.csv"), denom = "HOUSEHOLDS"),
  FCI_San = list(file = file.path(dir_in, "FCI_Sanitation_Structure.csv"), denom = "HOUSEHOLDS"),
  FCI_Wtr = list(file = file.path(dir_in, "FCI_Water.csv"), denom = "HOUSEHOLDS"),
  CI_Disab = list(file = file.path(dir_in, "CI_Disability.csv"), denom = "ALL_SEXES_OVERALL"),
  CI_Lang = list(file = file.path(dir_in, "CI_Language_Spine.csv"), denom = "ALL_SEXES_OVERALL"),
  CI_Lit = list(file = file.path(dir_in, "CI_Literacy_Attendance.csv"), denom = NULL),
  SLII_Age = list(file = file.path(dir_in, "SLII_Age_Bulge.csv"), denom = NULL),
  SLII_Marital = list(file = file.path(dir_in, "SLII_Marital_Status.csv"), denom = NULL)
)

# store intermediate dataframes
dfs <- list()

for (name in names(processing_plan)) {
  p <- processing_plan[[name]]
  if (!file.exists(p$file)) {
    log(sprintf("  - Skipping %s (file not found): %s", name, p$file))
    next
  }
  log(sprintf("  - Reading %s", basename(p$file)))
  df <- read_csv(p$file, show_col_types = FALSE)
  # normalize district key
  if ("DISTRICT" %in% toupper(names(df))) {
    # find proper case
    dn <- names(df)[which(toupper(names(df)) == "DISTRICT")[1]]
    df <- df %>% mutate(DistrictKey = norm_dist(.data[[dn]]))
  } else if ("District" %in% names(df)) {
    df <- df %>% mutate(DistrictKey = norm_dist(District))
  } else {
    df <- df %>% mutate(DistrictKey = NA_character_)
  }

  # branch processing
  if (startsWith(name, "FCI_")) {
    # sum numeric columns per DistrictKey, get HOUSEHOLDS denom
    denom_col <- "HOUSEHOLDS"
    num_cols <- names(df)[sapply(df, is.numeric) & !(names(df) %in% c("HOUSEHOLDS"))]
    agg <- df %>% filter(REGION == "OVERALL") %>% group_by(DistrictKey) %>%
      summarise(across(all_of(num_cols), ~sum(.x, na.rm = TRUE)), HOUSEHOLDS = sum(HOUSEHOLDS, na.rm = TRUE), .groups = "drop")
    # prefix
    pref <- ifelse(name=="FCI_Energy","Energy_", ifelse(name=="FCI_San","San_","Wtr_"))
    agg <- agg %>% rename_with(~paste0(pref, .x), -DistrictKey)
    dfs[[name]] <- agg
  } else if (name == "CI_Disab") {
    # pivot disability types
    agg <- df %>% mutate(DistrictKey = norm_dist(DISTRICT)) %>%
      group_by(DistrictKey, DISAB_FUNC_LIM) %>%
      summarise(n = sum(ALL_SEXES_OVERALL, na.rm = TRUE), .groups = "drop") %>%
      pivot_wider(names_from = DISAB_FUNC_LIM, values_from = n, names_prefix = "Disab_", values_fill = 0)
    dfs[[name]] <- agg
  } else if (name == "CI_Lang") {
    agg <- df %>% mutate(DistrictKey = norm_dist(DISTRICT)) %>%
      group_by(DistrictKey, LANGUAGE) %>%
      summarise(n = sum(ALL_SEXES_OVERALL, na.rm = TRUE), .groups = "drop") %>%
      pivot_wider(names_from = LANGUAGE, values_from = n, names_prefix = "Lang_", values_fill = 0)
    dfs[[name]] <- agg
  } else if (name == "CI_Lit") {
    lit <- df %>% mutate(DistrictKey = norm_dist(DISTRICT)) %>%
      filter(VARS %in% c("Population >=10", "Literate >=10", "Population >=5", "Ever Attended", "Out of School Children (5-16)")) %>%
      group_by(DistrictKey, VARS) %>% summarise(n = sum(ALL_SEXES_OVERALL, na.rm = TRUE), .groups = "drop") %>%
      pivot_wider(names_from = VARS, values_from = n)
    dfs[[name]] <- lit
  } else if (name == "SLII_Age") {
    age <- df %>% mutate(DistrictKey = norm_dist(DISTRICT)) %>% filter(SEX_AGE_GROUP_IN_YEARS == "ALL AGES") %>%
      group_by(DistrictKey) %>% summarise(Age_TotalPop = sum(ALL_SEXES_OVERALL, na.rm = TRUE),
                                          Age_Male = sum(MALE_OVERALL, na.rm = TRUE),
                                          Age_Female = sum(FEMALE_OVERALL, na.rm = TRUE),
                                          Age_Trans = sum(TRANSGENDER_OVERALL, na.rm = TRUE),
                                          Age_Rural = sum(ALL_SEXES_RURAL, na.rm = TRUE),
                                          Age_Urban = sum(ALL_SEXES_URBAN, na.rm = TRUE), .groups = "drop")
    dfs[[name]] <- age
  } else if (name == "SLII_Marital") {
    marital <- df %>% mutate(DistrictKey = norm_dist(DISTRICT)) %>% filter(str_squish(AGE_GROUP) == "15 & ABOVE") %>%
      group_by(DistrictKey, MARITAL_STATUS) %>% summarise(n = sum(ALL_SEXES_OVERALL, na.rm = TRUE), .groups = "drop") %>%
      pivot_wider(names_from = MARITAL_STATUS, values_from = n, names_prefix = "Marital_", values_fill = 0)
    dfs[[name]] <- marital
  }
}

# ---------------------------- Assembly & Denominator Anchoring ----------------------------
log("[3] Assembling master dataset and applying denominator anchoring (lockstep joins)...")
merged <- master %>% mutate(DistrictKey = norm_dist(District))

# left join all dfs
for (nm in names(dfs)) {
  log(sprintf("  - Joining %s", nm))
  merged <- left_join(merged, dfs[[nm]], by = "DistrictKey")
}

# Compute rates deterministically and cap >1.0 with loud warning
log("[4] Calculating rates and applying caps (>1.0 -> cap and loud warning)...")
# Energy example
if ("Energy_HOUSEHOLDS" %in% names(merged)) {
  merged <- merged %>% mutate(Energy_Access_Electricity = ifelse(Energy_HOUSEHOLDS > 0, Energy_LIGHT_ELECT / Energy_HOUSEHOLDS, NA_real_))
  bad <- which(!is.na(merged$Energy_Access_Electricity) & merged$Energy_Access_Electricity > 1)
  if (length(bad) > 0) {
    for (i in bad) log(sprintf("LOUD WARNING: Energy_Access_Electricity >1 in %s (%.3f). Capped to 1.0", merged$District[i], merged$Energy_Access_Electricity[i]))
    merged$Energy_Access_Electricity[bad] <- 1.0
  }
}
# Sanitation
if ("San_HOUSEHOLDS" %in% names(merged)) {
  merged <- merged %>% mutate(San_Access_SanitaryToilet = ifelse(San_HOUSEHOLDS > 0, San_TOILET_FLUSH / San_HOUSEHOLDS, NA_real_))
  bad <- which(!is.na(merged$San_Access_SanitaryToilet) & merged$San_Access_SanitaryToilet > 1)
  if (length(bad) > 0) {
    for (i in bad) log(sprintf("LOUD WARNING: San_Access_SanitaryToilet >1 in %s (%.3f). Capped to 1.0", merged$District[i], merged$San_Access_SanitaryToilet[i]))
    merged$San_Access_SanitaryToilet[bad] <- 1.0
  }
}
# Water
if ("Wtr_HOUSEHOLDS" %in% names(merged)) {
  merged <- merged %>% mutate(Wtr_Access_ImprovedDrink = ifelse(Wtr_HOUSEHOLDS > 0, Wtr_DRINK_WTR_IMPROVE / Wtr_HOUSEHOLDS, NA_real_))
  bad <- which(!is.na(merged$Wtr_Access_ImprovedDrink) & merged$Wtr_Access_ImprovedDrink > 1)
  if (length(bad) > 0) {
    for (i in bad) log(sprintf("LOUD WARNING: Wtr_Access_ImprovedDrink >1 in %s (%.3f). Capped to 1.0", merged$District[i], merged$Wtr_Access_ImprovedDrink[i]))
    merged$Wtr_Access_ImprovedDrink[bad] <- 1.0
  }
}
# Literacy & Attendance
if (all(c("Pop_GE10", "Lit_GE10") %in% names(merged))) {
  merged <- merged %>% mutate(Literacy_01 = ifelse(Pop_GE10 > 0, Lit_GE10 / Pop_GE10, NA_real_))
  bad <- which(!is.na(merged$Literacy_01) & merged$Literacy_01 > 1)
  if (length(bad) > 0) {
    for (i in bad) log(sprintf("LOUD WARNING: Literacy_01 >1 in %s (%.3f). Capped to 1.0", merged$District[i], merged$Literacy_01[i]))
    merged$Literacy_01[bad] <- 1.0
  }
}
if (all(c("Pop_GE5", "EverAttended") %in% names(merged))) {
  merged <- merged %>% mutate(Attendance_01 = ifelse(Pop_GE5 > 0, EverAttended / Pop_GE5, NA_real_))
  bad <- which(!is.na(merged$Attendance_01) & merged$Attendance_01 > 1)
  if (length(bad) > 0) {
    for (i in bad) log(sprintf("LOUD WARNING: Attendance_01 >1 in %s (%.3f). Capped to 1.0", merged$District[i], merged$Attendance_01[i]))
    merged$Attendance_01[bad] <- 1.0
  }
}

# ---------------------------- ICT Patch (Layer 2) ----------------------------
log("[5] Applying ICT Patch if needed (per Protocol)...")
ict_row <- which(norm_dist(merged$District) == "ISLAMABAD")
if (length(ict_row) == 0) stop("ICT (Islamabad) row not found in Master spine")

# If Age_TotalPop NA, attempt to use Gallup age-group.csv
if (!file.exists(age_group_file)) {
  log(sprintf("age-group.csv not found: %s. Skipping Gallup patch.", age_group_file))
} else {
  # read age-group
  age_raw <- read_csv(age_group_file, show_col_types = FALSE)
  # filter Islamabad rows
  ict_gallup <- age_raw %>% filter(str_detect(toupper(Province), "ISLAMABAD") & str_detect(toupper(District), "ISLAMABAD"))
  if (nrow(ict_gallup) == 0) {
    log("No Islamabad rows found in age-group.csv; skipping Gallup patch.")
  } else {
    # compute Age_65_Plus as sum Urban + Rural counts for age groups overlapping >=65
    # identify rows where Age Group overlaps with 65+
    age_ranges <- t(apply(as.data.frame(ict_gallup$`Age Group`), 1, function(r) parse_age_group(r)))
    keep65 <- sapply(1:nrow(age_ranges), function(i) {
      r <- age_ranges[i,]
      !is.na(r[1]) && (is.infinite(r[2]) || r[2] >= 65 || r[1] >= 65)
    })
    age65_sum <- sum(ict_gallup$`Population Reporting`[keep65], na.rm = TRUE)

    # For ICT total pop take master Pop2023
    ict_pop_master <- master$Pop2023[which(norm_dist(master$District) == 'ISLAMABAD')][1]
    # Compute Rawalpindi youth ratio (15-29)
    # find Rawalpindi rows
    rp_raw <- age_raw %>% filter(str_detect(toupper(District), "RAWALPINDI"))
    youth_rp <- 0
    rp_total <- 0
    if (nrow(rp_raw) > 0) {
      # compute sum of populations with overlap to 15-29
      ranges_rp <- t(apply(as.data.frame(rp_raw$`Age Group`), 1, function(r) parse_age_group(r)))
      keep15_29 <- sapply(1:nrow(ranges_rp), function(i) {
        r <- ranges_rp[i,]
        !is.na(r[1]) && !(r[2] < 15 || 29 < r[1])
      })
      youth_rp <- sum(rp_raw$`Population Reporting`[keep15_29], na.rm = TRUE)
      rp_total <- sum(rp_raw$`Population Reporting`, na.rm = TRUE)
    }
    youth_ratio <- if (rp_total > 0) youth_rp / rp_total else NA_real_

    # Apply patch per instructions
    if (is.na(merged$Age_TotalPop[ict_row])) {
      merged$Age_TotalPop[ict_row] <- ict_pop_master
      log(sprintf("ICT Age_TotalPop set to Master Pop2023: %d", ict_pop_master))
    }
    # set Age_65_Plus
    merged$Age_65_Plus <- NA_real_
    merged$Age_65_Plus[ict_row] <- age65_sum
    log(sprintf("ICT Age_65_Plus (from Gallup sums): %d", age65_sum))

    # set Age_15_29 using twin-city proxy
    if (!is.na(youth_ratio)) {
      merged$Age_15_29 <- NA_real_
      merged$Age_15_29[ict_row] <- round(merged$Age_TotalPop[ict_row] * youth_ratio)
      log(sprintf("Rawalpindi youth ratio: %.4f. ICT Age_15_29 imputed: %d", youth_ratio, merged$Age_15_29[ict_row]))
    } else {
      log("Could not compute Rawalpindi youth ratio; Age_15_29 left NA")
    }
  }
}

# ---------------------------- Feature Engineering (Causal Engines) ----------------------------
log("[6] Feature engineering: H2 Scale Fix, FCI, CI, CAPS...")
# Literacy normalization: if Literacy_01 exists it's ok; else compute from Lit_GE10 / Pop_GE10
if (!"Literacy_01" %in% names(merged) && all(c("Lit_GE10","Pop_GE10") %in% names(merged))) {
  merged <- merged %>% mutate(Literacy_01 = ifelse(Pop_GE10>0, Lit_GE10/Pop_GE10, NA_real_))
}
# Min-max scaling (ensure within [0,1])
if ("Literacy_01" %in% names(merged)) {
  lit_min <- min(merged$Literacy_01, na.rm = TRUE)
  lit_max <- max(merged$Literacy_01, na.rm = TRUE)
  if (lit_max > lit_min) merged <- merged %>% mutate(Literacy_01 = (Literacy_01 - lit_min) / (lit_max - lit_min))
}

# LIAS_01 = Lang_URDU / Lang_TOTAL
if (all(c("Lang_URDU","Lang_TOTAL") %in% names(merged))) merged <- merged %>% mutate(LIAS_01 = ifelse(Lang_TOTAL>0, Lang_URDU / Lang_TOTAL, NA_real_))

# Inverse_Disability_01: 1 - (total disability / Age_TotalPop)  (ensure no division by zero)
if ("Disab_Population" %in% names(merged) && "Age_TotalPop" %in% names(merged)) {
  merged <- merged %>% mutate(Inverse_Disability_01 = ifelse(Age_TotalPop>0, 1 - (Disab_Population / Age_TotalPop), NA_real_))
}

# CAPS: Literacy_01 * (1 - LIAS_01)
if (all(c("Literacy_01","LIAS_01") %in% names(merged))) merged <- merged %>% mutate(CAPS = Literacy_01 * (1 - LIAS_01))

# FCI: 1 - mean(Energy_Access_Electricity, San_Access_SanitaryToilet, Wtr_Access_ImprovedDrink) (rowwise)
merged <- merged %>% rowwise() %>% mutate(FCI = {
  vals <- c(ifelse(exists("Energy_Access_Electricity") && !is.null(Energy_Access_Electricity), Energy_Access_Electricity, NA),
            ifelse(exists("San_Access_SanitaryToilet") && !is.null(San_Access_SanitaryToilet), San_Access_SanitaryToilet, NA),
            ifelse(exists("Wtr_Access_ImprovedDrink") && !is.null(Wtr_Access_ImprovedDrink), Wtr_Access_ImprovedDrink, NA))
  if (all(is.na(vals))) NA_real_ else 1 - mean(vals, na.rm = TRUE)
}) %>% ungroup()

# CI: mean(Literacy_01, Attendance_01, LIAS_01, Inverse_Disability_01)
merged <- merged %>% rowwise() %>% mutate(CI = {
  vals <- c(ifelse(exists("Literacy_01") && !is.null(Literacy_01), Literacy_01, NA),
            ifelse(exists("Attendance_01") && !is.null(Attendance_01), Attendance_01, NA),
            ifelse(exists("LIAS_01") && !is.null(LIAS_01), LIAS_01, NA),
            ifelse(exists("Inverse_Disability_01") && !is.null(Inverse_Disability_01), Inverse_Disability_01, NA))
  if (all(is.na(vals))) NA_real_ else mean(vals, na.rm = TRUE)
}) %>% ungroup()

# ---------------------------- Output & Validation Report ----------------------------
log("[7] Writing final outputs and validation report...")
write_csv(merged, final_out)

# Validation report
vr <- list()
vr$timestamp <- as.character(Sys.time())
vr$rows <- nrow(merged)
vr$cols <- ncol(merged)
vr$missing_by_col <- colSums(is.na(merged))
# capped rates detection: we logged loud warnings earlier; also check any >1 before cap
capped <- merged %>% summarise(across(contains("Access_"), ~sum(.x > 1, na.rm = TRUE)))
vr$capped_rates_count <- sum(capped)

report_lines <- c()
report_lines <- c(report_lines, sprintf("Final_PBEA_Atlas generated: %s", final_out))
report_lines <- c(report_lines, sprintf("Rows: %d, Columns: %d", vr$rows, vr$cols))
report_lines <- c(report_lines, "\nMissing values by column:")
for (i in seq_along(vr$missing_by_col)) report_lines <- c(report_lines, sprintf("  %s: %d", names(vr$missing_by_col)[i], vr$missing_by_col[i]))
report_lines <- c(report_lines, sprintf("\nCapped rates detected (post-cap): %d", vr$capped_rates_count))
report_lines <- c(report_lines, "\nLog messages:")
report_lines <- c(report_lines, unlist(log_msgs))

writeLines(report_lines, con = validation_out)
log(sprintf("Final outputs written: %s and %s", final_out, validation_out))

log("Pipeline complete. Review Validation_Report.txt for details.")
