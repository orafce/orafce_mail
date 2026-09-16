-- One-time setup for the reproducers, and the only part of them that needs a
-- superuser.  Run it once against the database the reproducers will use:
--
--   psql -U postgres -f reproducers/setup.sql
--
-- It builds exactly the arrangement README.md documents: a login role that is
-- a member of orafce_mail and of both configuration roles, and a second login
-- role that is a member of nothing.  Everything the reproducers do afterwards
-- is done as one of those two unprivileged roles.

CREATE EXTENSION IF NOT EXISTS orafce;
CREATE EXTENSION IF NOT EXISTS orafce_mail;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'orafce_mail_user') THEN
    CREATE ROLE orafce_mail_user LOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'orafce_mail_nobody') THEN
    CREATE ROLE orafce_mail_nobody LOGIN;
  END IF;
END;
$$;

GRANT orafce_mail, orafce_mail_config_url, orafce_mail_config_userpwd
  TO orafce_mail_user;

\echo 'setup done: roles orafce_mail_user (member of all three roles) and orafce_mail_nobody (member of none)'
