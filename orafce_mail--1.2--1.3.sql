/* orafce_mail--1.2--1.3.sql */

-- complain if script is sourced in psql, rather than via ALTER EXTENSION
\echo Use "ALTER EXTENSION orafce_mail UPDATE TO '1.3'" to load this file. \quit

/*
 * utl_mail.send_attach_varchar2 was bound to orafce_mail_send_attach_raw, so
 * a text attachment was handled as binary.  The C function it should have
 * named all along treats the attachment as text, but only consults that when
 * att_mime_type is NULL, so the default has to give it the chance to.
 */
CREATE OR REPLACE PROCEDURE utl_mail.send_attach_varchar2(
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
	att_mime_type oracle.varchar2 DEFAULT NULL,
	att_filename oracle.varchar2 DEFAULT NULL,
	replyto oracle.varchar2 DEFAULT NULL)
AS 'MODULE_PATHNAME','orafce_mail_send_attach_varchar2'
LANGUAGE C;
