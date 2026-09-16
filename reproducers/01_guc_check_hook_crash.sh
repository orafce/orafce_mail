#!/bin/bash
#
# Issue 01 - the GUC check hooks look roles up in the catalogs
#
# smtp_server_url_acl_check() and smtp_server_userpwd_acl_check() call
# check_priv_of_role(), which calls get_role_oid() and has_privs_of_role().
# PostgreSQL runs a check hook for every source a value can come from, not
# only for SET, and the very first of those is the boot value that
# DefineCustomStringVariable() installs while _PG_init() is still running.
#
# So the moment the library is loaded the hook is asked whether the current
# user may set the variable, it answers no for anyone who is not a member of
# orafce_mail_config_url, and InitializeOneGUCOption() turns that "no" into
#
#     FATAL:  failed to initialize orafce_mail.smtp_server_url to ""
#
# which disconnects the backend.  Any user at all can trigger it: the
# utl_mail procedures are executable by PUBLIC, and calling one loads the
# library.  It also means the extension cannot be used by the very
# arrangement README.md describes, a user who is a member of orafce_mail but
# not of the two configuration roles.
#
# (01b_postmaster_segfault.sh covers the other end of the same defect.)

. "$(dirname "$0")/lib.sh"

require_psql

head1 "user '$REPRO_NOBODY' calls utl_mail.send() in a fresh session"
say "Expected: ERROR, must be a member of the role \"orafce_mail\""
say "Observed:"

out="$(PGUSER="$REPRO_NOBODY" psql -X -v ON_ERROR_STOP=0 \
		-c "CALL utl_mail.send('sender@example.com', 'recipient@example.com')" 2>&1)"
printf '%s\n' "$out" | sed 's/^/    /'

if printf '%s' "$out" | grep -q 'server closed the connection\|failed to initialize\|connection to server was lost'; then
	bug "loading the library terminated the backend instead of reporting a privilege error"
fi

if printf '%s' "$out" | grep -q 'role "orafce_mail_config_url"'; then
	bug "an unrelated privilege on orafce_mail_config_url was demanded just to load the library"
fi

head1 "the documented arrangement: a member of orafce_mail only"
say "A user who may send mail but may not configure the server must still be"
say "able to send mail with a url an administrator set for them."

psql -X -qc "SET orafce_mail.smtp_server_url = 'smtp://127.0.0.1:1'" >/dev/null 2>&1

out="$(PGUSER="$REPRO_NOBODY" psql -X -v ON_ERROR_STOP=0 \
		-c "SHOW orafce_mail.smtp_server_url" 2>&1)"
printf '%s\n' "$out" | sed 's/^/    /'

if printf '%s' "$out" | grep -q 'server closed the connection\|failed to initialize'; then
	bug "even reading the setting terminated the backend"
fi

ok "the library loads without demanding configuration privileges"
