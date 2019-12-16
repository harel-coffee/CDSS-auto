
--
-- Glucose lab values by person
SELECT rit_uid, pat_enc_csn_id_coded, lab_name, ord_value, ord_num_value, taken_time_jittered, result_time_jittered FROM `mining-clinical-decisions.starr_datalake2018.lab_result` 
-- SELECT lab_name, COUNT(lab_name) as number FROM `mining-clinical-decisions.starr_datalake2018.lab_result` 
WHERE UPPER(lab_name) LIKE '%GLUCOSE%' 
AND (lab_name) NOT IN ( 'Glucose, Urine', 'Glucose Urine', 'Glucose urine', 'Glucose/Creat ratio', 'Glucose, Fluid', "Est. Mean Glucose", "Glucose, CSF", "Collection Period Glucose", "Glucose Excretion", "Glucose Body Fluid", "Volume Glucose", "Glucose,GDM 3HR", "Glucose,GDM 2HR", 
"Glucose,GDM 1HR", "Glucose, 2 HR", "Glucose, 1 HR", "Glucose, Fasting (GDMF)", "Glucose,GTT 30 min", "Glucose,GTT 1HR", "Glucose,GTT 2HR", "Glucose,2HR - 75g", "Glucose, GDM Screen", "GLUCOSE", "Glucose") -- excludes glucoses not for insulin dose; also "GLUCOSE" and "Glucose" only used n=3 times
AND UPPER(ordering_mode) = 'INPATIENT' AND ord_num_value BETWEEN 0 AND 9999998
-- GROUP BY lab_name 
-- ORDER BY number