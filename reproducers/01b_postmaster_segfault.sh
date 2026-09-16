#!/bin/bash
#
# Issue 01b - the same defect, at its worst: the postmaster dies
#
# When orafce_mail is listed in shared_preload_libraries, _PG_init() runs in
# the postmaster.  DefineCustomStringVariable() calls the check hook for the
# boot value there too, and the hook calls get_role_oid(), a syscache lookup.
# The postmaster has no relcache, no syscache and no transaction, so the
# lookup dereferences memory that was never set up and the postmaster dies of
# SIGSEGV before it ever writes a line to its log.
#
# This needs no privileges beyond the ability to run initdb in a scratch
# directory, which any user can do; it does not touch the cluster the other
# reproducers use.

. "$(dirname "$0")/lib.sh"

command -v initdb >/dev/null 2>&1 || skip "initdb is not on PATH"
command -v postgres >/dev/null 2>&1 || skip "postgres is not on PATH"
command -v pg_config >/dev/null 2>&1 || skip "pg_config is not on PATH"

libdir="$(pg_config --pkglibdir)"
[ -f "$libdir/orafce_mail.so" ] ||
	skip "orafce_mail.so is not installed in $libdir"

data="$WORK/cluster"

head1 "creating a scratch cluster"
initdb -D "$data" --no-sync -A trust >"$WORK/initdb.log" 2>&1 ||
	{ tail -5 "$WORK/initdb.log" >&2; skip "initdb failed"; }

head1 "starting it with shared_preload_libraries = 'orafce_mail'"
postgres -D "$data" \
	-c shared_preload_libraries=orafce_mail \
	-c listen_addresses= \
	-c unix_socket_directories="$WORK" \
	-c port=54321 >"$WORK/postmaster.log" 2>&1 &
pid=$!

# Wait for it to either come up or die.
for _ in $(seq 1 100); do
	[ -S "$WORK/.s.PGSQL.54321" ] && break
	kill -0 "$pid" 2>/dev/null || break
	sleep 0.1
done

if kill -0 "$pid" 2>/dev/null; then
	status=0
	started=yes
	kill "$pid" 2>/dev/null
	wait "$pid" 2>/dev/null
else
	wait "$pid"
	status=$?
	started=no
fi

say "postgres exited with status $status"
say "everything it managed to log:"
sed 's/^/    /' "$WORK/postmaster.log"

# 139 is the shell's encoding of SIGSEGV; some shells report 11 directly.
if [ "$status" -eq 139 ] || [ "$status" -eq 11 ]; then
	bug "the postmaster crashed with SIGSEGV while defining the GUCs"
fi

if grep -q 'failed to initialize orafce_mail' "$WORK/postmaster.log"; then
	bug "the postmaster refused to start because of the GUC check hook"
fi

# Anything else that stopped it from starting is not what this is about, and
# reporting success on it would be reporting success on nothing.
if [ "$started" != "yes" ]; then
	skip "the scratch cluster did not start, for reasons unrelated to the hook"
fi

ok "the postmaster survived defining the GUCs"
