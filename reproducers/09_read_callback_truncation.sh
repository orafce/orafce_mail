#!/bin/bash
#
# Issue 09 - drives 09_read_callback_truncation.c
#
# read_callback() is a plain function over plain buffers, so it can be
# exercised directly instead of through a server.  The definitions it needs
# are copied out of orafce_mail.c here, by name, so the test always runs
# against the current source.  Needs no database and no privileges.

. "$(dirname "$0")/lib.sh"

command -v python3 >/dev/null 2>&1 || skip "python3 is not on PATH"
CC="${CC:-$(command -v cc || command -v gcc)}"
[ -n "$CC" ] || skip "no C compiler on PATH"

src="$REPRO_DIR/../orafce_mail.c"
[ -f "$src" ] || skip "cannot find orafce_mail.c next to the reproducers"

head1 "extracting the buffer handling out of orafce_mail.c"
python3 - "$src" "$WORK/extracted.inc" <<'PY' || skip "extraction failed"
import re
import sys

src, dest = sys.argv[1], sys.argv[2]
text = open(src).read()


def typedef(name):
    # (?:(?!typedef).)*? so the match starts at the typedef that belongs to
    # this name rather than at some earlier one
    m = re.search(r"typedef struct\s*\{(?:(?!typedef).)*?\}\s*%s;" % name, text, re.S)
    if not m:
        sys.exit("could not find typedef %s in %s" % (name, src))
    return m.group(0)


def function(name):
    """A whole function definition, from its storage class to its closing brace."""
    m = re.search(r"^static[^\n]*\n%s\(.*?^\}" % re.escape(name), text, re.S | re.M)
    if not m:
        sys.exit("could not find function %s() in %s" % (name, src))
    return m.group(0)


pieces = [typedef("BinaryReader"), typedef("DynamicBuffer")]
pieces += [function(n) for n in ("add_line", "is_list_space", "add_fields",
                                 "read_callback", "seek_callback")]

open(dest, "w").write("\n\n".join(pieces) + "\n")
print("    extracted %d definitions, %d lines"
      % (len(pieces), sum(p.count("\n") + 1 for p in pieces)))
PY

head1 "building the driver"
sanitize=""
echo 'int main(void){return 0;}' >"$WORK/probe.c"
if "$CC" -fsanitize=address,undefined "$WORK/probe.c" -o "$WORK/probe" >/dev/null 2>&1; then
	sanitize="-fsanitize=address,undefined"
	say "    with -fsanitize=address,undefined, so a buffer overrun would be caught too"
fi

"$CC" -g -O1 $sanitize -Wall -Wextra -I"$WORK" \
	-o "$WORK/driver" "$REPRO_DIR/09_read_callback_truncation.c" >"$WORK/build.log" 2>&1 || {
	sed 's/^/    /' "$WORK/build.log" >&2
	skip "could not build the driver"
}

head1 "running it"
if "$WORK/driver"; then
	ok "read_callback() delivers the whole message whatever buffer size it is given"
fi

bug "read_callback() reported end of data while it still had bytes to deliver"
