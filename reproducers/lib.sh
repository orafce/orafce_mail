#!/bin/bash
# Shared helpers for the reproducers.  Sourced, not executed.
#
# Every reproducer exits 1 while the bug it describes is present and 0 once it
# is fixed, so run_all.sh doubles as a regression test.

set -u

: "${PGHOST:=/tmp}"
: "${PGPORT:=5432}"
: "${PGDATABASE:=postgres}"
: "${SMTP_PORT:=52525}"

# The two unprivileged roles reproducers/setup.sql creates.
: "${REPRO_USER:=orafce_mail_user}"       # member of all three orafce_mail roles
: "${REPRO_NOBODY:=orafce_mail_nobody}"   # member of none of them
: "${PGUSER:=$REPRO_USER}"

export PGHOST PGPORT PGDATABASE PGUSER

REPRO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orafce_mail_repro.XXXXXX")"
SINK_PID=""

cleanup()
{
	[ -n "$SINK_PID" ] && kill "$SINK_PID" 2>/dev/null
	rm -rf "$WORK"
}
trap cleanup EXIT

say()   { printf '%s\n' "$*"; }
head1() { printf '\n=== %s ===\n' "$*"; }

# Fail the run with an explanation of what could not be set up.  A reproducer
# that cannot run is not the same as a reproducer that passes.
skip()
{
	say "SKIP: $*"
	exit 77
}

bug()
{
	printf '\nBUG REPRODUCED: %s\n' "$*"
	exit 1
}

ok()
{
	printf '\nNOT REPRODUCED (looks fixed): %s\n' "$*"
	exit 0
}

require_psql()
{
	command -v psql >/dev/null 2>&1 || skip "psql is not on PATH"
	psql -Atqc 'select 1' >/dev/null 2>&1 ||
		skip "cannot connect to PostgreSQL (PGHOST=$PGHOST PGPORT=$PGPORT PGUSER=${PGUSER:-$USER}); see reproducers/README.md"
	psql -Atqc "select extname from pg_extension where extname = 'orafce_mail'" 2>/dev/null |
		grep -q orafce_mail ||
		skip "the orafce_mail extension is not installed in $PGDATABASE; see reproducers/README.md"
	if [ "$(psql -Atqc 'select current_setting(''is_superuser'')' 2>/dev/null)" = "on" ]; then
		skip "these reproducers must be run by a non-superuser; see reproducers/README.md"
	fi
}

# Start the capture SMTP server and wait until it is accepting connections.
start_sink()
{
	command -v python3 >/dev/null 2>&1 || skip "python3 is not on PATH"

	SINK_LOG="$WORK/session.log"
	python3 "$REPRO_DIR/smtp_sink.py" "$SMTP_PORT" "$SINK_LOG" >"$WORK/sink.err" 2>&1 &
	SINK_PID=$!

	for _ in $(seq 1 100); do
		if grep -q listening "$WORK/sink.err" 2>/dev/null; then
			return 0
		fi
		kill -0 "$SINK_PID" 2>/dev/null || break
		sleep 0.1
	done

	cat "$WORK/sink.err" >&2
	skip "could not start the capture SMTP server on port $SMTP_PORT (set SMTP_PORT to a free port)"
}

sink_url() { printf 'smtp://127.0.0.1:%s' "$SMTP_PORT"; }

# Everything the SMTP server saw, commands prefixed with "C: ".
sink_session() { cat "$SINK_LOG" 2>/dev/null; }
