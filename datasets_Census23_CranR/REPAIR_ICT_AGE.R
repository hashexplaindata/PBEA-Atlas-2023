# REPAIR_ICT_AGE.R
# Fill missing ICT age data from Gallup Pakistan Census 2023 dashboard (age-group.csv)
# 
# Purpose: ICT (Islamabad) was missing from SLII_Age_Bulge.csv in the R-package.
#          The Gallup dashboard provides tehsil-level age data for Islamabad (Rural + Urban).
#          This script aggregates the Gallup data to ICT district-level and fills the merged dataset.
#
# Usage: Rscript "C:/Users/Azalas12/Desktop/Census 2023/datasets_Census23_CranR/REPAIR_ICT_AGE.R"
#
# Output: Merged_Districts_REFACTORED_with_ICT_age.csv (corrected merged file)
#         ICT_AGE_REPAIR_LOG.txt (audit log)

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr); library(tidyr)
})

dir_in <- "C:/Users/Azalas12/Desktop/Census 2023/datasets_Census23_CranR"
dir_main <- "C:/Users/Azalas12/Desktop/Census 2023"
age_group_file <- file.path(dir_main, "age-group.csv")
merged_in <- file.path(dir_in, "Merged_Districts_REFACTORED.csv")
master_file <- file.path(dir_in, "Master_Districts.csv")
merged_out <- file.path(dir_in, "Merged_Districts_REFACTORED_with_ICT_age.csv")
log_file <- file.path(dir_in, "ICT_AGE_REPAIR_LOG.txt")

sink(log_file)
cat("=== ICT AGE REPAIR LOG ===\n")
cat(sprintf("Timestamp: %s\n", Sys.time()))

tryCatch({
  # 1) Read input files
  cat("\n[1] Reading input files...\n")
  if (!file.exists(age_group_file)) stop(sprintf("age-group.csv not found: %s", age_group_file))
  if (!file.exists(merged_in)) stop(sprintf("Merged_Districts_REFACTORED.csv not found: %s", merged_in))
  if (!file.exists(master_file)) stop(sprintf("Master_Districts.csv not found: %s", master_file))

  age_raw <- read_csv(age_group_file, show_col_types = FALSE)
  merged <- read_csv(merged_in, show_col_types = FALSE)
  master <- read_csv(master_file, show_col_types = FALSE)

  cat(sprintf("  age-group.csv: %d rows\n", nrow(age_raw)))
  cat(sprintf("  Merged_Districts_REFACTORED.csv: %d rows\n", nrow(merged)))
  cat(sprintf("  Master_Districts.csv: %d rows\n", nrow(master)))

  # 2) Filter Islamabad data from age-group.csv
  cat("\n[2] Filtering Islamabad data from age-group.csv...\n")
  ict_raw <- age_raw %>%
    filter(str_detect(Province, regex("Islamabad", ignore_case = TRUE))) %>%
    filter(str_detect(District, regex("Islamabad", ignore_case = TRUE)))
  
  cat(sprintf("  Found %d rows for Islamabad\n", nrow(ict_raw)))
  cat(sprintf("  Unique regions: %s\n", paste(unique(ict_raw$Region), collapse = ", ")))
  cat(sprintf("  Unique genders: %s\n", paste(unique(ict_raw$Gender), collapse = ", ")))
  cat(sprintf("  Unique age groups: %s\n", 
              paste(sort(unique(ict_raw$`Age Group`)), collapse = "; ")))

  # 3) Aggregate to district level (sum across all age groups, tehsils, regions by gender)
  cat("\n[3] Aggregating to district-level...\n")
  ict_agg <- ict_raw %>%
    group_by(Gender) %>%
    summarise(
      total_pop = sum(`Population Reporting`, na.rm = TRUE),
      .groups = "drop"
    )
  
  cat(sprintf("  Aggregated by gender:\n"))
  print(ict_agg)

  # Parse gender categories
  ict_total_pop <- ict_raw %>% pull(`Population Reporting`) %>% sum(na.rm = TRUE)
  ict_male <- ict_agg %>% filter(str_detect(Gender, regex("^Male$", ignore_case = TRUE))) %>% pull(total_pop)
  ict_female <- ict_agg %>% filter(str_detect(Gender, regex("^Female$", ignore_case = TRUE))) %>% pull(total_pop)
  ict_trans <- ict_agg %>% filter(str_detect(Gender, regex("Tgend|Transgender", ignore_case = TRUE))) %>% pull(total_pop)

  ict_male <- if(length(ict_male) == 0) 0 else ict_male[1]
  ict_female <- if(length(ict_female) == 0) 0 else ict_female[1]
  ict_trans <- if(length(ict_trans) == 0) 0 else ict_trans[1]

  cat(sprintf("\n  Total population (all genders): %d\n", ict_total_pop))
  cat(sprintf("  Male: %d\n", ict_male))
  cat(sprintf("  Female: %d\n", ict_female))
  cat(sprintf("  Transgender: %d\n", ict_trans))

  # Aggregate by region (Rural/Urban)
  ict_by_region <- ict_raw %>%
    group_by(Region) %>%
    summarise(
      region_pop = sum(`Population Reporting`, na.rm = TRUE),
      .groups = "drop"
    )
  
  ict_rural <- ict_by_region %>% filter(str_detect(Region, "Rural")) %>% pull(region_pop)
  ict_urban <- ict_by_region %>% filter(str_detect(Region, "Urban")) %>% pull(region_pop)

  ict_rural <- if(length(ict_rural) == 0) 0 else ict_rural[1]
  ict_urban <- if(length(ict_urban) == 0) 0 else ict_urban[1]

  cat(sprintf("  Rural: %d\n", ict_rural))
  cat(sprintf("  Urban: %d\n", ict_urban))

  # 4) Validate against Master_Districts.csv Pop2023
  cat("\n[4] Validation...\n")
  ict_master_pop <- master %>% filter(str_detect(District, regex("Islamabad|ICT", ignore_case = TRUE))) %>% pull(Pop2023)
  if (length(ict_master_pop) == 0) {
    cat("  WARNING: Could not find Islamabad record in Master_Districts.csv\n")
  } else {
    ict_master_pop <- ict_master_pop[1]
    pct_match <- 100 * ict_total_pop / ict_master_pop
    cat(sprintf("  Master_Districts.csv Pop2023 for Islamabad: %d\n", ict_master_pop))
    cat(sprintf("  age-group.csv aggregate: %d\n", ict_total_pop))
    cat(sprintf("  Match: %.1f%%\n", pct_match))
    if (pct_match < 95 || pct_match > 105) {
      cat(sprintf("  ⚠️  WARNING: Mismatch > 5%%. Check data.\n"))
    } else {
      cat(sprintf("  ✓ Good agreement (within 5%% tolerance)\n"))
    }
  }

  # 5) Fill ICT row in merged dataset
  cat("\n[5] Filling ICT row in merged dataset...\n")
  ict_idx <- which(merged$District == "ICT")
  if (length(ict_idx) == 0) {
    stop("ICT row not found in merged dataset")
  }

  cat(sprintf("  Found ICT at row %d\n", ict_idx))
  cat(sprintf("  Before: Age_TotalPop = %s\n", 
              if(is.na(merged$Age_TotalPop[ict_idx])) "NA" else merged$Age_TotalPop[ict_idx]))

  merged$Age_TotalPop[ict_idx] <- ict_total_pop
  merged$Age_Male[ict_idx] <- ict_male
  merged$Age_Female[ict_idx] <- ict_female
  merged$Age_Trans[ict_idx] <- ict_trans
  merged$Age_Rural[ict_idx] <- ict_rural
  merged$Age_Urban[ict_idx] <- ict_urban

  cat(sprintf("  After: Age_TotalPop = %d\n", merged$Age_TotalPop[ict_idx]))
  cat(sprintf("  After: Age_Male = %d, Age_Female = %d, Age_Trans = %d\n", 
              merged$Age_Male[ict_idx], merged$Age_Female[ict_idx], merged$Age_Trans[ict_idx]))
  cat(sprintf("  After: Age_Rural = %d, Age_Urban = %d\n", 
              merged$Age_Rural[ict_idx], merged$Age_Urban[ict_idx]))

  # 6) Write corrected merged file
  cat("\n[6] Writing corrected merged dataset...\n")
  write_csv(merged, merged_out)
  cat(sprintf("  ✓ Written to: %s\n", merged_out))

  cat("\n=== REPAIR SUCCESSFUL ===\n")
  cat(sprintf("Timestamp: %s\n\n", Sys.time()))

}, error = function(e) {
  cat(sprintf("\n❌ ERROR: %s\n\n", conditionMessage(e)))
  stop(e)
})

sink()

# Print summary to console
cat("\n========== ICT AGE REPAIR COMPLETE ==========\n")
cat(sprintf("Log: %s\n", log_file))
cat(sprintf("Output: %s\n", merged_out))
cat("Read log file for details.\n\n")
