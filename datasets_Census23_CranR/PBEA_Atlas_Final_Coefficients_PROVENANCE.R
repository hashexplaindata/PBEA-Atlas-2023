# PBEA Atlas Final Coefficients — Reproducibility & Traceability
#
# This file stores the exact ICT reconstruction logic used to create
# or repair the final atlas coefficients dataset.
#
# Primary dataset:
#   PBEA_Atlas_Final_Coefficients.csv
#
# Provenance note:
#   Keep this file alongside the CSV for auditability and reproducibility.

# --- REPRODUCIBLE ICT PATCH PROTOCOL ---
ict_idx <- which(df$DistrictKey == "ICT")

# 1. Apply anchors from Master Spine and Gallup
df$Age_TotalPop[ict_idx]  <- 2363863
df$Age_65_Plus[ict_idx]   <- 98000
df$Under15[ict_idx]       <- 787629  # Verified Gallup Under-15 count

# 2. Apply the Twin-City Proxy (Rawalpindi Floor)
df$Age_15_29[ict_idx]     <- 2363863 * 0.25

# 3. Algebraically close the loop for 100% sum integrity
df$Age_15_64[ict_idx]     <- df$Age_TotalPop[ict_idx] - df$Under15[ict_idx] - df$Age_65_Plus[ict_idx]
df$Age_30_64[ict_idx]     <- df$Age_15_64[ict_idx] - df$Age_15_29[ict_idx]

# 4. Final Sanity Check: Ratio Calculation
df$Dependency_Ratio[ict_idx] <- (df$Under15[ict_idx] + df$Age_65_Plus[ict_idx]) / df$Age_15_64[ict_idx]
# Result should be ~0.599

# Optional reproducibility note:
# If this logic is used in a pipeline, ensure the final artifact records:
#   - source of Age_TotalPop (Master Spine)
#   - source of Age_65_Plus (Gallup / exact bin if available)
#   - the conservative Youth Bulge floor for Age_15_29
#   - dependency-ratio formula and any sanity gates
