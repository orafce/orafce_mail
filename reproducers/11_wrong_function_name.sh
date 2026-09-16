#!/bin/bash
#
# Issue 11 - utl_mail.send() blames the wrong function in its argument errors
#
# orafce_mail_send() passes "utl_mail.send_attach_raw" as the function name
# for its own arguments, so a user who calls utl_mail.send() with a NULL or
# empty sender is told to go and look at a procedure they never called.

. "$(dirname "$0")/lib.sh"

require_psql

head1 "calling utl_mail.send() with a NULL sender"
out="$(psql -X -v ON_ERROR_STOP=0 \
		-c "CALL utl_mail.send(NULL, 'recipient@example.com')" 2>&1)"
printf '%s\n' "$out" | sed 's/^/    /'

if printf '%s' "$out" | grep -q 'utl_mail.send_attach_raw'; then
	bug "the hint names utl_mail.send_attach_raw for an error in utl_mail.send"
fi

head1 "and with an empty sender"
out="$(psql -X -v ON_ERROR_STOP=0 \
		-c "CALL utl_mail.send('', 'recipient@example.com')" 2>&1)"
printf '%s\n' "$out" | sed 's/^/    /'

if printf '%s' "$out" | grep -q 'utl_mail.send_attach_raw'; then
	bug "the hint names utl_mail.send_attach_raw for an error in utl_mail.send"
fi

ok "the errors name the function that was actually called"
