*===========================
* NOPD Use-of-Force: Clean + Intensity DiD
* Outcomes: Severity (1–4), Subject Hospitalized, Firearm Discharged
*===========================

clear all
set more off
capture ssc install estout

*---------------------------
* 0) Working directory
*---------------------------
cd "C:\Users\lhernandezlyons\OneDrive - Tulane University\PECN 6200 Summer Work"

*---------------------------
* 1) Import data
*---------------------------
import excel "Use of Force.xlsx", sheet("Data") firstrow clear
describe
list in 1/10

*---------------------------
* 2) Standardize variable names (only what we use)
*---------------------------
rename PIBFileNumber         pib_file_number
rename DateOccurred          date_occurred
rename UseofForceType        uof_type
rename UseofForceLevel       uof_level
rename OfficerRaceEthnicity  officer_race_eth
rename OfficerGender         officer_gender
rename OfficerAge            officer_age
rename SubjectGender         subject_gender
rename SubjectEthnicity      subject_ethnicity
rename SubjectAge            subject_age
rename SubjectHospitalized   subject_hosp
rename SubjectArrested       subject_arrested
rename UseofForceReason      uof_reason

*---------------------------
* 3) Dates (Excel dates already numeric)
*---------------------------
gen day = date_occurred
format day %td
gen m = mofd(day)
format m %tm
gen year = year(day)

*---------------------------
* 4) Outcomes + controls
*---------------------------
* Severity (1–4) parsed directly from "L1", "L2", "L3", "L4" without flags
gen byte severity = .
replace severity = real(regexs(1)) if regexm(uof_level, "L([1-4])")
label define sev 1 "L1" 2 "L2" 3 "L3" 4 "L4"
label values severity sev

* Subject Hospitalized (yes/no -> 1/0)
gen byte hosp = .
replace hosp = 1 if strpos(lower(subject_hosp), "yes")
replace hosp = 0 if strpos(lower(subject_hosp), "no")

* Firearm Discharged: only the discharge (not exhibited)
gen byte fire = (strpos(uof_type, "Firearm (Discharged)")>0)

* Officer demographics
gen officer_black  = strpos(officer_race_eth, "Black")>0
gen officer_white  = strpos(officer_race_eth, "White")>0
gen officer_hisp   = strpos(officer_race_eth, "Hispanic")>0
gen officer_male   = strpos(officer_gender, "Male")>0
gen officer_female = strpos(officer_gender, "Female")>0

* Subject demographics
gen subject_black  = strpos(subject_ethnicity, "Black")>0
gen subject_white  = strpos(subject_ethnicity, "White")>0
gen subject_hisp   = strpos(subject_ethnicity, "Hispanic")>0
gen subject_male   = strpos(subject_gender, "Male")>0
gen subject_female = strpos(subject_gender, "Female")>0

* Force reason FE
encode uof_reason, gen(force_reason)

*---------------------------
* 5) Reform timing + event-month exclusions
*---------------------------
* ===========================
* Event months (already using these)
* ===========================
local ev2018 = tm(2018m5)
local ev2020 = tm(2020m12)
local ev2022 = tm(2022m11)

* ---------------------------
* Short-run: first 12 months after each reform
* ---------------------------
gen byte post2018_yr1 = inrange(m, `ev2018', `ev2018' + 11)
gen byte post2020_yr1 = inrange(m, `ev2020', `ev2020' + 11)
gen byte post2022_yr1 = inrange(m, `ev2022', `ev2022' + 11)

label var post2018_yr1 "1st year after 2018 reform"
label var post2020_yr1 "1st year after 2020 reform"
label var post2022_yr1 "1st year after 2022 reform"

* ---------------------------
* Long-run: stays 1 after each reform
* (use NEW names so we don't overwrite anything)
* ---------------------------
gen byte post2018_long = (m >= `ev2018')
gen byte post2020_long = (m >= `ev2020')
gen byte post2022_long = (m >= `ev2022')

label var post2018_long "Post-2018 (long-run)"
label var post2020_long "Post-2020 (long-run)"
label var post2022_long "Post-2022 (long-run)"

*---------------------------
* 6) Single baseline (pre-2018) by District
*    Window: 2016m1–2018m4
*---------------------------
gen byte prewin18 = inrange(m, tm(2016m1), tm(2018m4))

preserve
    keep if prewin18 & !missing(District, severity)
    collapse (mean) sev_pre2018 = severity, by(District)
    tempfile sev18
    save `sev18'
restore
merge m:1 District using `sev18', keep(match master) nogen

preserve
    keep if prewin18 & !missing(District, hosp)
    collapse (mean) hosp_pre2018 = hosp, by(District)
    tempfile hosp18
    save `hosp18'
restore
merge m:1 District using `hosp18', keep(match master) nogen

preserve
    keep if prewin18 & !missing(District, fire)
    collapse (mean) fire_pre2018 = fire, by(District)
    tempfile fire18
    save `fire18'
restore
merge m:1 District using `fire18', keep(match master) nogen

* Standardize baselines (effect sizes per 1 SD)
egen sev_pre2018_z  = std(sev_pre2018)
egen hosp_pre2018_z = std(hosp_pre2018)
egen fire_pre2018_z = std(fire_pre2018)

label var sev_pre2018_z  "Baseline severity z (pre-2018)"
label var hosp_pre2018_z "Baseline hospitalized z (pre-2018)"
label var fire_pre2018_z "Baseline firearm discharge z (pre-2018)"

* Analysis sample: keep obs with valid baseline + core vars
keep if !missing(District, m, year, severity, hosp, fire, ///
                 sev_pre2018_z, hosp_pre2018_z, fire_pre2018_z)

*---------------------------
* 7) Summary stats (for Results section)
*---------------------------
capture ssc install estout
estpost summarize severity hosp fire post2018_yr1 post2020_yr1 post2022_yr1 ///
    sev_pre2018_z hosp_pre2018_z fire_pre2018_z
esttab using "summary_stats.rtf", ///
    cells("mean sd min max count") label replace ///
    title("Summary statistics")

*===========================
* 8) MAIN REGRESSIONS — SEVERITY
*    Five columns: stepwise controls → preferred spec
*===========================
ssc install ftools, replace

cap which reghdfe
if _rc ssc install reghdfe, replace
ssc install estout, replace

eststo clear

* ===========================
* SHORT-RUN MAIN RESULTS (Table 1)
* ===========================

* Control blocks
local officerCtrls  officer_black officer_white officer_hisp officer_male officer_female
local subjectCtrls  subject_black subject_white subject_hisp subject_male subject_female
local situational   i.force_reason

eststo clear

*--------------------------------------------
* Baseline mean severity by district (pre-2018)
*--------------------------------------------
preserve

    keep District sev_pre2018
    duplicates drop

    label var sev_pre2018 "Mean Severity (1–4), Pre-2018"

    graph hbar sev_pre2018, over(District, sort(sev_pre2018) descending label(labsize(medium))) ///
        blabel(bar, format(%3.2f) color(black) size(medium)) ///
        bar(1, fcolor(navy*0.4) lcolor(navy)) ///
        ytitle("Mean severity (1 = L1, 4 = L4)") ///
        title("Baseline Mean Use-of-Force Severity by District (Pre-2018)") ///
        legend(off)

restore







*---------------------------
* Baseline mean severity by district (pre-2018)
*---------------------------
preserve

    keep District sev_pre2018
    duplicates drop

    label var sev_pre2018 "Mean severity (L1–L4), pre-2018"

    graph hbar sev_pre2018, over(District, ///
        sort(sev_pre2018) descending ///
        label(labsize(medlarge))) ///
        bargap(20) ///
        blabel(bar, format(%3.2f) position(outside) size(medsmall)) ///
        ytitle("") ///
        xtitle("Mean severity (1–4)") ///
        title("Baseline Mean Use-of-Force Severity by District (Pre-2018)") ///
        legend(off)

restore




*---------------------------
* Option 2: Baseline severity z-score by district
*---------------------------
preserve

    keep District sev_pre2018_z
    duplicates drop

    label var sev_pre2018_z "Baseline severity (z-score, pre-2018)"

    graph dot sev_pre2018_z, over(District, ///
        sort(sev_pre2018_z)) ///
        yline(0, lpattern(dash)) ///
        title("Baseline Severity (z-score) by District (Pre-2018)") ///
        ytitle("Baseline severity (standardized)")

restore
*---------------------------
* Option 1: Baseline mean severity by district (pre-2018)
*---------------------------
preserve

    * Keep one row per district with the baseline mean
    keep District sev_pre2018
    duplicates drop

    label var sev_pre2018 "Mean severity (L1–L4), pre-2018"

    graph bar sev_pre2018, over(District, ///
        sort(sev_pre2018) descending) ///
        ytitle("Mean severity (1 = L1, 4 = L4)") ///
        title("Baseline Mean Use-of-Force Severity by District (Pre-2018)") ///
        bar(1, outlinecolor(black))

restore










* (1) No controls
reghdfe severity ///
    c.post2018_yr1#c.sev_pre2018_z ///
    c.post2020_yr1#c.sev_pre2018_z ///
    c.post2022_yr1#c.sev_pre2018_z ///
    , absorb(District m) vce(cluster District)
eststo s1_short

* (2) + Officer controls
reghdfe severity ///
    c.post2018_yr1#c.sev_pre2018_z ///
    c.post2020_yr1#c.sev_pre2018_z ///
    c.post2022_yr1#c.sev_pre2018_z ///
    `officerCtrls' ///
    , absorb(District m) vce(cluster District)
eststo s2_short

* (3) + Officer + Subject controls
reghdfe severity ///
    c.post2018_yr1#c.sev_pre2018_z ///
    c.post2020_yr1#c.sev_pre2018_z ///
    c.post2022_yr1#c.sev_pre2018_z ///
    `officerCtrls' `subjectCtrls' ///
    , absorb(District m) vce(cluster District)
eststo s3_short

* (4) + Force reason FE
reghdfe severity ///
    c.post2018_yr1#c.sev_pre2018_z ///
    c.post2020_yr1#c.sev_pre2018_z ///
    c.post2022_yr1#c.sev_pre2018_z ///
    `officerCtrls' `subjectCtrls' `situational' ///
    , absorb(District m) vce(cluster District)
eststo s4_short

* (5) Full model (same as 4, just labeled as main)
reghdfe severity ///
    c.post2018_yr1#c.sev_pre2018_z ///
    c.post2020_yr1#c.sev_pre2018_z ///
    c.post2022_yr1#c.sev_pre2018_z ///
    `officerCtrls' `subjectCtrls' `situational' ///
    , absorb(District m) vce(cluster District)
eststo s5_short

* Export short-run table (coeffs + p-values)
esttab s1_short s2_short s3_short s4_short s5_short using "table1_short_run_severity.rtf", replace ///
    b(%9.3f) p(%9.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(c.post2018_yr1#c.sev_pre2018_z ///
         c.post2020_yr1#c.sev_pre2018_z ///
         c.post2022_yr1#c.sev_pre2018_z) ///
    order(c.post2018_yr1#c.sev_pre2018_z ///
          c.post2020_yr1#c.sev_pre2018_z ///
          c.post2022_yr1#c.sev_pre2018_z) ///
    mtitles("No controls" "+ Officer" "+ Officer + Subject" "+Force reason" "Full model") ///
    title("Short-run effects: First year after each reform (severity, z)") ///
    addnotes("District & month FE absorbed; SE clustered by District" ///
             "Post dummies equal 1 only in first 12 months after each reform" ///
             "p-values in parentheses; * p<0.10, ** p<0.05, *** p<0.01")

* ===========================
* LONG-RUN RESULTS 
* ===========================

eststo clear

* (1) No controls
reghdfe severity ///
    c.post2018_long#c.sev_pre2018_z ///
    c.post2020_long#c.sev_pre2018_z ///
    c.post2022_long#c.sev_pre2018_z ///
    , absorb(District m) vce(cluster District)
eststo l1_long

* (2) + Officer controls
reghdfe severity ///
    c.post2018_long#c.sev_pre2018_z ///
    c.post2020_long#c.sev_pre2018_z ///
    c.post2022_long#c.sev_pre2018_z ///
    `officerCtrls' ///
    , absorb(District m) vce(cluster District)
eststo l2_long

* (3) + Officer + Subject controls
reghdfe severity ///
    c.post2018_long#c.sev_pre2018_z ///
    c.post2020_long#c.sev_pre2018_z ///
    c.post2022_long#c.sev_pre2018_z ///
    `officerCtrls' `subjectCtrls' ///
    , absorb(District m) vce(cluster District)
eststo l3_long

* (4) + Force reason FE
reghdfe severity ///
    c.post2018_long#c.sev_pre2018_z ///
    c.post2020_long#c.sev_pre2018_z ///
    c.post2022_long#c.sev_pre2018_z ///
    `officerCtrls' `subjectCtrls' `situational' ///
    , absorb(District m) vce(cluster District)
eststo l4_long

* (5) Full model (long-run)
reghdfe severity ///
    c.post2018_long#c.sev_pre2018_z ///
    c.post2020_long#c.sev_pre2018_z ///
    c.post2022_long#c.sev_pre2018_z ///
    `officerCtrls' `subjectCtrls' `situational' ///
    , absorb(District m) vce(cluster District)
eststo l5_long

* Export long-run table
esttab l1_long l2_long l3_long l4_long l5_long using "tableA1_long_run_severity.rtf", replace ///
    b(%9.3f) p(%9.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(c.post2018_long#c.sev_pre2018_z ///
         c.post2020_long#c.sev_pre2018_z ///
         c.post2022_long#c.sev_pre2018_z) ///
    order(c.post2018_long#c.sev_pre2018_z ///
          c.post2020_long#c.sev_pre2018_z ///
          c.post2022_long#c.sev_pre2018_z) ///
    mtitles("No ctrls" "+Officer" "+Officer+Subject" "+Force reason" "Full model") ///
    title("Long-run effects: Step-function post indicators (severity, z)") ///
    addnotes("District & month FE absorbed; SE clustered by District" ///
             "Post dummies stay 1 after each reform date (cumulative effect)" ///
             "p-values in parentheses; * p<0.10, ** p<0.05, *** p<0.01")

*===========================
* 9) ROBUSTNESS: EXCLUDING COVID / PROTEST PERIOD
*   Drop 2020m3–2021m6 and re-run stepwise specs
*===========================

preserve
    * Drop COVID / protest window: March 2020 – June 2021
    drop if inrange(m, tm(2020m3), tm(2021m6))

    *===========================
    * SHORT-RUN RESULTS (No-COVID sample)
    *===========================
    eststo clear

    * (1) No controls
    reghdfe severity ///
        c.post2018_yr1#c.sev_pre2018_z ///
        c.post2020_yr1#c.sev_pre2018_z ///
        c.post2022_yr1#c.sev_pre2018_z ///
        , absorb(District m) vce(cluster District)
    eststo s1_short_nocovid

    * (2) + Officer controls
    reghdfe severity ///
        c.post2018_yr1#c.sev_pre2018_z ///
        c.post2020_yr1#c.sev_pre2018_z ///
        c.post2022_yr1#c.sev_pre2018_z ///
        `officerCtrls' ///
        , absorb(District m) vce(cluster District)
    eststo s2_short_nocovid

    * (3) + Officer + Subject controls
    reghdfe severity ///
        c.post2018_yr1#c.sev_pre2018_z ///
        c.post2020_yr1#c.sev_pre2018_z ///
        c.post2022_yr1#c.sev_pre2018_z ///
        `officerCtrls' `subjectCtrls' ///
        , absorb(District m) vce(cluster District)
    eststo s3_short_nocovid

    * (4) + Force reason FE
    reghdfe severity ///
        c.post2018_yr1#c.sev_pre2018_z ///
        c.post2020_yr1#c.sev_pre2018_z ///
        c.post2022_yr1#c.sev_pre2018_z ///
        `officerCtrls' `subjectCtrls' `situational' ///
        , absorb(District m) vce(cluster District)
    eststo s4_short_nocovid

    * (5) Full model (same as 4, just labeled as main)
    reghdfe severity ///
        c.post2018_yr1#c.sev_pre2018_z ///
        c.post2020_yr1#c.sev_pre2018_z ///
        c.post2022_yr1#c.sev_pre2018_z ///
        `officerCtrls' `subjectCtrls' `situational' ///
        , absorb(District m) vce(cluster District)
    eststo s5_short_nocovid

    * Export short-run no-COVID table
    esttab s1_short_nocovid s2_short_nocovid s3_short_nocovid s4_short_nocovid s5_short_nocovid ///
        using "table5_short_run_severity_nocovid.rtf", replace ///
        b(%9.3f) p(%9.3f) ///
        star(* 0.10 ** 0.05 *** 0.01) ///
        keep(c.post2018_yr1#c.sev_pre2018_z ///
             c.post2020_yr1#c.sev_pre2018_z ///
             c.post2022_yr1#c.sev_pre2018_z) ///
        order(c.post2018_yr1#c.sev_pre2018_z ///
              c.post2020_yr1#c.sev_pre2018_z ///
              c.post2022_yr1#c.sev_pre2018_z) ///
        mtitles("No controls" "+ Officer" "+ Officer + Subject" "+ Force reason" "Full model") ///
        title("Short-run effects excluding COVID/protest period (severity, z)") ///
        addnotes("Sample drops months 2020m3–2021m6" ///
                 "District & month FE absorbed; SE clustered by District" ///
                 "p-values in parentheses; * p<0.10, ** p<0.05, *** p<0.01")

    *===========================
    * LONG-RUN RESULTS (No-COVID sample)
    *===========================
    eststo clear

    * (1) No controls
    reghdfe severity ///
        c.post2018_long#c.sev_pre2018_z ///
        c.post2020_long#c.sev_pre2018_z ///
        c.post2022_long#c.sev_pre2018_z ///
        , absorb(District m) vce(cluster District)
    eststo l1_long_nocovid

    * (2) + Officer controls
    reghdfe severity ///
        c.post2018_long#c.sev_pre2018_z ///
        c.post2020_long#c.sev_pre2018_z ///
        c.post2022_long#c.sev_pre2018_z ///
        `officerCtrls' ///
        , absorb(District m) vce(cluster District)
    eststo l2_long_nocovid

    * (3) + Officer + Subject controls
    reghdfe severity ///
        c.post2018_long#c.sev_pre2018_z ///
        c.post2020_long#c.sev_pre2018_z ///
        c.post2022_long#c.sev_pre2018_z ///
        `officerCtrls' `subjectCtrls' ///
        , absorb(District m) vce(cluster District)
    eststo l3_long_nocovid

    * (4) + Force reason FE
    reghdfe severity ///
        c.post2018_long#c.sev_pre2018_z ///
        c.post2020_long#c.sev_pre2018_z ///
        c.post2022_long#c.sev_pre2018_z ///
        `officerCtrls' `subjectCtrls' `situational' ///
        , absorb(District m) vce(cluster District)
    eststo l4_long_nocovid

    * (5) Full model (long-run)
    reghdfe severity ///
        c.post2018_long#c.sev_pre2018_z ///
        c.post2020_long#c.sev_pre2018_z ///
        c.post2022_long#c.sev_pre2018_z ///
        `officerCtrls' `subjectCtrls' `situational' ///
        , absorb(District m) vce(cluster District)
    eststo l5_long_nocovid

    * Export long-run no-COVID table
    esttab l1_long_nocovid l2_long_nocovid l3_long_nocovid l4_long_nocovid l5_long_nocovid ///
        using "table6_long_run_severity_nocovid.rtf", replace ///
        b(%9.3f) p(%9.3f) ///
        star(* 0.10 ** 0.05 *** 0.01) ///
        keep(c.post2018_long#c.sev_pre2018_z ///
             c.post2020_long#c.sev_pre2018_z ///
             c.post2022_long#c.sev_pre2018_z) ///
        order(c.post2018_long#c.sev_pre2018_z ///
              c.post2020_long#c.sev_pre2018_z ///
              c.post2022_long#c.sev_pre2018_z) ///
        mtitles("No ctrls" "+ Officer" "+ Officer + Subject" "+ Force reason" "Full model") ///
        title("Long-run effects excluding COVID/protest period (severity, z)") ///
        addnotes("Sample drops months 2020m3–2021m6" ///
                 "District & month FE absorbed; SE clustered by District" ///
                 "p-values in parentheses; * p<0.10, ** p<0.05, *** p<0.01")

restore
			 
			 
*===========================
* 9) SECOND OUTCOMES — for text + appendix
*===========================
* Hospitalized
reghdfe hosp ///
    c.post2018_yr1#c.hosp_pre2018_z ///
    c.post2020_yr1#c.hosp_pre2018_z ///
    c.post2022_yr1#c.hosp_pre2018_z ///
    `C_officer' `C_subject' `C_reason', absorb(District m) vce(cluster District)
eststo h1

esttab h1 using "table_hospitalized_pref.rtf", replace rtf ///
    b(%9.3f) p(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(c.post2018_yr1#c.hosp_pre2018_z c.post2020_yr1#c.hosp_pre2018_z c.post2022_yr1#c.hosp_pre2018_z) ///
    title("Preferred spec: Hospitalization (Post × Baseline z)") ///
    addnotes("Same controls/FE as Table 1, Col (5)")

* Firearm discharged — ROBUSTNESS TABLE (req'd)
reghdfe fire ///
    c.post2018_yr1#c.fire_pre2018_z ///
    c.post2020_yr1#c.fire_pre2018_z ///
    c.post2022_yr1#c.fire_pre2018_z ///
    `C_officer' `C_subject' `C_reason', absorb(District m) vce(cluster District)
eststo f1

esttab f1 using "tableA1_robustness_firearm.rtf", replace rtf ///
    b(%9.3f) p(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(c.post2018_yr1#c.fire_pre2018_z c.post2020_yr1#c.fire_pre2018_z c.post2022_yr1#c.fire_pre2018_z) ///
    title("Robustness: Alternate outcome (Firearm discharged)") ///
    addnotes("Preferred controls; District & Month FE")

*===========================
* 10) FIGURES
*===========================

preserve

* Count incidents per month
collapse (count) incidents = severity, by(m)

tsset m

tsline incidents, ///
    xtitle("Month") ytitle("Use-of-force incidents") ///
    title("Monthly Use-of-Force Incidents Over Time") ///
    xline(`=tm(2020m3)' `=tm(2021m6)', lpattern(dash))

graph export "figure_incidents_per_month.png", replace

restore

preserve

gen q = qofd(day)
format q %tq

collapse (count) incidents = severity, by(q)

tsset q

tsline incidents, ///
    xtitle("Quarter") ytitle("Use-of-force incidents") ///
    title("Quarterly Use-of-Force Incidents") ///
    xline(`=tq(2020q1)' `=tq(2021q2)', lpattern(dash))

graph export "figure_incidents_quarterly.png", replace

restore


preserve

collapse (count) incidents = severity, by(m)
tsset m

tssmooth ma incidents_ma = incidents, window(3 1 3)

twoway ///
    (line incidents_ma m, lcolor(blue) lwidth(medthick)) ///
    , xtitle("Month") ///
      ytitle("Monthly use-of-force incidents (3-month MA)") ///
      title("Use-of-Force Incidents (Smoothed)") ///
      xline(`=tm(2020m3)' `=tm(2021m6)', lpattern(dash) lcolor(black))

graph export "figure_incidents_smooth.png", replace

restore

preserve

* Count incidents per month
collapse (count) incidents = severity, by(m)

* Generate COVID-period indicator
gen byte covid = inrange(m, tm(2020m3), tm(2021m6))

* Run regression of incident counts on COVID dummy
reg incidents covid, robust

restore


preserve
collapse (mean) severity, by(year District)

twoway ///
    (line severity year, lpattern(solid)) ///
    , by(District, col(3) note("") ///
                 title("Mean use-of-force severity by district and year")) ///
      xline(2018 2020 2022, lpattern(dash)) ///
      ytitle("Mean severity (L1–L4)") ///
      xtitle("Year")

graph export "figure1_severity_by_district_year.png", replace
restore

preserve
collapse (count) incidents = severity, by(District)
graph bar incidents, over(District) ///
    ytitle("Total incidents, 2016–2025") ///
    title("Use-of-Force Incidents by District (2016-2025)")
restore

preserve
keep if inrange(m, tm(2016m1), tm(2018m4))
collapse (mean) mean_sev = severity, by(District)
graph bar mean_sev, over(District) ///
    ytitle("Mean severity (L1–L4)") ///
    title("Baseline force severity differs across districts")
restore

preserve
keep if severity == 4   // L4 only

collapse (count) L4_count = severity, by(District)

graph bar L4_count, over(District) ///
    title("Total L4 Incidents by District (2016–2025)") ///
    ytitle("Count of L4 incidents") ///
    bar(1, color(navy))

restore

preserve

* total incidents per district
collapse (count) total_incidents = severity, by(District)
tempfile totals
save `totals'

restore
preserve

* L4 incidents per district
keep if severity == 4
collapse (count) L4 = severity, by(District)

merge 1:1 District using `totals', nogen

gen L4_rate = L4 / total_incidents * 1000

graph bar L4_rate, over(District) ///
    title("L4 Incidents per 1,000 Use-of-Force Events") ///
    ytitle("Rate per 1,000") ///
    bar(1, color(magenta))

restore

preserve

* total incidents per district
collapse (count) total_incidents = severity, by(District)
tempfile totals
save `totals'

restore
preserve

* L4 incidents per district
keep if severity == 4
collapse (count) L4 = severity, by(District)

merge 1:1 District using `totals', nogen

gen L4_rate = L4 / total_incidents * 100

graph bar L4_rate, over(District) ///
    title("L4 Incidents per 100 Use-of-Force Events") ///
    ytitle("Rate per 100") ///
    bar(1, color(magenta))

restore

preserve
keep if severity == 4
collapse (count) L4 = severity, by(m District)

histogram L4, by(District)
restore

preserve

    * Restrict to baseline window
    keep if inrange(m, tm(2016m1), tm(2018m4))

    * Keep only higher-severity force
    keep if severity >= 3

    * Count L3+ incidents per district
    collapse (count) L3plus = severity, by(District)

    * Bar chart
    graph bar L3plus, over(District) ///
        ytitle("Count of L3–L4 incidents (2016–pre-2018)") ///
        title("Baseline High-Severity Force Varies Across Districts")

restore

* Baseline window: 2016m1–2018m4
gen byte pre18 = inrange(m, tm(2016m1), tm(2018m4))

preserve
    keep if pre18

    * Indicator for high-severity force
    gen byte high_L34 = inlist(severity, 3, 4)

    * For each district: total incidents and high-severity incidents
    collapse ///
        (count) total_incidents = severity ///
        (sum)   high_L34_incidents = high_L34, ///
        by(District)
gen rate_L34 = 1000 * high_L34_incidents / total_incidents
graph bar rate_L34, over(District) ///
    ytitle("L3–L4 incidents per 1,000 force incidents") ///
    title("High-Severity Force Rate per 1,000 Incidents (Pre-2018)")
		
    * Share of incidents that were L3–L4 (%)
    gen share_L34 = 100 * high_L34_incidents / total_incidents
    label var share_L34 "Percent of incidents that were L3–L4"

    graph bar share_L34, over(District) ///
        ytitle("Percent of force incidents that were L3–L4") ///
        title("Share of High-Severity Force by District (Pre-2018)") ///
        ylabel(0(10)100)

    graph export "figure_share_L34_pre2018.png", replace
restore

gen rate_L34 = 1000 * high_L34_incidents / total_incidents
graph bar rate_L34, over(District) ///
    ytitle("L3–L4 incidents per 1,000 force incidents") ///
    title("High-Severity Force Rate per 1,000 Incidents (Pre-2018)")


preserve
keep if District == 4
keep if inrange(m, tm(2018m1), tm(2023m12))

collapse (mean) severity, by(m)

* compute the cutoff as a local
local cut2020 = tm(2020m12)

twoway line severity m, ///
    xline(`cut2020', lpattern(dash)) ///
    ytitle("Mean severity (L1–L4)") ///
    xtitle("Month") ///
    title("Monthly severity in District 4 around 2020 reform")

graph export "figure_d4_monthly.png", replace
restore



preserve

* Define pre vs post-2020 indicator
gen byte post2020_flag = (year >= 2021)

collapse (mean) severity, by(District post2020_flag)

label define post2020 0 "Pre" 1 "Post"
label values post2020_flag post2020

* Reshape so we have separate variables for Pre and Post
reshape wide severity, i(District) j(post2020_flag)

rename severity0 sev_pre
rename severity1 sev_post

graph bar sev_pre sev_post, over(District) ///
    ytitle("Mean severity (L1–L4)") ///
    title("Mean severity before vs after 2020 reform, by district") ///
    bar(1, color(blue)) ///
    bar(2, color(red)) ///
    legend(order(1 "Pre" 2 "Post") pos(6) ring(0))

graph export "figure2_pre_post2020_by_district.png", replace

restore


* --- (2) Binned scatter: change in severity (post–2022 vs pre–2022) ---
* No locals. Hard-code the cutoff with tm(2022m11).
* Compute district-level pre/post means in-place, then reduce to one row per district.

* Create pre/post flags once (no macros)
gen byte post22_flag = m > tm(2022m11)

* District-level pre/post means of severity
bys District: egen sev_pre  = mean(cond(m <  tm(2022m11), severity, .))
bys District: egen sev_post = mean(cond(m >  tm(2022m11), severity, .))

* Keep one row per district with baseline and the two means
preserve
    keep District sev_pre2018_z sev_pre sev_post
    duplicates drop
    drop if missing(sev_pre2018_z) | missing(sev_pre) | missing(sev_post)

    gen d_sev_22 = sev_post - sev_pre
    label var d_sev_22 "Change in severity (post'22 – pre'22)"
    label var sev_pre2018_z "Baseline severity z (pre-2018)"

    cap which binscatter
    if _rc ssc install binscatter, replace

    binscatter d_sev_22 sev_pre2018_z, nq(20) line(qfit) ///
        xtitle("Baseline severity (z, pre-2018)") ///
        ytitle("Δ Severity (post-2022 minus pre-2022)") ///
        title("Change in Severity vs Baseline After 2022")
    graph export "figure2_binnedscatter_post2022.png", replace
restore

*===========================
* END
*===========================
