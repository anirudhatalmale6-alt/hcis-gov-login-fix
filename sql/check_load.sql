-- HCIS - did the data load land properly?
--
-- Run this straight after loading a database from the old system, BEFORE
-- anyone opens payroll. Read only: it changes nothing.
--
-- It answers one question that no other screen will tell you honestly. Payroll
-- pays a care giver for the people they look after, and that link is a single
-- field on the beneficiary's record holding the care giver's ID. If the load
-- brings the OLD system's numbering, every beneficiary will have that field
-- filled in, nothing will look blank, and the links will point at care givers
-- who do not exist here. Payroll then pays nobody, for a reason invisible
-- everywhere else.
--
-- So "how many are filled in" is not the test. "How many point at somebody who
-- is actually here" is.

\echo ''
\echo '============================================================'
\echo ' HCIS - checking a data load'
\echo '============================================================'

\echo ''
\echo '--- How much arrived ---'
SELECT (SELECT count(*) FROM beneficiaries)      AS beneficiaries,
       (SELECT count(*) FROM care_workers)       AS care_givers,
       (SELECT count(*) FROM service_agreements) AS agreements,
       (SELECT count(*) FROM leave_requests)     AS leave_records;

\echo ''
\echo '--- The care giver links ---'
SELECT count(*)                                                    AS beneficiaries_total,
       count(*) FILTER (WHERE coalesce(care_worker_id,'') <> '')   AS has_a_care_giver,
       count(*) FILTER (WHERE coalesce(care_worker_id,'') =  '')   AS has_nobody
  FROM beneficiaries;

\echo ''
\echo '--- THE NUMBER THAT MATTERS ---'
\echo '    Links pointing at a care giver who is not on this box.'
SELECT count(*) AS pointing_nowhere
  FROM beneficiaries b
 WHERE coalesce(b.care_worker_id,'') <> ''
   AND NOT EXISTS (SELECT 1 FROM care_workers w WHERE w.display_id = b.care_worker_id);

\echo ''
\echo '--- Verdict ---'
-- Spelled out rather than left as a number to interpret. Somebody reading this
-- at the end of a long migration should not have to remember which way round
-- good looks.
SELECT CASE
         WHEN (SELECT count(*) FROM beneficiaries) = 0
           THEN 'NOTHING LOADED - there are no beneficiaries on this box at all.'
         WHEN orphans > 0
           THEN 'FAILED - ' || orphans || ' links point at care givers who are not here. '
             || 'The two systems number people differently. Send me this number, do not run payroll.'
         WHEN linked = 0
           THEN 'NO LINKS - every beneficiary is here but none is assigned to a care giver. '
             || 'Payroll will pay nobody. The assignments did not come across.'
         ELSE 'PASS - ' || linked || ' beneficiaries are linked to a care giver who exists here. '
             || 'Payroll has something to work with.'
       END AS verdict
  FROM (
    SELECT
      (SELECT count(*) FROM beneficiaries b
        WHERE coalesce(b.care_worker_id,'') <> ''
          AND NOT EXISTS (SELECT 1 FROM care_workers w WHERE w.display_id = b.care_worker_id)) AS orphans,
      (SELECT count(*) FROM beneficiaries b
        WHERE coalesce(b.care_worker_id,'') <> ''
          AND EXISTS (SELECT 1 FROM care_workers w WHERE w.display_id = b.care_worker_id))     AS linked
  ) t;

\echo ''
\echo '    If the verdict is not PASS, send it to me before anyone runs payroll.'
\echo ''
