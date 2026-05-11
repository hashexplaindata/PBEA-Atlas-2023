suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr); library(tidyr)
})

dir_in  <- "C:/Users/Azalas12/Desktop/Census 2023/datasets_Census23_CranR"
out_csv <- file.path(dir_in, "ICT_Age_Reconstruction.csv")

ICT_TOTAL <- 2363863   # ICT Age_TotalPop (given)

# --- Load SLII_Age_Bulge, isolate Rawalpindi district ---
slii <- read_csv(file.path(dir_in, "SLII_Age_Bulge.csv"), show_col_types = FALSE) |>
  mutate(DIST_KEY = str_squish(str_to_upper(DISTRICT))) |>
  filter(DIST_KEY == "RAWALPINDI")

# Aggregate tehsil rows to district level, per bin
pindi_bins <- slii |>
  group_by(BIN = SEX_AGE_GROUP_IN_YEARS) |>
  summarise(
    BOTH = sum(ALL_SEXES_OVERALL, na.rm = TRUE),
    MALE = sum(MALE_OVERALL,      na.rm = TRUE),
    FEM  = sum(FEMALE_OVERALL,    na.rm = TRUE),
    .groups = "drop"
  )

# Helper: pull BOTH for a named bin (fallback to MALE+FEMALE if BOTH is missing/0)
b <- function(bin_name) {
  r <- pindi_bins |> filter(str_squish(BIN) == bin_name)
  if (nrow(r) == 0) return(NA_real_)
  if (r$BOTH > 0) r$BOTH else (r$MALE + r$FEM)
}

# Available bins for Rawalpindi
cat("=== Rawalpindi bins available in SLII_Age_Bulge ===\n")
print(pindi_bins, n = Inf)

T      <- b("ALL AGES")
U5     <- b("UNDER 5")
U15    <- b("UNDER 15")
A0524  <- b("05 - 24")
A1549  <- b("15 - 49")
A1564  <- b("15 - 64")
A65    <- b("65 & ABOVE")   # source has 2 spaces, but we str_squish on lookup

cat(sprintf("\nRawalpindi totals:\n  ALL AGES  = %s\n  UNDER 5   = %s\n  UNDER 15  = %s\n  05-24     = %s\n  15-49     = %s\n  15-64     = %s\n  65+       = %s\n",
            format(T, big.mark=","), format(U5, big.mark=","),
            format(U15, big.mark=","), format(A0524, big.mark=","),
            format(A1549, big.mark=","), format(A1564, big.mark=","),
            format(A65, big.mark=",")))

# --- Derived non-overlapping cohorts (algebra, no estimation) ---
# 5-14 = UNDER 15 - UNDER 5
# 15-24 = (5-24) - (5-14)
# 25-49 = (15-49) - (15-24)
# 50-64 = (15-64) - (15-49)
A0514 <- U15 - U5
A1524 <- A0524 - A0514
A2549 <- A1549 - A1524
A5064 <- A1564 - A1549

cat(sprintf("\nDerived (EXACT) non-overlapping bins for Rawalpindi:\n  Under 15  = %s\n  15-24     = %s\n  25-49     = %s\n  50-64     = %s\n  65+       = %s\n  ---- sum  = %s  (vs ALL AGES = %s)\n",
            format(U15, big.mark=","), format(A1524, big.mark=","),
            format(A2549, big.mark=","), format(A5064, big.mark=","),
            format(A65, big.mark=","),
            format(U15+A1524+A2549+A5064+A65, big.mark=","),
            format(T, big.mark=",")))

# --- 15-29 reconstruction ---
# WARNING: source has no 5-year cohorts. 15-24 is exact; 25-29 must be
# estimated. Assumption: ages are uniformly distributed within 25-49.
# Under that assumption, 25-29 = 5/25 * (25-49) = 0.20 * (25-49).
A2529_est <- 0.20 * A2549
A1529_est <- A1524 + A2529_est

# Also: 30-49 = 0.80 * (25-49) under the same assumption;
# so 30-64 = 30-49 + 50-64
A3049_est <- 0.80 * A2549
A3064_est <- A3049_est + A5064

# --- Ratio + sanity check ---
Pindi_15_29_Ratio <- A1529_est / T

cat(sprintf("\nPindi_15_29_Ratio (estimated) = %.4f\n", Pindi_15_29_Ratio))

if (Pindi_15_29_Ratio > 0.50) {
  stop(sprintf("SANITY CHECK FAILED: Pindi_15_29_Ratio = %.4f > 0.50",
               Pindi_15_29_Ratio))
}
if (Pindi_15_29_Ratio < 0.25 || Pindi_15_29_Ratio > 0.35) {
  warning(sprintf("Pindi_15_29_Ratio = %.4f is outside the expected [0.25, 0.35] band (but <= 0.50, so not stopping).",
                  Pindi_15_29_Ratio))
} else {
  cat("Sanity check passed: ratio is within [0.25, 0.35].\n")
}

# --- Apply Rawalpindi ratios to ICT ---
ICT_Under15 <- ICT_TOTAL * (U15   / T)
ICT_15_29   <- ICT_TOTAL *  Pindi_15_29_Ratio
ICT_30_64   <- ICT_TOTAL * (A3064_est / T)
ICT_65_plus <- ICT_TOTAL * (A65   / T)

stack_sum <- ICT_Under15 + ICT_15_29 + ICT_30_64 + ICT_65_plus

cat(sprintf("\n=== ICT reconstruction (applied ratios x %s) ===\n",
            format(ICT_TOTAL, big.mark=",")))
cat(sprintf("  Under 15  = %s\n  15-29     = %s\n  30-64     = %s\n  65+       = %s\n  -- sum    = %s  (vs Age_TotalPop = %s)\n",
            format(round(ICT_Under15), big.mark=","),
            format(round(ICT_15_29),   big.mark=","),
            format(round(ICT_30_64),   big.mark=","),
            format(round(ICT_65_plus), big.mark=","),
            format(round(stack_sum),   big.mark=","),
            format(ICT_TOTAL,          big.mark=",")))

# Integrity rule: stacked bins must not exceed Age_TotalPop
if (stack_sum > ICT_TOTAL * 1.001) {  # 0.1% rounding tolerance
  stop(sprintf("INTEGRITY FAIL: sum of bins (%s) > Age_TotalPop (%s)",
               format(round(stack_sum), big.mark=","),
               format(ICT_TOTAL,        big.mark=",")))
} else {
  cat("Integrity rule passed: stacked bins <= Age_TotalPop (within rounding).\n")
}

# --- Persist results ---
out <- tibble::tibble(
  District       = c("Rawalpindi", "ICT"),
  Age_TotalPop   = c(T,                        ICT_TOTAL),
  Under_15       = c(U15,                      round(ICT_Under15)),
  Age_15_24_exact= c(A1524,                    NA_real_),
  Age_15_29_est  = c(round(A1529_est),         round(ICT_15_29)),
  Age_30_64_est  = c(round(A3064_est),         round(ICT_30_64)),
  Age_65_plus    = c(A65,                      round(ICT_65_plus)),
  Ratio_15_29    = c(Pindi_15_29_Ratio,        Pindi_15_29_Ratio),
  Source_Method  = c("R-source SLII_Age_Bulge (algebraic derivation + uniform 25-49 assumption)",
                     "Rawalpindi 15-29 ratio applied to ICT total")
)

write_csv(out, out_csv)
cat(sprintf("\nWrote %s\n", out_csv))
