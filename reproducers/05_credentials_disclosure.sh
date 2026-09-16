#!/bin/bash
#
# Issue 05 - the SMTP credentials can be read by anyone
#
# orafce_mail.c calls these two settings "Invisible super user settings", but
# both are defined with a flags argument of 0.  Setting them is guarded by a
# check hook, reading them is guarded by nothing, so any user who can connect
# can read the SMTP username and password out of the session with SHOW or
# current_setting() - or out of pg_settings, without even naming them.
#
# The flag PostgreSQL provides for this is GUC_SUPERUSER_ONLY, which keeps the
# value readable only by superusers and members of pg_read_all_settings while
# leaving the existing role-based rule for *setting* it alone.
#
# The flag only takes effect once the library that defines the setting has
# been loaded.  Until then the setting is a placeholder, which has no flags,
# so this checks the state that matters - after a load - and reports the
# placeholder window separately.

. "$(dirname "$0")/lib.sh"

require_psql

secret='smtp-user:c0rrect-horse-battery-staple'

# Loads the library first, so the real definition of the setting is in force,
# then sets the credentials and tries to read them back.
read_back()
{
	psql -X -Atq -v ON_ERROR_STOP=0 <<SQL 2>&1
DO \$\$ BEGIN
  CALL utl_mail.send('a@b.c', 'd@e.f');
EXCEPTION WHEN OTHERS THEN
  NULL;                       -- loading the library is all that was wanted
END \$\$;
SET orafce_mail.smtp_server_userpwd = '$secret';
$1
SQL
}

head1 "a member of orafce_mail_config_userpwd sets the credentials and reads them back"
say "current_user is $(psql -X -Atqc 'SELECT current_user'), a non-superuser."

for stmt in "SHOW orafce_mail.smtp_server_userpwd;" \
			"SELECT current_setting('orafce_mail.smtp_server_userpwd');" \
			"SELECT setting FROM pg_settings WHERE name = 'orafce_mail.smtp_server_userpwd';"; do
	say ""
	say "  $stmt"
	out="$(read_back "$stmt")"
	printf '%s\n' "$out" | sed 's/^/    /'

	if printf '%s' "$out" | grep -qF "$secret"; then
		say ""
		bug "orafce_mail.smtp_server_userpwd is readable without any privilege"
	fi
done

head1 "the same, for a user who is a member of no orafce_mail role at all"
out="$(PGUSER="$REPRO_NOBODY" psql -X -Atq -v ON_ERROR_STOP=0 \
		-c "SELECT setting FROM pg_settings WHERE name LIKE 'orafce_mail%'" 2>&1)"
printf '%s\n' "$out" | sed 's/^/    /'

if printf '%s' "$out" | grep -qF "$secret"; then
	bug "the credentials leak through pg_settings to any user at all"
fi

head1 "note: the placeholder window before the library is loaded"
say "A setting defined by a library is a placeholder until that library is"
say "loaded, and a placeholder carries no flags.  A value an administrator"
say "stored with ALTER ROLE ... SET is therefore readable by that role at"
say "the start of its session, before anything loads orafce_mail."
say ""
say "That is a property of PostgreSQL custom settings, not something this"
say "extension can close from inside itself; putting orafce_mail in"
say "session_preload_libraries closes it, which is only possible now that"
say "the library can be preloaded at all (see 01b)."

ok "the credentials were not disclosed"
