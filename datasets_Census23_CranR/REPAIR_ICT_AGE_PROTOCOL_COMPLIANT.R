# REPAIR_ICT_AGE_PROTOCOL_COMPLIANT.R
# Per PBEA_PROTOCOL: Repair ICT age data using the Proxy Rule (Exception Handling)
#
# DECISION RATIONALE (PBEA_PROTOCOL Section 4):
#   - Rule 2.2: ICT is mandated to be included ("Geographic Firewall")
#   - Rule 2.1: Denominator Anchor prohibits rates > 1.0; Gallup data is 3.4x inflated (violates Rule 2.1)
#   - Rule 2.3: Loud Warning triggers on data mismatch > 0.15; 338.9% mismatch = REJECT
#   - Exception Handling: "Missing Data Rule - Use Proxy Rule + Document"
#
# SOLUTION:
#   - Age_TotalPop = Pop2023 from Master_Districts.csv (integrity-safe proxy)
#   - Age_Male, Age_Female, Age_Trans, Age_Rural, Age_Urban = NA (retain missing to prevent violations)
#   - Document fully in audit trail
#
# Usage: Rscript "C:/Users/Azalas12/Desktop/Census 2023/datasets_Census23_CranR/REPAIR_ICT_AGE_PROTOCOL_COMPLIANT.R"
#
# Output: Merged_Districts_REFACTORED.csv (overwrites original with corrected ICT row)
#         ICT_AGE_REPAIR_PROTOCOL_LOG.txt (audit trail per PBEA_PROTOCOL Section 5)

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr)
})

dir_in <- "C:/Users/Azalas12/Desktop/Census 2023/datasets_Census23_CranR"
merged_file <- file.path(dir_in, "Merged_Districts_REFACTORED.csv")
master_file <- file.path(dir_in, "Master_Districts.csv")
log_file <- file.path(dir_in, "ICT_AGE_REPAIR_PROTOCOL_LOG.txt")

# Redirect console AND file output
log_con <- file(log_file, "w")

log_write <- function(msg) {
  cat(msg, "\n", sep = "", file = log_con)
  cat(msg, "\n", sep = "")
}

tryCatch({
  log_write("=== ICT AGE REPAIR (PBEA_PROTOCOL COMPLIANT) ===")
  log_write(sprintf("Timestamp: %s", Sys.time()))
  log_write("")
  log_write("DECISION BASIS:")
  log_write("  Rule 2.2 (Geographic Firewall): ICT included (mandatory)")
  log_write("  Rule 2.1 (Denominator Anchor): Rejects inflated Gallup data (338.9% mismatch)")
  log_write("  Rule 2.3 (Loud Warning): Data integrity violation (STOP)")
  log_write("  Exception Handling: Proxy Rule + Documentation")
  log_write("")

  # Read input files
  log_write("[1] Reading input files...")
  if (!file.exists(merged_file)) stop(sprintf("File not found: %s", merged_file))
  if (!file.exists(master_file)) stop(sprintf("File not found: %s", master_file))

  merged <- read_csv(merged_file, show_col_types = FALSE)
  master <- read_csv(master_file, show_col_types = FALSE)

  log_write(sprintf("  Merged dataset: %d rows × %d cols", nrow(merged), ncol(merged)))
  log_write(sprintf("  Master_Districts: %d rows", nrow(master)))

  # Find ICT in both datasets
  log_write("")
  log_write("[2] Locating ICT...")
  ict_idx_merged <- which(merged$District == "ICT")
  ict_row_master <- master %>% filter(District == "ICT")

  if (length(ict_idx_merged) == 0) stop("ICT not found in merged dataset")
  if (nrow(ict_row_master) == 0) stop("ICT not found in Master_Districts")

  ict_pop2023 <- ict_row_master$Pop2023[1]
  log_write(sprintf("  ICT found at row %d in merged dataset", ict_idx_merged))
  log_write(sprintf("  Master_Districts Pop2023 for ICT: %d", ict_pop2023))

  # Apply Proxy Rule
  log_write("")
  log_write("[3] Applying Proxy Rule (Exception Handling)...")
  log_write("  Before repair:")
  log_write(sprintf("    Age_TotalPop: %s", 
                    if(is.na(merged$Age_TotalPop[ict_idx_merged])) "NA" 
                    else merged$Age_TotalPop[ict_idx_merged]))
  log_write(sprintf("    Age_Male: %s", 
                    if(is.na(merged$Age_Male[ict_idx_merged])) "NA" 
                    else merged$Age_Male[ict_idx_merged]))

  # Set Age_TotalPop to Pop2023 (proxy)
  merged$Age_TotalPop[ict_idx_merged] <- ict_pop2023

  # Ensure age-strata remain NA (do not impute; document limitation)
  if (!"Age_Male" %in% names(merged)) {
    merged$Age_Male <- NA_real_
  } else {
    merged$Age_Male[ict_idx_merged] <- NA_real_
  }
  
  if (!"Age_Female" %in% names(merged)) {
    merged$Age_Female <- NA_real_
  } else {
    merged$Age_Female[ict_idx_merged] <- NA_real_
  }
  
  if (!"Age_Trans" %in% names(merged)) {
    merged$Age_Trans <- NA_real_
  } else {
    merged$Age_Trans[ict_idx_merged] <- NA_real_
  }
  
  if (!"Age_Rural" %in% names(merged)) {
    merged$Age_Rural <- NA_real_
  } else {
    merged$Age_Rural[ict_idx_merged] <- NA_real_
  }
  
  if (!"Age_Urban" %in% names(merged)) {
    merged$Age_Urban <- NA_real_
  } else {
    merged$Age_Urban[ict_idx_merged] <- NA_real_
  }

  log_write("  After repair (Proxy Rule):")
  log_write(sprintf("    Age_TotalPop: %d (sourced from Master_Districts Pop2023)", ict_pop2023))
  log_write("    Age_Male: NA (retained; official age strata unavailable)")
  log_write("    Age_Female: NA (retained; official age strata unavailable)")
  log_write("    Age_Trans: NA (retained; official age strata unavailable)")
  log_write("    Age_Rural: NA (retained; official age strata unavailable)")
  log_write("    Age_Urban: NA (retained; official age strata unavailable)")

  # Write corrected dataset
  log_write("")
  log_write("[4] Writing corrected merged dataset...")
  write_csv(merged, merged_file)
  log_write(sprintf("  ✓ Overwrote: %s", merged_file))

  log_write("")
  log_write("=== REPAIR COMPLETE (PROTOCOL COMPLIANT) ===")
  log_write(sprintf("Timestamp: %s", Sys.time()))
  log_write("")
  log_write("METHODOLOGY NOTE FOR PUBLICATION:")
  log_write("  ICT age data is missing from official Census 2023 published tabulations")
  log_write("  (both SLII_Age_Bulge.csv and Gallup Pakistan dashboard). Per PBEA_PROTOCOL")
  log_write("  Exception Handling Rule, Age_TotalPop for ICT is sourced from Master_Districts")
  log_write("  Pop2023 as an integrity-safe proxy. Age-strata (Male, Female, Rural, Urban)")
  log_write("  are retained as NA to preserve data integrity and prevent downstream")
  log_write("  rate calculations with incomplete strata. Analysis requiring complete")
  log_write("  age-structured data should exclude ICT or document the proxy explicitly.")
  log_write("")

}, error = function(e) {
  log_write(sprintf("❌ ERROR: %s", conditionMessage(e)))
  stop(e)
})

close(log_con)

# Print summary to console
cat("\n========== ICT AGE REPAIR COMPLETE (PBEA_PROTOCOL) ==========\n")
cat(sprintf("Corrected file: %s\n", merged_file))
cat(sprintf("Audit log: %s\n", log_file))
cat("Read log for full details.\n\n")
