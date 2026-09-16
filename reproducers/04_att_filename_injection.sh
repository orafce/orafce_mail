#!/bin/bash
#
# Issue 04 - att_filename is pasted into Content-Disposition unescaped
#
# Commit 85780b2 ("Honour att_inline instead of accepting and ignoring it")
# had to supply the part's Content-Disposition itself, because libcurl only
# ever synthesises "attachment".  It builds the header with
#
#     psprintf("Content-Disposition: %s; filename=\"%s\"", ..., att_filename)
#
# and that replaced curl_mime_filename(), which escaped the value before
# putting it between quotes.  A double quote in the filename now closes the
# quoted string early, and the rest of the name is read as further
# parameters, further headers, and - after a blank line - as part content.
#
# Before that commit the same filename came out as a single, correctly
# escaped filename parameter, so this is a regression.

. "$(dirname "$0")/lib.sh"

require_psql
start_sink

url="$(sink_url)"

# Reads the attachment part's Content-Disposition the way a mail client does,
# honouring backslash escapes inside the quoted string, and prints
#
#     filename=<the name the client would use>
#     trailing=<whatever followed the closing quote>
#
# so a filename that stayed one parameter can be told from one that escaped
# out of it.
cat >"$WORK/parse_disposition.py" <<'PY'
import re
import sys

for line in sys.stdin:
    line = line.rstrip("\r\n")
    if not line.lower().startswith("content-disposition:"):
        continue

    value = line.split(":", 1)[1].strip()
    m = re.search('filename="', value)
    if not m:
        print("filename=")
        print("trailing=" + value)
        continue

    i = m.end()
    name = ""
    while i < len(value):
        if value[i] == "\\" and i + 1 < len(value):
            name += value[i + 1]
            i += 2
        elif value[i] == '"':
            i += 1
            break
        else:
            name += value[i]
            i += 1

    print("filename=" + name)
    print("trailing=" + value[i:])
PY

send_with_filename()
{
	: >"$SINK_LOG"
	psql -X -q -v ON_ERROR_STOP=0 >"$WORK/psql.log" 2>&1 <<SQL
SET orafce_mail.smtp_server_url = '$url';
CALL utl_mail.send_attach_raw(
        sender        => 'good@example.com',
        recipients    => 'recipient@example.com',
        subject       => 'attachment',
        message       => 'see attachment',
        attachment    => 'DATA'::bytea,
        att_mime_type => 'text/plain',
        att_filename  => $1);
SQL
	sed 's/^/    /' "$WORK/psql.log"
	sink_session | sed 's/^/    /'
	sink_session | python3 "$WORK/parse_disposition.py" >"$WORK/parsed"
	say ""
	say "as a mail client would read it:"
	sed 's/^/    /' "$WORK/parsed"
}

trailing()
{
	sed -n 's/^trailing=//p' "$WORK/parsed"
}

head1 "a filename containing a quote"
say "The name asked for is report.txt with an RFC 2231 extended parameter"
say "appended.  Clients prefer filename* over filename, so if it escapes the"
say "quoted string the recipient saves the attachment as evil.exe."
send_with_filename "'report.txt\"; filename*=UTF-8''''''evil.exe'"

if trailing | grep -qi 'filename\*='; then
	say ""
	say "-> a second, extended filename parameter escaped out of the value"
	bug "att_filename is interpolated into Content-Disposition without escaping"
fi

head1 "a filename ending in a backslash"
say "A trailing backslash escapes the closing quote, so the parameter never"
say "ends and the parser runs on into whatever follows."
send_with_filename "'report\\'"

if [ -n "$(trailing)" ]; then
	say ""
	say "-> the closing quote was escaped away by the value: $(trailing)"
	bug "att_filename is interpolated into Content-Disposition without escaping"
fi

head1 "a filename containing a line break"
send_with_filename "e'report.txt\"\r\nX-Injected: yes\r\n\r\n<h1>content of my choosing</h1>\r\nX-Ignored: '"

if sink_session | grep -q '^X-Injected: yes'; then
	say ""
	say "-> X-Injected became a header of the MIME part"
	bug "att_filename is interpolated into Content-Disposition without escaping"
fi

ok "the filename stayed inside the filename parameter"
