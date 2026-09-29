-- HCIS Government box - put one account back into service.
--
-- Called with two variables:   -v usr="..."  -v pwd="..."
--
-- It does four things to that one account, and nothing to any other:
--   * sets the password you chose
--   * switches the account back to active
--   * clears any lockout from failed attempts
--   * clears the force-a-password-change flag, so you get straight in
--
-- One transaction. If any part fails, nothing is written.

\set ON_ERROR_STOP on

BEGIN;

-- The two values are handed to the database here, rather than being pasted
-- into the statements below. psql does not substitute its variables inside a
-- DO block, and a password is exactly the kind of text that would break a
-- query if it were pasted in. This way the database receives it as data.
-- \gset rather than a plain SELECT: it hands the value over without printing
-- it. A password must not be echoed onto the screen, and this file's output
-- is saved to a report that gets sent back to me.
SELECT set_config('hcis.usr', :'usr', true) AS _ \gset
SELECT set_config('hcis.pwd', :'pwd', true) AS _ \gset

DO $$
DECLARE
  v_usr TEXT := current_setting('hcis.usr');
  v_pwd TEXT := current_setting('hcis.pwd');
  n     INT;
BEGIN
  -- Refuse politely rather than silently doing nothing to an account that is
  -- not there. A mistyped username is the likeliest mistake, so say so.
  SELECT count(*) INTO n
    FROM system_users WHERE lower(username) = lower(v_usr);

  IF n = 0 THEN
    RAISE EXCEPTION
      'There is no account called "%" on this box. Run 1-WHATS-WRONG.bat to see the list of usernames.', v_usr;
  END IF;

  IF length(v_pwd) < 10 THEN
    RAISE EXCEPTION
      'That password is only % characters. Please use at least 10.', length(v_pwd);
  END IF;

  UPDATE system_users
     SET password_hash        = crypt(v_pwd, gen_salt('bf', 10)),
         status               = 'active',
         locked_until         = NULL,
         failed_attempts      = 0,
         must_change_password = FALSE
   WHERE lower(username) = lower(v_usr);
END $$;

COMMIT;

\echo ''
\echo '=== the account now reads ==='
SELECT username, role, status,
       CASE WHEN locked_until IS NULL THEN 'not locked' ELSE 'STILL LOCKED' END AS lockout,
       failed_attempts
  FROM system_users
 WHERE lower(username) = lower(:'usr');

\echo ''
\echo '=== proof: does that password actually open that account? ==='
\echo ''
-- Deliberately NOT done by calling hcis_login. Newer versions of that function
-- sign a token as well, and if the signing key has not been set up on this box
-- it raises an error - which would look like a wrong password when it is
-- nothing of the kind. Comparing the stored hash answers the real question and
-- gives the same answer on every version of this system.
SELECT username,
       role,
       CASE WHEN crypt(:'pwd', password_hash) = password_hash
            THEN 'YES - this password opens this account'
            ELSE 'NO  - it does not match'        END AS password_check,
       CASE WHEN status <> 'active'               THEN 'BLOCKED - account is not active'
            WHEN locked_until IS NOT NULL
             AND locked_until > now()             THEN 'BLOCKED - locked out'
            WHEN coalesce(password_hash,'') = ''  THEN 'BLOCKED - no password set'
            ELSE 'nothing is blocking sign in'    END AS account_check
  FROM system_users
 WHERE lower(username) = lower(:'usr');
