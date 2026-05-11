# RUN_ALL.R
# Wrapper to run Phase 1 audit, then refactored merge, and produce QA summary.
# Usage (from cmd):
#   Rscript "C:/Users/Azalas12/Desktop/Census 2023/datasets_Census23_CranR/RUN_ALL.R"
# Optional arg to impute ICT age (documented imputation):
#   Rscript ".../RUN_ALL.R" --impute-ict

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr); library(tidyr)
})

dir_in <- "C:/Users/Azalas12/Desktop/Census 2023/datasets_Census23_CranR"
status_file <- file.path(dir_in, "RUN_ALL_STATUS.txt")
qa_file <- file.path(dir_in, "QA_SUMMARY.csv")

args <- commandArgs(trailingOnly = TRUE)
impute_ict <- any(grepl("--impute-ict", args, ignore.case = TRUE))

cat("RUN_ALL.R starting...\n")
cat(sprintf("Working dir: %s\n", dir_in))
cat(sprintf("Impute ICT age if missing: %s\n", ifelse(impute_ict, "YES", "NO")))

## Create or clear the status file safely
if (file.exists(status_file)) file.remove(status_file)
cat("", file = status_file)

tryCatch({
  # 1) Run Phase 1 audit
  cat("\n[STEP 1] Running Phase 1 Denominator Audit...\n")
  source(file.path(dir_in, "PHASE1_DENOMINATOR_AUDIT.R"))
  audit_log_path <- file.path(dir_in, "DENOMINATOR_AUDIT_LOG.csv")
  if (!file.exists(audit_log_path)) stop("Audit log not created: " , audit_log_path)
  audit_log <- read_csv(audit_log_path, show_col_types = FALSE)

  # Check for FAILs
  n_fails <- sum(grepl("FAIL", audit_log$Result, ignore.case = TRUE))
  n_warnings <- sum(grepl("WARNING", audit_log$Result, ignore.case = TRUE))
  cat(sprintf("Audit results: %d FAIL(s), %d WARNING(s)\n", n_fails, n_warnings))
  writeLines(sprintf("Audit: FAILS=%d, WARNINGS=%d", n_fails, n_warnings), con = status_file)

  if (n_fails > 0) {
    stop(sprintf("Audit has %d FAIL(s). Fix source data before proceeding. See %s", n_fails, audit_log_path))
  }

  # 2) Run refactored merge
  cat("\n[STEP 2] Running refactored merge...\n")
  source(file.path(dir_in, "merge_districts_REFACTORED.R"))

  merged_path <- file.path(dir_in, "Merged_Districts_REFACTORED.csv")
  audit_trail_path <- file.path(dir_in, "Merge_Audit_Trail.csv")
  if (!file.exists(merged_path)) stop("Merged output not created: ", merged_path)
  if (!file.exists(audit_trail_path)) stop("Merge audit trail not created: ", audit_trail_path)

  # 3) Build QA summary
  cat("\n[STEP 3] Building QA summary...\n")
  merged <- read_csv(merged_path, show_col_types = FALSE)
  denom_audit <- read_csv(audit_log_path, show_col_types = FALSE)
  merge_audit <- read_csv(audit_trail_path, show_col_types = FALSE)

  # Count rate warnings in merge audit (non-check marks)
  rate_flags <- merge_audit %>% filter(Status != "✓")
  n_rate_flags <- nrow(rate_flags)

  age_missing <- merged %>% filter(is.na(Age_TotalPop)) %>% pull(District)

  qa <- tibble(
    timestamp = Sys.time(),
    districts = nrow(merged),
    cols = ncol(merged),
    audit_fails = n_fails,
    audit_warnings = n_warnings,
    merge_rate_flags = n_rate_flags,
    age_missing_count = length(age_missing),
    age_missing_districts = if (length(age_missing)>0) paste(age_missing, collapse = ";") else ""
  )
  write_csv(qa, qa_file)
  cat(sprintf("QA summary written to: %s\n", qa_file))

  # 4) Optional: Impute ICT Age from Master_Districts.csv (simple imputation)
  if (impute_ict && length(age_missing) > 0) {
    cat("\n[STEP 4] Imputing ICT Age_TotalPop from Master_Districts.csv (documented imputation)\n")
    master <- read_csv(file.path(dir_in, "Master_Districts.csv"), show_col_types = FALSE)
    if (!("District" %in% names(master) && "Pop2023" %in% names(master))) {
      warning("Master_Districts.csv missing expected columns; cannot impute.")
    } else {
      merged2 <- merged %>% left_join(master %>% select(District, Pop2023), by = "District") %>%
        mutate(Age_TotalPop = ifelse(is.na(Age_TotalPop) & District %in% age_missing, Pop2023, Age_TotalPop)) %>%
        select(-Pop2023)
      out_imputed <- file.path(dir_in, "Merged_Districts_REFACTORED_imputed.csv")
      write_csv(merged2, out_imputed)
      cat(sprintf("Imputed merged dataset written to: %s\n", out_imputed))
    }
  }

  writeLines("RUN_ALL: SUCCESS", con = status_file)
  cat("\nRUN_ALL completed successfully. See QA summary and audit logs.\n")

}, error = function(e) {
  msg <- paste(Sys.time(), "ERROR:", conditionMessage(e))
  cat(msg, "\n")
  writeLines(msg, con = status_file)
  stop(e)
})
