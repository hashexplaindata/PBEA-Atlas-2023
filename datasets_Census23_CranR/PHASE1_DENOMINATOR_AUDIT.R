suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(stringr); library(purrr)
})

# ============================================================================
# PHASE 1: DENOMINATOR AUDIT SCRIPT
# Pakistan Census 2023 - Data Integrity Diagnostics
# ============================================================================

dir_in  <- "C:/Users/Azalas12/Desktop/Census 2023/datasets_Census23_CranR"
audit_output <- file.path(dir_in, "DENOMINATOR_AUDIT_LOG.csv")

cat("\n========== CENSUS 2023 DATA INTEGRITY AUDIT ==========\n")
cat("Phase 1: Denominator Validation\n")
cat("Timestamp:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# ----------- HELPER FUNCTIONS -----------

audit_row <- function(source_file, category, metric, test_result, details) {
  data.frame(
    Timestamp = Sys.time(),
    Source_File = source_file,
    Category = category,
    Metric = metric,
    Result = test_result,
    Details = details,
    Severity = ifelse(test_result == "PASS", "✓", "⚠️"),
    stringsAsFactors = FALSE
  )
}

# ----------- 1. FCI FILES AUDIT -----------

cat("\n[1/4] AUDITING FCI FILES (Facilities Count Index)\n")
cat("      Files: Energy_Fuel, Sanitation_Structure, Water\n\n")

fci_files <- c("FCI_Energy_Fuel.csv", "FCI_Sanitation_Structure.csv", "FCI_Water.csv")
audit_log <- data.frame()

for (fci_file in fci_files) {
  cat("  →", fci_file, "\n")
  
  df <- read_csv(file.path(dir_in, fci_file), show_col_types = FALSE)
  
  # Filter to OVERALL only (this is what merge_districts.R does)
  overall <- df %>% filter(REGION == "OVERALL")
  
  # Test 1: Check for NA in HOUSEHOLDS column (Denominator)
  households_na <- sum(is.na(overall$HOUSEHOLDS))
  test1 <- ifelse(households_na == 0, "PASS", "FAIL")
  audit_log <- rbind(audit_log, audit_row(
    fci_file,
    "Denominator (HOUSEHOLDS)",
    "NA_Count",
    test1,
    sprintf("NA values in HOUSEHOLDS: %d of %d", households_na, nrow(overall))
  ))
  
  # Test 2: Check for ZERO in HOUSEHOLDS (division by zero risk)
  households_zero <- sum(overall$HOUSEHOLDS == 0, na.rm = TRUE)
  test2 <- ifelse(households_zero == 0, "PASS", "⚠️ WARNING")
  audit_log <- rbind(audit_log, audit_row(
    fci_file,
    "Denominator (HOUSEHOLDS)",
    "Zero_Count",
    test2,
    sprintf("Zero values in HOUSEHOLDS: %d of %d", households_zero, nrow(overall))
  ))
  
  # Test 3: Check for duplicate HOUSEHOLDS within same district (data quality)
  dup_check <- overall %>%
    group_by(DISTRICT) %>%
    summarise(
      n_rows = n(),
      n_unique_households = n_distinct(HOUSEHOLDS, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    filter(n_unique_households > 1)
  
  test3 <- ifelse(nrow(dup_check) == 0, "PASS", "⚠️ WARNING")
  audit_log <- rbind(audit_log, audit_row(
    fci_file,
    "Data_Quality",
    "Duplicate_Households",
    test3,
    sprintf("Districts with multiple HOUSEHOLDS values: %d", nrow(dup_check))
  ))
  
  # Test 4: Rate sanity check (all numerator columns)
  numerator_cols <- setdiff(names(overall), 
    c("PROVINCE", "DIVISION", "DISTRICT", "TEHSIL", "ADMIN_UNIT", "REGION", "HOUSEHOLDS"))
  
  bad_rates_list <- list()
  
  for (num_col in numerator_cols) {
    if (is.numeric(overall[[num_col]])) {
      rates <- overall[[num_col]] / overall$HOUSEHOLDS
      bad_idx <- which(rates > 1.0 & !is.na(rates))
      if (length(bad_idx) > 0) {
        bad_rates_list[[num_col]] <- bad_idx
      }
    }
  }
  
  n_bad_rates <- sum(lengths(bad_rates_list))
  test4 <- ifelse(n_bad_rates == 0, "PASS", "❌ FAIL")
  
  audit_log <- rbind(audit_log, audit_row(
    fci_file,
    "Rate_Validity",
    "Rate_Greater_1",
    test4,
    sprintf("Rows with rate > 1.0: %d across %d cols", n_bad_rates, length(bad_rates_list))
  ))
  
  if (n_bad_rates > 0) {
    cat("    ❌ INFINITE FRICTION DETECTED:\n")
    for (col in names(bad_rates_list)) {
      bad_rows <- bad_rates_list[[col]]
      cat(sprintf("       %s: %d rows\n", col, length(bad_rows)))
      # Show first 3
      for (idx in head(bad_rows, 3)) {
        rate <- overall[[col]][idx] / overall$HOUSEHOLDS[idx]
        cat(sprintf("         Row %d: %s/%s = %.4f\n", 
              idx, col, "HOUSEHOLDS", rate))
      }
    }
  }
  
  cat("\n")
}

# ----------- 2. CI FILES AUDIT (Census Index) -----------

cat("\n[2/4] AUDITING CI FILES (Census Index)\n")
cat("      Files: Disability, Language, Literacy\n\n")

ci_files <- c("CI_Disability.csv", "CI_Language_Spine.csv", "CI_Literacy_Attendance.csv")

for (ci_file in ci_files) {
  cat("  →", ci_file, "\n")
  
  df <- read_csv(file.path(dir_in, ci_file), show_col_types = FALSE)
  
  # Test: Check for NA in denominator (ALL_SEXES_OVERALL or category-specific)
  denom_col <- if ("ALL_SEXES_OVERALL" %in% names(df)) "ALL_SEXES_OVERALL" else NULL
  
  if (!is.null(denom_col)) {
    denom_na <- sum(is.na(df[[denom_col]]))
    test <- ifelse(denom_na == 0, "PASS", "⚠️ WARNING")
    
    audit_log <- rbind(audit_log, audit_row(
      ci_file,
      "Denominator",
      "NA_Count",
      test,
      sprintf("NA values in %s: %d of %d", denom_col, denom_na, nrow(df))
    ))
  }
  
  cat("\n")
}

# ----------- 3. SLII FILES AUDIT (Structural Level Indices) -----------

cat("\n[3/4] AUDITING SLII FILES (Structural Indices)\n")
cat("      Files: Age_Bulge, Marital_Status\n\n")

slii_files <- c("SLII_Age_Bulge.csv", "SLII_Marital_Status.csv")

for (slii_file in slii_files) {
  cat("  →", slii_file, "\n")
  
  df <- read_csv(file.path(dir_in, slii_file), show_col_types = FALSE)
  
  # Test: Check for NA in key demographic columns
  demo_cols <- c("ALL_SEXES_OVERALL", "MALE_OVERALL", "FEMALE_OVERALL")
  
  for (demo_col in demo_cols) {
    if (demo_col %in% names(df)) {
      na_count <- sum(is.na(df[[demo_col]]))
      test <- ifelse(na_count == 0, "PASS", "⚠️ WARNING")
      
      audit_log <- rbind(audit_log, audit_row(
        slii_file,
        "Demographics",
        paste0("NA_", demo_col),
        test,
        sprintf("NA values in %s: %d of %d", demo_col, na_count, nrow(df))
      ))
    }
  }
  
  cat("\n")
}

# ----------- 4. MASTER DISTRICTS AUDIT -----------

cat("\n[4/4] AUDITING MASTER DISTRICTS SPINE\n\n")

master <- read_csv(file.path(dir_in, "Master_Districts.csv"), show_col_types = FALSE)

# Test 1: Expected row count
n_master <- nrow(master)
test1 <- ifelse(n_master >= 130, "PASS", "⚠️ WARNING")
audit_log <- rbind(audit_log, audit_row(
  "Master_Districts.csv",
  "Spine_Integrity",
  "Row_Count",
  test1,
  sprintf("Total districts in spine: %d (expected: ~136-160)", n_master)
))

# Test 2: Geographic coverage
regions <- unique(master$Region)
test2 <- ifelse(length(regions) >= 4, "PASS", "⚠️ WARNING")
audit_log <- rbind(audit_log, audit_row(
  "Master_Districts.csv",
  "Geographic_Coverage",
  "Province_Count",
  test2,
  sprintf("Regions covered: %s", paste(regions, collapse = ", "))
))

# Test 3: Missing AJK/GB indicator
has_ajk <- any(grepl("AJK|JAMMU|KASHMIR", master$Region, ignore.case = TRUE))
has_gb <- any(grepl("GB|GILGIT|BALTISTAN", master$Region, ignore.case = TRUE))

missing_territories <- c()
if (!has_ajk) missing_territories <- c(missing_territories, "AJK")
if (!has_gb) missing_territories <- c(missing_territories, "GB")

test3 <- if (length(missing_territories) == 0) "PASS" else "⚠️ WARNING"
audit_log <- rbind(audit_log, audit_row(
  "Master_Districts.csv",
  "Geographic_Coverage",
  "Disputed_Territories",
  test3,
  sprintf("Missing: %s [Geographic scope is FOUR-PROVINCE ONLY]", 
          paste(missing_territories, collapse = " + "))
))

cat("  → Geographic coverage assessment:\n")
cat(sprintf("     Provinces: %s\n", paste(regions, collapse = ", ")))
cat(sprintf("     Total records: %d\n", n_master))
if (length(missing_territories) > 0) {
  cat(sprintf("     ⚠️  MISSING: %s\n", paste(missing_territories, collapse = " + ")))
  cat("     IMPLICATION: This is a Four-Province dataset ONLY\n")
}
cat("\n")

# ----------- SUMMARY REPORT -----------

cat("\n========== AUDIT SUMMARY ==========\n\n")

pass_count <- sum(grepl("PASS", audit_log$Result))
warn_count <- sum(grepl("WARNING", audit_log$Result))
fail_count <- sum(grepl("FAIL", audit_log$Result))

cat(sprintf("✓ PASSED: %d\n", pass_count))
cat(sprintf("⚠️  WARNINGS: %d\n", warn_count))
cat(sprintf("❌ FAILURES: %d\n\n", fail_count))

# Write audit log to CSV
write_csv(audit_log, audit_output)
cat(sprintf("Detailed log saved to: %s\n", audit_output))

# Print full audit table
cat("\nDetailed Results:\n")
print(audit_log %>% select(Source_File, Category, Metric, Result, Details))

# ----------- RECOMMENDATIONS -----------

cat("\n========== PHASE 1 RECOMMENDATIONS ==========\n\n")

if (fail_count > 0) {
  cat("❌ CRITICAL ISSUES DETECTED:\n")
  critical <- audit_log %>% filter(grepl("FAIL", Result))
  for (i in 1:nrow(critical)) {
    cat(sprintf("   - %s: %s\n", critical$Source_File[i], critical$Details[i]))
  }
  cat("\n   ACTION: Do NOT proceed to data merge until these are resolved.\n\n")
}

if (warn_count > 0) {
  cat("⚠️  WARNINGS REQUIRE ATTENTION:\n")
  warnings <- audit_log %>% filter(grepl("WARNING", Result))
  for (i in 1:nrow(warnings)) {
    cat(sprintf("   - %s: %s\n", warnings$Source_File[i], warnings$Details[i]))
  }
  cat("\n   ACTION: Review and document in methods section.\n\n")
}

if (length(missing_territories) > 0) {
  cat("🔍 GEOGRAPHIC SCOPE DETERMINATION:\n\n")
  cat("   Current: 4-Province Atlas (136 districts)\n")
  cat("   Missing: AJK, GB (~24 districts)\n")
  cat("   Decision Tree:\n")
  cat("     1) Check if PakPC2023PakDist R-package has missing districts\n")
  cat("     2) IF YES → Update Master_Districts.csv and re-merge\n")
  cat("     3) IF NO  → Add disclaimer to all outputs\n\n")
}

cat("✓ Phase 1 complete. Ready for Phase 2 (Geographic Scope Decision).\n")

