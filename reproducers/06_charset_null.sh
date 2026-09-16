#!/bin/bash
#
# Issue 06 - a NULL is handed to snprintf("%s")
#
# When no mime_type is given the charset is filled in with
#
#     snprintf(charbuffer, sizeof(charbuffer), "text/plain; charset=\"%s\"",
#              get_encoding_name_for_icu(pg_get_client_encoding()));
#
# get_encoding_name_for_icu() has no name for every encoding.  From
# PostgreSQL 16 it answers NULL for the ones it does not know - SQL_ASCII,
# MULE_INTERNAL, EUC_JIS_2004, SHIFT_JIS_2004 - and passing NULL to "%s" is
# undefined behaviour.  glibc prints "(null)", which is how this reproducer
# sees it, but nothing requires that: other C libraries dereference the
# pointer and the backend crashes.  On PostgreSQL 15 and older the same call
# raises "encoding SQL_ASCII not supported by ICU" and no mail can be sent at
# all.
#
# SQL_ASCII is reachable by any user with a plain SET.

. "$(dirname "$0")/lib.sh"

require_psql
start_sink

url="$(sink_url)"

head1 "sending with client_encoding = SQL_ASCII"
psql -X -q -v ON_ERROR_STOP=0 >"$WORK/psql.log" 2>&1 <<SQL
SET orafce_mail.smtp_server_url = '$url';
SET client_encoding = 'SQL_ASCII';
CALL utl_mail.send(sender     => 'good@example.com',
                   recipients => 'recipient@example.com',
                   subject    => 'plain ascii',
                   message    => 'body');
SQL
sed 's/^/    /' "$WORK/psql.log"

head1 "the Content-Type the recipient is given"
sink_session | grep -a '^Content-Type:' | sed 's/^/    /'

if grep -q 'not supported by ICU' "$WORK/psql.log"; then
	bug "no mail can be sent at all while client_encoding is SQL_ASCII"
fi

if sink_session | grep -qa 'charset="(null)"'; then
	say ""
	say "-> the charset is the C library's rendering of a NULL pointer, which"
	say "   means NULL reached snprintf(\"%s\"): undefined behaviour."
	bug "get_encoding_name_for_icu() returned NULL and it was formatted anyway"
fi

if ! sink_session | grep -qa '^Content-Type:'; then
	skip "no Content-Type was captured; the message did not reach the sink"
fi

ok "a usable charset name was produced for SQL_ASCII"
