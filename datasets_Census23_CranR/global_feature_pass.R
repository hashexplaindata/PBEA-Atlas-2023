# Global Feature Pass: Count-to-Coefficient Normalization & Age Propagation
# Executes Move #1 (Age Cohort Propagation & Dependency Ratio) and
# Move #2 (Normalize Friction & Capability)
# Prepares data for K-Means Clustering by converting variables to 0-1 scales.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
})

# Paths
dir_in <- "C:/Users/Azalas12/Desktop/Census 2023/datasets_Census23_CranR"
dir_main <- "C:/Users/Azalas12/Desktop/Census 2023"
master_file <- file.path(dir_in, "Master_Districts.csv")
age_group_file <- file.path(dir_main, "age-group.csv")
merged_file <- file.path(dir_in, "Merged_Districts_REFACTORED.csv")
out_file <- file.path(dir_in, "Final_PBEA_Atlas_Data.csv")

cat("Starting Global Feature Pass...\n")

# 1. Load data
cat("Loading Merged Districts Data...\n")
if (!file.exists(merged_file)) {
  stop("Merged districts file not found. Please ensure merge_districts_REFACTORED.R has run successfully.")
}
df <- read_csv(merged_file, show_col_types = FALSE)

# 2. Extract Age Data & Calculate Dependency Ratio globally
cat("Processing Age Cohorts & Dependency Ratio...\n")
if (file.exists(age_group_file)) {
  age_df <- read_csv(age_group_file, show_col_types = FALSE)

  # Normalize District names for merging
  age_df <- age_df %>%
    mutate(DistrictKey = toupper(str_trim(District))) %>%
    mutate(DistrictKey = str_replace_all(DistrictKey, "\\s+", " ")) %>%
    mutate(DistrictKey = ifelse(DistrictKey == "ICT", "ISLAMABAD", DistrictKey))

  # Helper to classify age groups
  classify_age <- function(s) {
    s <- toupper(str_trim(s))
    if (str_detect(s, "UNDER\\s*5|5\\s*-\\s*9|10\\s*-\\s*14")) return("Under_15")
    if (str_detect(s, "15\\s*-\\s*19|20\\s*-\\s*24|25\\s*-\\s*29|30\\s*-\\s*34|35\\s*-\\s*39|40\\s*-\\s*44|45\\s*-\\s*49|50\\s*-\\s*54|55\\s*-\\s*59|60\\s*-\\s*64")) return("Working_15_64")
    if (str_detect(s, "65\\s*&\\s*ABOVE|65\\s*\\+|65\\s*ABOVE")) return("Elderly_65_Plus")
    return(NA_character_)
  }

  age_grouped <- age_df %>%
    mutate(BroadAgeGroup = sapply(`Age Group`, classify_age)) %>%
    filter(!is.na(BroadAgeGroup)) %>%
    group_by(DistrictKey, BroadAgeGroup) %>%
    summarise(Pop = sum(`Population Reporting`, na.rm = TRUE), .groups = "drop") %>%
    pivot_wider(names_from = BroadAgeGroup, values_from = Pop, values_fill = 0)

  # Calculate Dependency Ratio
  age_grouped <- age_grouped %>%
    mutate(Dependency_Ratio = ifelse(Working_15_64 > 0, (Under_15 + Elderly_65_Plus) / Working_15_64, NA_real_))

  # Ensure df has a matching DistrictKey
  df <- df %>%
    mutate(DistrictKey = toupper(str_trim(District))) %>%
    mutate(DistrictKey = str_replace_all(DistrictKey, "\\s+", " ")) %>%
    mutate(DistrictKey = ifelse(DistrictKey == "ICT", "ISLAMABAD", DistrictKey))

  # Merge
  df <- left_join(df, age_grouped %>% select(DistrictKey, Dependency_Ratio), by = "DistrictKey")
} else {
  warning("age-group.csv not found. Skipping Global Dependency Ratio calculation.")
  df$Dependency_Ratio <- NA_real_
}

# 3. Normalize Friction (FCI) - convert counts to 0-1 rates
cat("Normalizing Friction (Opportunity / FCI)...\n")
# Assuming standard naming conventions based on the merged file output
# Check and calculate Sanitation Rate
if (all(c("San_TOILET_FLUSH", "San_HOUSEHOLDS") %in% names(df))) {
  df <- df %>% mutate(Friction_Sanitation_Rate = ifelse(San_HOUSEHOLDS > 0, San_TOILET_FLUSH / San_HOUSEHOLDS, NA_real_))
}
# Check and calculate Energy Rate
if (all(c("Energy_LIGHT_ELECT", "Energy_HOUSEHOLDS") %in% names(df))) {
  df <- df %>% mutate(Friction_Energy_Rate = ifelse(Energy_HOUSEHOLDS > 0, Energy_LIGHT_ELECT / Energy_HOUSEHOLDS, NA_real_))
}
# Check and calculate Water Rate
if (all(c("Wtr_DRINK_WTR_IMPROVE", "Wtr_HOUSEHOLDS") %in% names(df))) {
  df <- df %>% mutate(Friction_Water_Rate = ifelse(Wtr_HOUSEHOLDS > 0, Wtr_DRINK_WTR_IMPROVE / Wtr_HOUSEHOLDS, NA_real_))
}

# Apply capping and warnings (Rule 2.1 Exception handling)
check_and_cap <- function(data, col_name) {
  if (col_name %in% names(data)) {
    bad_idx <- which(!is.na(data[[col_name]]) & data[[col_name]] > 1.0)
    if (length(bad_idx) > 0) {
      for (i in bad_idx) {
        cat(sprintf("LOUD WARNING: %s > 1.0 in %s (%.3f). Capping at 1.0.\n", col_name, data$District[i], data[[col_name]][i]))
      }
      data[[col_name]][bad_idx] <- 1.0
    }
  }
  return(data)
}
df <- check_and_cap(df, "Friction_Sanitation_Rate")
df <- check_and_cap(df, "Friction_Energy_Rate")
df <- check_and_cap(df, "Friction_Water_Rate")

# 4. Normalize Capability (CI)
cat("Normalizing Capability (CI)...\n")
# Literacy 01
if (all(c("Lit_GE10", "Pop_GE10") %in% names(df))) {
  df <- df %>% mutate(Literacy_01 = ifelse(Pop_GE10 > 0, Lit_GE10 / Pop_GE10, NA_real_))
  df <- check_and_cap(df, "Literacy_01")

  # Min-Max Normalization (Rule 3.1)
  lit_min <- min(df$Literacy_01, na.rm = TRUE)
  lit_max <- max(df$Literacy_01, na.rm = TRUE)
  if (lit_max > lit_min) {
    df <- df %>% mutate(Literacy_Norm_01 = (Literacy_01 - lit_min) / (lit_max - lit_min))
  } else {
    df$Literacy_Norm_01 <- df$Literacy_01
  }
}

# Disability
if (all(c("Disab_Disability", "Disab_Population") %in% names(df))) {
  df <- df %>% mutate(Capability_Physical_Rate = ifelse(Disab_Population > 0, 1 - (Disab_Disability / Disab_Population), NA_real_))
  df <- check_and_cap(df, "Capability_Physical_Rate")
} else if (all(c("Disab_TOTAL", "Pop2023") %in% names(df))) {
   # Fallback if specific disab cols are missing but totals exist
   df <- df %>% mutate(Capability_Physical_Rate = ifelse(Pop2023 > 0, 1 - (Disab_TOTAL / Pop2023), NA_real_))
   df <- check_and_cap(df, "Capability_Physical_Rate")
}

# 5. Output
cat("Writing finalized feature matrix to:", out_file, "\n")
write_csv(df, out_file)
cat("Global Feature Pass Complete. Data is ready for K-Means Clustering.\n")
