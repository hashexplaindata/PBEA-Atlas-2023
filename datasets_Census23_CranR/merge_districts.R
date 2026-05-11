suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(stringr); library(purrr)
})

dir_in  <- "C:/Users/Azalas12/Desktop/Census 2023/datasets_Census23_CranR"
out_csv <- file.path(dir_in, "Merged_Districts.csv")

# District key: uppercase + trim + alias (ICT <-> ISLAMABAD)
norm_dist <- function(x) {
  k <- str_squish(str_to_upper(x))
  k <- ifelse(k == "ICT", "ISLAMABAD", k)
  k <- ifelse(k == "MALAKAND PROTECTED AREA", "MALAKAND", k)
  k
}

# --- Spine ---
spine <- read_csv(file.path(dir_in, "Master_Districts.csv"),
                  show_col_types = FALSE) |>
  select(-any_of("...1")) |>
  rename(Province = Region) |>
  mutate(DistrictKey = norm_dist(District))

# --- CI_Disability: pivot wide on DISAB_FUNC_LIM ---
disab <- read_csv(file.path(dir_in, "CI_Disability.csv"),
                  show_col_types = FALSE) |>
  mutate(DistrictKey = norm_dist(DISTRICT)) |>
  group_by(DistrictKey, DISAB_FUNC_LIM) |>
  summarise(n = sum(ALL_SEXES_OVERALL, na.rm = TRUE), .groups = "drop") |>
  pivot_wider(names_from = DISAB_FUNC_LIM, values_from = n,
              names_prefix = "Disab_", values_fill = 0) |>
  rename_with(~ str_replace_all(.x, "[ /]+", "_"))

# --- CI_Language_Spine: pivot wide on LANGUAGE ---
lang <- read_csv(file.path(dir_in, "CI_Language_Spine.csv"),
                 show_col_types = FALSE) |>
  mutate(DistrictKey = norm_dist(DISTRICT)) |>
  group_by(DistrictKey, LANGUAGE) |>
  summarise(n = sum(ALL_SEXES_OVERALL, na.rm = TRUE), .groups = "drop") |>
  pivot_wider(names_from = LANGUAGE, values_from = n,
              names_prefix = "Lang_", values_fill = 0)

# --- CI_Literacy_Attendance: sum counts to district, recompute Literacy on 0-1 ---
lit_long <- read_csv(file.path(dir_in, "CI_Literacy_Attendance.csv"),
                     show_col_types = FALSE) |>
  mutate(DistrictKey = norm_dist(DISTRICT)) |>
  filter(VARS %in% c("Population >=10", "Literate >=10",
                     "Population >=5", "Ever Attended",
                     "Out of School Children (5-16)")) |>
  group_by(DistrictKey, VARS) |>
  summarise(n = sum(ALL_SEXES_OVERALL, na.rm = TRUE), .groups = "drop") |>
  pivot_wider(names_from = VARS, values_from = n)

lit <- lit_long |>
  rename(Pop_GE10 = `Population >=10`,
         Lit_GE10 = `Literate >=10`,
         Pop_GE5  = `Population >=5`,
         EverAttended = `Ever Attended`,
         OutOfSchool_5_16 = `Out of School Children (5-16)`) |>
  mutate(
    # H2 fix: scale Literacy to 0-1 (was 0-100 in source as percent)
    Literacy_01 = ifelse(Pop_GE10 > 0, Lit_GE10 / Pop_GE10, NA_real_),
    EverAttend_01 = ifelse(Pop_GE5 > 0, EverAttended / Pop_GE5, NA_real_)
  )

# --- FCI tables: OVERALL only, sum to district ---
sum_fci <- function(file, cols, prefix) {
  read_csv(file.path(dir_in, file), show_col_types = FALSE) |>
    filter(REGION == "OVERALL") |>
    mutate(DistrictKey = norm_dist(DISTRICT)) |>
    group_by(DistrictKey) |>
    summarise(across(all_of(cols), ~ sum(.x, na.rm = TRUE)), .groups = "drop") |>
    rename_with(~ paste0(prefix, .x), -DistrictKey)
}

energy <- sum_fci("FCI_Energy_Fuel.csv",
  c("HOUSEHOLDS","LIGHT_ELECT","LIGHT_SOLAR","LIGHT_OTHERS",
    "FUEL_GAS","FUEL_LPGCNG","FUEL_FIREWOOD","FUEL_OTHERS",
    "SEP_KITCHEN","NO_KITCHEN"), "Energy_")

sanit  <- sum_fci("FCI_Sanitation_Structure.csv",
  c("HOUSEHOLDS","TOILET_SEPARATE","TOILET_FLUSH","TOILET_NON_FLUSH",
    "TOILET_NONE","WASHROOM_SEPARATE","WASHROOM_NONE"), "San_")

water  <- sum_fci("FCI_Water.csv",
  c("HOUSEHOLDS","DRINK_WTR_IMPROVE","DRINK_WTR_INSIDE","DRINK_WTR_OUTSIDE",
    "DRINK_WTR_TAP","DRINK_WTR_MOTOR","DRINK_WTR_WELL",
    "DRINK_WTR_FILTER","DRINK_WTR_BOTTLE","DRINK_WTR_OTHER"), "Wtr_")

# --- SLII_Age_Bulge: keep ALL AGES summary row ---
age <- read_csv(file.path(dir_in, "SLII_Age_Bulge.csv"),
                show_col_types = FALSE) |>
  mutate(DistrictKey = norm_dist(DISTRICT)) |>
  filter(SEX_AGE_GROUP_IN_YEARS == "ALL AGES") |>
  group_by(DistrictKey) |>
  summarise(
    Age_TotalPop  = sum(ALL_SEXES_OVERALL, na.rm = TRUE),
    Age_Male      = sum(MALE_OVERALL,      na.rm = TRUE),
    Age_Female    = sum(FEMALE_OVERALL,    na.rm = TRUE),
    Age_Trans     = sum(TRANSGENDER_OVERALL, na.rm = TRUE),
    Age_Rural     = sum(ALL_SEXES_RURAL,   na.rm = TRUE),
    Age_Urban     = sum(ALL_SEXES_URBAN,   na.rm = TRUE),
    .groups = "drop"
  )

# --- SLII_Marital_Status: already at DISTRICT, pivot wide ---
marital <- read_csv(file.path(dir_in, "SLII_Marital_Status.csv"),
                    show_col_types = FALSE) |>
  mutate(DistrictKey = norm_dist(DISTRICT)) |>
  filter(str_squish(AGE_GROUP) == "15 & ABOVE") |>
  group_by(DistrictKey, MARITAL_STATUS) |>
  summarise(n = sum(ALL_SEXES_OVERALL, na.rm = TRUE), .groups = "drop") |>
  pivot_wider(names_from = MARITAL_STATUS, values_from = n,
              names_prefix = "Marital_", values_fill = 0) |>
  rename_with(~ str_replace_all(.x, "[ /]+", "_"))

# --- Join everything onto the spine ---
merged <- spine |>
  left_join(disab,   by = "DistrictKey") |>
  left_join(lang,    by = "DistrictKey") |>
  left_join(lit,     by = "DistrictKey") |>
  left_join(energy,  by = "DistrictKey") |>
  left_join(sanit,   by = "DistrictKey") |>
  left_join(water,   by = "DistrictKey") |>
  left_join(age,     by = "DistrictKey") |>
  left_join(marital, by = "DistrictKey")

# --- Diagnostics ---
n_spine <- nrow(spine)
unmatched_in_spine <- merged |>
  filter(is.na(Disab_Population) & is.na(Energy_HOUSEHOLDS)) |>
  pull(District)

src_keys <- unique(c(disab$DistrictKey, lang$DistrictKey, lit$DistrictKey,
                     energy$DistrictKey, sanit$DistrictKey, water$DistrictKey,
                     age$DistrictKey, marital$DistrictKey))
unmatched_in_source <- setdiff(src_keys, spine$DistrictKey)

cat(sprintf("Spine districts: %d\n", n_spine))
cat(sprintf("Output rows: %d  |  cols: %d\n", nrow(merged), ncol(merged)))
cat(sprintf("Spine districts with no tributary match: %d\n",
            length(unmatched_in_spine)))
if (length(unmatched_in_spine)) print(unmatched_in_spine)
cat(sprintf("Source district keys absent from spine: %d\n",
            length(unmatched_in_source)))
if (length(unmatched_in_source)) print(unmatched_in_source)

# Literacy sanity check (should be 0-1)
cat("\nLiteracy_01 summary (should be in [0,1]):\n")
print(summary(merged$Literacy_01))

write_csv(merged, out_csv)
cat(sprintf("\nWrote %s\n", out_csv))
