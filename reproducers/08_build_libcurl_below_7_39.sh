#!/bin/bash
#
# Issue 08 - the module does not build against libcurl older than 7.39.0
#
# The block that begins
#
#     #if LIBCURL_VERSION_NUM >= 0x072700 /* 7.39.0 */
#
# is there to make the progress-meter interrupt support conditional, but two
# functions that have nothing to do with libcurl's version - check_priv_of_role()
# and add_line() - were written inside it, and so was the declaration of
# interrupt_requested, whose only assignment is guarded by the PostgreSQL
# version alone.  With an older libcurl none of the three exists and the
# compile fails.
#
# The reproducer compiles the module with LIBCURL_VERSION_NUM forced down to
# 7.38.0 through a shim header, which needs no privileges at all.

. "$(dirname "$0")/lib.sh"

command -v pg_config >/dev/null 2>&1 || skip "pg_config is not on PATH"
command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 ||
	skip "no C compiler on PATH"
CC="${CC:-$(command -v cc || command -v gcc)}"

src="$REPRO_DIR/../orafce_mail.c"
[ -f "$src" ] || skip "cannot find orafce_mail.c next to the reproducers"

mkdir -p "$WORK/shim/curl"
cat >"$WORK/shim/curl/curl.h" <<'EOF'
/* Pull in the real header, then pretend libcurl is 7.38.0. */
#include_next <curl/curl.h>
#undef LIBCURL_VERSION_NUM
#define LIBCURL_VERSION_NUM 0x072600
EOF

head1 "compiling orafce_mail.c against a libcurl that reports 7.38.0"
set +e
"$CC" -fPIC -c -o "$WORK/orafce_mail.o" \
	-I"$WORK/shim" \
	-I"$(pg_config --includedir-server)" \
	$(pg_config --cflags 2>/dev/null) \
	"$src" >"$WORK/compile.log" 2>&1
status=$?
set -e

grep -E '(error|Error)' "$WORK/compile.log" | sed 's/^/    /'

if [ "$status" -ne 0 ]; then
	bug "orafce_mail.c does not compile with libcurl older than 7.39.0"
fi

ok "the module compiles against libcurl 7.38.0"
