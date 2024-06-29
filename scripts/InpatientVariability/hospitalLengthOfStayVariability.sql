-- (Elective Ortho Surgery) Admission as Example
WITH

-- Identify Cases by Diagnosis Related Group
cohortDiagnosisRelatedGroup AS
(
    select *
    from `som-nero-phi-jonc101.shc_core_2021.drg_code`
    where drg_mpi_code =  '302' and drg_code_set_c = '51'    -- Knee Joint Replacement   8.6K encounters
        -- drg_mpi_code =  '470' and drg_code_set_c = '6'    -- Major Hip and Knee Joint Replacement without MC, 15K Encounters
    /*
    (   --'301' -- Hip Joint Replacement
        --'301',    -- Hip Joint Replacement    9.7K encounters
        --'470',    -- Hip and Knee Joint Replacement or Reattachment w/o MCC    14K encounters
        '302'     -- Knee Joint Replacement   8.6K encounters
    )
    and drg_code_set_c = '51' -- Or '6' or '3'? Unclear which one to interpret
    */
    
),

-- Find all Specialty Primary cohort Assignments
cohortPrimaryEncounter AS
(
    select distinct anon_id, pat_enc_csn_id_coded
    from `som-nero-phi-jonc101.shc_core_2021.treatment_team`
    where name = 'Primary Team'
    --and prov_name like 'ORTHO ARTHRITIS%'
    -- Up to 1,000 cases per year
),

-- Exclude all those that passed through Emergency Department (only capture "elective" cases)
emergencyAdmissionEncounter AS
(
    select distinct anon_id, pat_enc_csn_id_coded
    from `som-nero-phi-jonc101.shc_core_2021.adt`
    where pat_service_c in ('100','187') -- Emergency and Emergency Services
    and in_event_type_c = 1 -- Admission
),
cohortNonEmergencyEncounter AS
(
    select anon_id, pat_enc_csn_id_coded
    from cohortPrimaryEncounter 
    EXCEPT DISTINCT
    select anon_id, pat_enc_csn_id_coded
    from emergencyAdmissionEncounter 
),
cohortNonEmergencyEncounterByYear AS
(
    select EXTRACT(YEAR FROM trtmnt_tm_begin_dt_jittered) as assignYear, count(distinct anon_id) nPatients, count(distinct pat_enc_csn_id_coded) as nEncounters
    from cohortNonEmergencyEncounter join shc_core_2021.treatment_team using (anon_id, pat_enc_csn_id_coded)
    group by assignYear
    order by assignYear desc
    -- Close to 1,000 patients per year, confirming most of these admissions are elective / non-emergency
),

-- Find top Admission Diagnoses for those Encounters
cohortDiagnosisCounts AS
(  
    select source, icd9, icd10, dx_name, count(distinct snee.anon_id) as nPatients, count(distinct snee.pat_enc_csn_id_coded) as nEncounters, count(*) as nDiagnoses
    from `som-nero-phi-jonc101.shc_core_2021.diagnosis` as dc 
        join cohortNonEmergencyEncounter as snee on (snee.anon_id = dc.anon_id and snee.pat_enc_csn_id_coded = dc.pat_enc_csn_id_jittered)
    group by source, icd9, icd10, dx_name
    order by nPatients desc
),
diagnosisRelatedGroupCounts AS
(
    select drg_code_set_c, drg_mpi_code, drg_name, count(distinct anon_id) as nPatients, count(distinct pat_enc_csn_id_coded) as nEncounters, count(*) as nDiagnoses
    from `som-nero-phi-jonc101.shc_core_2021.drg_code`
    group by drg_code_set_c, drg_mpi_code, drg_name
    order by nEncounters desc
),

-- Calculate Length of Stay Distribution for Top Admission Diagnosis
cohortDiagnosisRelatedGroupLengthOfStay AS
(
    select 
        drg_code_set_c, drg_mpi_code, drg_name, anon_id, pat_enc_csn_id_coded, 
        admn_prov_map_id, visit_prov_map_id,
        min(event_time_jittered) as firstEventTime,
        DATETIME_DIFF(max(event_time_jittered), min(event_time_jittered), HOUR) as lengthOfStayHour, 
        ROUND(DATETIME_DIFF(max(event_time_jittered), min(event_time_jittered), HOUR) / 24, 2) as lengthOfStayDay,
        ROUND(DATETIME_DIFF(max(event_time_jittered), min(event_time_jittered), HOUR) / 24) as lengthOfStayDayFloor
    from cohortDiagnosisRelatedGroup
        join cohortNonEmergencyEncounter using (anon_id, pat_enc_csn_id_coded)
        join shc_core_2021.adt using (anon_id, pat_enc_csn_id_coded) -- Join ADT data for first and last event time to estimate length of stay
        join shc_core_2021.encounter using (anon_id, pat_enc_csn_id_coded)
    group by 
        drg_code_set_c, drg_mpi_code, drg_name, anon_id, pat_enc_csn_id_coded,
        admn_prov_map_id, visit_prov_map_id
),
-- Calculate summary stats per diagnosis 
cohortDRGLengthOfStaySummary AS
(
    select 
        drg_mpi_code, drg_name, 
        AVG(lengthOfStayDay) AS avgLengthOfStayDay, STDDEV(lengthOfStayDay) as stddevLengthOfStayDay,
        COUNT(distinct anon_id) as nPatients, COUNT(distinct pat_enc_csn_id_coded) as nEncounters,
        STDDEV(lengthOfStayDay) * COUNT(distinct pat_enc_csn_id_coded) AS variabilityImpact,
        SUM(lengthOfStayDay) as totalDays
    from cohortDiagnosisRelatedGroupLengthOfStay
    group by 
        drg_mpi_code, drg_name
    order by 
        stddevLengthOfStayDay * nEncounters desc -- Potential impact? Volume * variability
),
-- Break out diagnosis summary stats by admitting provider for top diagnoses...
cohortDRGLengthOfStaySummaryByProvider AS
(
    select 
        drg_mpi_code, drg_name, 
        admn_prov_map_id,
        AVG(lengthOfStayDay) AS avgLengthOfStayDay, STDDEV(lengthOfStayDay) as stddevLengthOfStayDay,
        COUNT(distinct anon_id) as nPatients, COUNT(distinct pat_enc_csn_id_coded) as nEncounters,
        STDDEV(lengthOfStayDay) * COUNT(distinct pat_enc_csn_id_coded) AS variabilityImpact,
        SUM(lengthOfStayDay) as totalDays
    from cohortDiagnosisRelatedGroupLengthOfStay
    -- where drg_mpi_code = '021' -- Restrict to one diagnosis at a time (e.g., Craniotomy) to make it easier to parse
    group by 
        drg_mpi_code, drg_name,
        admn_prov_map_id
    having nPatients > 10 -- Only inspect providers who've had a non-trival number of admissions
    order by 
        --avgLengthOfStayDay DESC
        drg_mpi_code, drg_name,
        stddevLengthOfStayDay * nEncounters desc -- Potential impact? Volume * variability
),
-- Join above two so able to compare total DRG averages vs per provider average
cohortDRGLengthOfStaySummaryByProviderAndTotal AS
(
    select 
        drg_mpi_code, drg_name, 
        admn_prov_map_id,
        byProv.avgLengthOfStayDay, byProv.stddevLengthOfStayDay, byProv.nPatients, byProv.nEncounters, byProv.variabilityImpact, byProv.totalDays,
        byDRG.avgLengthOfStayDay, byDRG.stddevLengthOfStayDay, byDRG.nPatients, byDRG.nEncounters, byDRG.variabilityImpact, byDRG.totalDays
    from 
        cohortDRGLengthOfStaySummaryByProvider as byProv
        join cohortDRGLengthOfStaySummary as byDRG using (drg_mpi_code, drg_name) 
    order by 
        byDRG.variabilityImpact desc,
        byProv.totalDays desc

),
-- Break out data by length of stay values so can plot as a histogram
cohortDRGLengthOfStayHistogram AS
(
    select 
        --EXTRACT(YEAR FROM firstEventTime) as admitYear,
        drg_mpi_code, drg_name,
        admn_prov_map_id,
        FLOOR(lengthOfStayHour/24) as lengthOfStayDayMin, FLOOR(lengthOfStayHour/24)+1 as lengthOfStayDayMax,
        count(distinct anon_id) as nPatients, count(distinct pat_enc_csn_id_coded) as nEncounters
    from cohortDiagnosisRelatedGroupLengthOfStay
    --where drg_mpi_code = '021' and drg_name like 'CRANIOTOMY%' -- Restrict to diagnosis to facilitate visualization
    group by 
        --admitYear, 
        drg_mpi_code, drg_name, admn_prov_map_id, lengthOfStayDayMin, lengthOfStayDayMax
    order by 
        --admitYear desc, 
        drg_mpi_code, drg_name, admn_prov_map_id, lengthOfStayDayMin
),

-- Find which order sets were used in each cohort admit/encounter
cohortDiagnosisRelatedGroupOrderSet AS
(
    select distinct cdrg.*,  protocol_id, protocol_name
    from shc_core_2021.proc_orderset as os
        join cohortDiagnosisRelatedGroup as cdrg using (anon_id, pat_enc_csn_id_coded)
),

-- Most common order sets used in the cohort
cohortDiagnosisRelatedGroupByOrderSet AS
(
    select protocol_id, protocol_name,
        count(distinct anon_id) as nPatients, count(distinct pat_enc_csn_id_coded) as nEncounters
    from cohortDiagnosisRelatedGroupOrderSet as cdrgos
    group by protocol_id, protocol_name
    order by nEncounters desc
),

-- Restrict to only order set of interest as the relevant "standard" pathway for the DRG cohort
cohortDiagnosisRelatedGroupStandardOrderSet AS
(
    select distinct anon_id, pat_enc_csn_id_coded, protocol_id, protocol_name
    from shc_core_2021.proc_orderset as os
        join cohortDiagnosisRelatedGroup as cdrg using (anon_id, pat_enc_csn_id_coded)
    where protocol_id = 891 -- IP ORT TOTAL JOINT REPLACEMENT
),
-- Left outer join against cohort DRG length of stay results so can differentiate who used and who did not use standard order set
cohortDiagnosisRelatedGroupLengthOfStayStandardOrderSet AS
(
    select *, (protocol_id is not null) orderSetUsed
    from cohortDiagnosisRelatedGroupLengthOfStay AS cdrglos
        left join cohortDiagnosisRelatedGroupStandardOrderSet AS cdrgsos using (anon_id, pat_enc_csn_id_coded)
),
-- Break out summary stats by whether standard order set was used or not...
cohortDRGLengthOfStaySummaryByStandardOrderSet AS
(
    select 
        drg_code_set_c, drg_mpi_code, drg_name, 
        orderSetUsed,
        AVG(lengthOfStayDay) AS avgLengthOfStayDay, STDDEV(lengthOfStayDay) as stddevLengthOfStayDay,
        COUNT(distinct anon_id) as nPatients, COUNT(distinct pat_enc_csn_id_coded) as nEncounters,
        STDDEV(lengthOfStayDay) * COUNT(distinct pat_enc_csn_id_coded) AS variabilityImpact,
        SUM(lengthOfStayDay) as totalDays
    from cohortDiagnosisRelatedGroupLengthOfStayStandardOrderSet
    group by 
        drg_code_set_c, drg_mpi_code, drg_name,
        orderSetUsed
    order by 
        drg_code_set_c, drg_mpi_code, drg_name,
        stddevLengthOfStayDay * nEncounters desc -- Potential impact? Volume * variability
),


spacer AS ( select * from `som-nero-phi-jonc101.shc_core_2021.demographic`)

select *
from cohortDRGLengthOfStaySummaryByStandardOrderSet
limit 1000





-- Break out LoS Distribution by Primary Attending


-- Correlate Discharge Order time Relative to Discharge Time vs. Length of Stay
