#!/bin/bash
#
# Issue 10 - only "text/plain;" gets its line endings fixed
#
# SMTP requires every line to end with CR LF (RFC 5321 2.3.8).  The message
# arrives with whatever the client put in it, so it has to be converted, and
# orafce_send_mail() decides whether to convert with
#
#     if (!mime_type || strncmp(mime_type, "text/plain;", 11) == 0)
#
# an exact match on a prefix that includes the semicolon.  "text/plain"
# without parameters does not match it, and neither does text/html,
# text/csv, message/rfc822 or any other textual type, so those go out with
# bare LFs: a malformed message, which servers are entitled to reject and
# which mail clients render as one long line.

. "$(dirname "$0")/lib.sh"

require_psql
start_sink

url="$(sink_url)"

send()
{
	psql -X -q -v ON_ERROR_STOP=0 >>"$WORK/psql.log" 2>&1 <<SQL
SET orafce_mail.smtp_server_url = '$url';
CALL utl_mail.send(sender     => 'good@example.com',
                   recipients => 'recipient@example.com',
                   mime_type  => $1,
                   subject    => 'line endings',
                   message    => e'first\nsecond\nthird');
SQL
}

# Count body lines that end with a bare LF, that is, an LF not preceded by CR.
bare_lf()
{
	python3 - "$SINK_LOG" <<'PY'
import sys

raw = open(sys.argv[1], "rb").read()
start = raw.find(b"C: DATA\r\n")
body = raw[start:] if start >= 0 else raw
bare = 0
for i, b in enumerate(body):
    if b == 0x0A and (i == 0 or body[i - 1] != 0x0D):
        bare += 1
print(bare)
PY
}

found=0
for mime in "NULL" "'text/plain; charset=utf-8'" "'text/plain'" "'text/html'" "'TEXT/CSV'"; do
	: >"$SINK_LOG"
	send "$mime"
	n="$(bare_lf)"
	printf '  mime_type => %-28s bare LF line endings on the wire: %s\n' "$mime" "$n"
	if [ "$n" != "0" ]; then
		found=1
	fi
done

# The other half of the rule: content that is not text must be delivered
# exactly as it was given, so converting everything is not the answer.
: >"$SINK_LOG"
send "'application/octet-stream'"
n="$(bare_lf)"
printf '  mime_type => %-28s bare LF line endings on the wire: %s\n' \
	"'application/octet-stream'" "$n"
if [ "$n" = "0" ]; then
	say ""
	say "-> line endings were rewritten inside content that is not text"
	found=1
fi

if [ "$found" -eq 1 ]; then
	head1 "the message as the server saw it"
	sed 's/^/    /' "$SINK_LOG"
	bug "textual messages are sent with bare LF line endings"
fi

ok "every textual mime_type had its line endings converted to CR LF"
