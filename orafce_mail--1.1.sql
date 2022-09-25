/* orafce_mail.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION orafce_mail" to load this file. \quit
CREATE SCHEMA utl_mail;
CREATE SCHEMA dbms_mail;

GRANT USAGE ON SCHEMA utl_mail TO PUBLIC;
GRANT USAGE ON SCHEMA dbms_mail TO PUBLIC;

CREATE PROCEDURE utl_mail.send(
	sender oracle.varchar2,
	recipients oracle.varchar2,
	cc oracle.varchar2 DEFAULT NULL,
	bcc oracle.varchar2 DEFAULT NULL,
	subject oracle.varchar2 DEFAULT NULL,
	message oracle.varchar2 DEFAULT NULL,
	mime_type oracle.varchar2 DEFAULT NULL,
	priority integer DEFAULT NULL,
	replyto oracle.varchar2 DEFAULT NULL)
AS 'MODULE_PATHNAME','orafce_mail_send'
LANGUAGE C;

CREATE PROCEDURE utl_mail.send_attach_raw(
	sender oracle.varchar2,
	recipients oracle.varchar2,
	cc oracle.varchar2 DEFAULT NULL,
	bcc oracle.varchar2 DEFAULT NULL,
	subject oracle.varchar2 DEFAULT NULL,
	message oracle.varchar2 DEFAULT NULL,
	mime_type oracle.varchar2 DEFAULT NULL,
	priority integer DEFAULT NULL,
	attachment bytea DEFAULT NULL,
	att_inline boolean DEFAULT true,
	att_mime_type oracle.varchar2 DEFAULT 'application/octet',
	att_filename oracle.varchar2 DEFAULT NULL,
	replyto oracle.varchar2 DEFAULT NULL)
AS 'MODULE_PATHNAME','orafce_mail_send_attach_raw'
LANGUAGE C;

CREATE PROCEDURE utl_mail.send_attach_varchar2(
	sender oracle.varchar2,
	recipients oracle.varchar2,
	cc oracle.varchar2 DEFAULT NULL,
	bcc oracle.varchar2 DEFAULT NULL,
	subject oracle.varchar2 DEFAULT NULL,
	message oracle.varchar2 DEFAULT NULL,
	mime_type oracle.varchar2 DEFAULT NULL,
	priority integer DEFAULT NULL,
	attachment oracle.varchar2 DEFAULT NULL,
	att_inline boolean DEFAULT true,
	att_mime_type oracle.varchar2 DEFAULT 'application/octet',
	att_filename oracle.varchar2 DEFAULT NULL,
	replyto oracle.varchar2 DEFAULT NULL)
AS 'MODULE_PATHNAME','orafce_mail_send_attach_raw'
LANGUAGE C;

CREATE PROCEDURE dbms_mail.send(
	from_str oracle.varchar2,
	to_str oracle.varchar2,
	cc oracle.varchar2,
	bcc oracle.varchar2,
	subject oracle.varchar2,
	reply_to oracle.varchar2,
	body oracle.varchar2)
AS 'MODULE_PATHNAME','orafce_mail_dbms_mail_send'
LANGUAGE C;

/*
 * There is not dependency between roles and extensions?
 */
DO $$
BEGIN
  IF NOT EXISTS(SELECT * FROM pg_roles WHERE rolname::text = 'orafce_mail') THEN
    CREATE ROLE orafce_mail NOLOGIN;
  END IF;
  IF NOT EXISTS(SELECT * FROM pg_roles WHERE rolname::text = 'orafce_mail_config_url') THEN
    CREATE ROLE orafce_mail_config_url NOLOGIN;
  END IF;
  IF NOT EXISTS(SELECT * FROM pg_roles WHERE rolname::text = 'orafce_mail_config_userpwd') THEN
    CREATE ROLE orafce_mail_config_userpwd NOLOGIN;
  END IF;
END;
$$;
