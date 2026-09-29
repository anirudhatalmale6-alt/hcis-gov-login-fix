-- HCIS Government box - why can't I sign in?
-- Read only. This changes nothing at all.

\echo ''
\echo '=== 1. Which database am I actually looking at? ==='
SELECT current_database()          AS database,
       inet_server_addr()          AS server,
       inet_server_port()          AS port,
       version()                   AS postgres;

\echo ''
\echo '=== 2. Has the sign-in function been installed on this box? ==='
SELECT CASE WHEN count(*) > 0 THEN 'YES - hcis_login exists'
            ELSE 'NO  - this box is still on browser-side passwords' END AS sign_in_function
  FROM pg_proc WHERE proname = 'hcis_login';

\echo ''
\echo '=== 3. Every account on this box ==='
\echo '    (no passwords are shown - only whether one is set)'
SELECT username,
       role,
       status,
       CASE WHEN coalesce(password_hash,'') = ''      THEN 'NO PASSWORD SET'
            WHEN password_hash LIKE '$2%'             THEN 'ok (scrambled)'
            ELSE 'READABLE - not yet scrambled' END   AS password,
       CASE WHEN locked_until IS NULL                 THEN ''
            WHEN locked_until > now()                 THEN 'LOCKED until ' || to_char(locked_until,'HH24:MI')
            ELSE 'lock expired' END                   AS lockout,
       coalesce(failed_attempts,0)                    AS failed_tries,
       must_change_password                           AS must_change
  FROM system_users
 ORDER BY (status = 'active') DESC, username;

\echo ''
\echo '=== 4. The short answer ==='
SELECT (SELECT count(*) FROM system_users)                                    AS accounts_total,
       (SELECT count(*) FROM system_users WHERE status = 'active')            AS accounts_active,
       (SELECT count(*) FROM system_users
         WHERE status = 'active' AND locked_until > now())                    AS locked_right_now,
       (SELECT count(*) FROM system_users
         WHERE status = 'active' AND coalesce(password_hash,'') = '')         AS active_with_no_password;

\echo ''
\echo '=== 5. How much data is on this box ==='
SELECT (SELECT count(*) FROM beneficiaries)   AS beneficiaries,
       (SELECT count(*) FROM care_workers)    AS care_givers,
       (SELECT count(*) FROM leave_requests)  AS leave_records;

\echo ''
\echo '=== 5b. Are people actually assigned to a care giver? ==='
\echo '    Payroll pays a care giver for the people they look after. That link'
\echo '    is beneficiaries.care_worker_id. With none set, payroll can pay'
\echo '    nobody - and before the September build it would have paid everybody.'
SELECT count(*)                                                         AS beneficiaries_total,
       count(*) FILTER (WHERE coalesce(care_worker_id,'') <> '')        AS with_a_care_giver,
       count(*) FILTER (WHERE coalesce(care_worker_id,'') =  '')        AS with_nobody
  FROM beneficiaries;

\echo ''
\echo '    Links that point at a care giver who is not on this box.'
\echo '    Anything other than 0 means the two sides were numbered'
\echo '    differently - the usual result of a load from another system.'
SELECT count(*) AS links_pointing_nowhere
  FROM beneficiaries b
 WHERE coalesce(b.care_worker_id,'') <> ''
   AND NOT EXISTS (SELECT 1 FROM care_workers w WHERE w.display_id = b.care_worker_id);

\echo ''
\echo '    Service agreements - a separate record from the link above.'
SELECT count(*)                                          AS agreements_total,
       count(*) FILTER (WHERE status = 'active')         AS active
  FROM service_agreements;
