#!/bin/bash
#
# Issue 07 - cc and bcc are written into the message but never into the envelope
#
# orafce_send_mail() builds the recipient list with
#
#     recip = add_fields(recip, recipients);
#
# and never adds cc or bcc to it, while both are emitted as headers.  Two
# things follow, and they pull in opposite directions:
#
#   - nobody named in cc or bcc is sent anything, because SMTP delivers to
#     the envelope, not to the headers.  The caller is given no indication of
#     this;
#   - the Bcc header travels with the message, so every recipient is told who
#     was blind copied.  RFC 5322 3.6.3 is explicit that Bcc must not appear
#     in the copy recipients receive; that is the entire point of a blind
#     copy.

. "$(dirname "$0")/lib.sh"

require_psql
start_sink

url="$(sink_url)"

head1 "sending with a cc and a bcc"
psql -X -q -v ON_ERROR_STOP=0 >"$WORK/psql.log" 2>&1 <<SQL
SET orafce_mail.smtp_server_url = '$url';
CALL utl_mail.send(sender     => 'good@example.com',
                   recipients => 'recipient@example.com',
                   cc         => 'copied@example.com',
                   bcc        => 'blind@example.com',
                   subject    => 'who gets this?',
                   message    => 'body');
SQL
sed 's/^/    /' "$WORK/psql.log"

head1 "what the server received"
sink_session | sed 's/^/    /'

found=0

head1 "envelope"
sink_session | grep -a '^C: RCPT TO:' | sed 's/^/    /'

if ! sink_session | grep -qa '^C: RCPT TO:<copied@example.com>'; then
	say "    -> copied@example.com is in the Cc header but gets no message"
	found=1
fi
if ! sink_session | grep -qa '^C: RCPT TO:<blind@example.com>'; then
	say "    -> blind@example.com is in the Bcc header but gets no message"
	found=1
fi

head1 "disclosure"
if sink_session | grep -qa '^Bcc: blind@example.com'; then
	say "    -> the Bcc header is inside the message, so recipient@example.com"
	say "       is told that blind@example.com was copied"
	found=1
else
	say "    the Bcc header was kept out of the message"
fi

[ "$found" -eq 1 ] &&
	bug "cc/bcc are not delivered to, and the blind copy list is disclosed"

ok "cc and bcc are delivered to and the Bcc header is not sent"
