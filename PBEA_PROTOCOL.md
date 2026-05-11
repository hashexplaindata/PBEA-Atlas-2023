# PBEA PROTOCOL: Formal Research Rules & Causal Mandate

**Project:** Pakistan Behavioral Environment Atlas (PBEA) 2023  
**Status:** Preregistered (OSF-Compliant)  
**Version:** 2.1 (Refactored)  

## 1. THE CAUSAL CONSTITUTION (COM-B)
Every variable in this study must map to the Causal Gearbox. If a variable does not represent a physical barrier or a cognitive capacity, it is "Superstitious Noise" and must be purged.

* **Opportunity (FCI):** Structural/Environmental resistance. Metric: Proportion of Household Deprivation.
* **Capability (CI):** Human processing potential. Metric: Normalized Cognitive & Physical Proxies.
* **Motivation (SLII):** Life-stage inertia. Metric: Demographic Social Gravity.

## 2. DATA GOVERNANCE: THE THREE-LAYER INTEGRITY MODEL
These rules are hardcoded into the R/Python pipeline. Overriding them without a DOI update is a scientific integrity violation.

### Rule 2.1: The Denominator Anchor
* **MANDATE:** No raw counts are permitted in the final analysis.
* **PROTOCOL:** Numerators must be anchored to their table-specific denominators in the same extraction row.
  * Infrastructure (Gas/Water/Electricity): $\div$ Households.
  * Literacy/Language/Disability: $\div$ Total Population (or age-specific population $\ge 10$).
* **EXCEPTION:** If any rate is $> 1.0$, the district is flagged. If the error persists after checking the R-source, the district is Terminated from the cluster analysis.

### Rule 2.2: The Geographic Firewall
* **SCOPE:** "Four-Province Behavioral Atlas."
* **BOUNDARIES:** Punjab, Sindh, KPK, Balochistan, and ICT (Islamabad).
* **EXCLUSIONS:** AJK and GB are excluded due to enumeration boundary drift. We do not speculate on missing districts to preserve the $\alpha = 0.05$ integrity.

### Protocol Note 2.4 (The ICT Patch)
"Protocol Note 2.4 (The ICT Patch): While the 135 provincial districts are processed via the PakPC2023 R-package, the Islamabad Capital Territory (ICT) was found to be siloed in the source tables. To maintain Atlas continuity, ICT’s total population and elderly dependency counts (65+) were sourced from the Gallup Pakistan 2023 Digital Census Dashboard. To maintain parity with the Youth Bulge (15–29) metric used in the SLII, a twin-city proxy ratio (Rawalpindi) was applied to the ICT total count. This hybrid approach ensures 100% geographic coverage of the four provinces and the capital without compromising the causal integrity of the indices."

### Rule 2.3: The Loud Warning Protocol
* **THRESHOLD:** String-distance matching (Jaro-Winkler) limit = 0.15.
* **ACTION:** Any distance $> 0.15$ triggers a STOP command. Manual aliasing is only permitted via the DistrictKey override in the Master_Districts.csv.

## 3. STATISTICAL MANDATES (APA 7 COMPLIANT)

### Rule 3.1: The H2 Scale Fix
* **BRUTAL REALITY:** Raw percentages (%) and Indices ($0-1$) are mathematically incompatible for paired analysis.
* **RULE:** The Literacy Rate MUST be Min-Max Normalized to the $0-1$ range before calculation of the Capability Index ($CI$) or performing the H2 paired t-test.

### Rule 3.2: CAPS Calculation (Cognitive Tax)
* **FORMULA:** $CAPS = Literacy_{Norm} \times (1 - LIAS)$
* **LIAS PROXY:** $Language\_Urdu / Language\_Total$.
* **LOGIC:** Districts where the primary tongue does not align with the language of instruction (Urdu) incur a "Cognitive Penalty" that suppresses behavioral adoption.

### Rule 3.3: K-Means Unsupervised Learning
* **INITIALIZATION:** n_init = 50.
* **VALIDATION:** The number of clusters ($k$) is determined by the Elbow Method and Silhouette Score. Pre-defining $k$ based on "Provinces" is prohibited confirmation bias.

## 4. EXCEPTION HANDLING & FALLBACKS

| Scenario | Rule-Based Action |
| :--- | :--- |
| **Missing Internet Data** | **Proxy Rule:** Use Electricity_Access as the primary digital opportunity proxy. Document as a limitation. |
| **Missing GB/AJK** | **Label Rule:** Title all visualizations "Four-Province Atlas." Do not use "National." |
| **Cluster Overlap** | **Stability Rule:** If Silhouette Score $< 0.4$, re-normalize inputs and re-run with outliers removed. |

## 5. PUBLICATION & REPRODUCIBILITY
* **Psych-DS:** All exports must include a dataset_description.json.
* **APA 7:** Report $p$-values to 3 decimal places; report Cohen's $d$ for all t-tests.
* **OSF:** All audit logs from PHASE1_AUDIT.R must be uploaded to the OSF project as "Supplemental Materials."

***
  **BY ORDER OF THE LEAD RESEARCHER-Behaviroural Data Scientist**