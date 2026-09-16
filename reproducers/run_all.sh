#!/bin/bash
#
# Runs every reproducer and summarises the result.
#
# Each one exits 1 while the issue it describes is present, 0 once it is
# fixed, and 77 if it could not be run at all.  So before the fixes this
# reports failures, and after them it is a regression test.
#
# See README.md for what has to exist first.

cd "$(dirname "$0")" || exit 1

verbose=0
[ "${1:-}" = "-v" ] && verbose=1

reproduced=0
fixed=0
skipped=0
summary=""

for script in [0-9][0-9]*.sh; do
	printf '\n\n################ %s ################\n' "$script"
	if [ "$verbose" -eq 1 ]; then
		bash "$script"
		status=$?
	else
		output="$(bash "$script" 2>&1)"
		status=$?
		printf '%s\n' "$output" | tail -n 25
	fi

	case "$status" in
		0)  fixed=$((fixed + 1));      result="fixed" ;;
		77) skipped=$((skipped + 1));  result="SKIPPED" ;;
		*)  reproduced=$((reproduced + 1)); result="REPRODUCED" ;;
	esac
	summary="$summary$(printf '  %-40s %s\n' "$script" "$result")
"
done

printf '\n\n################ summary ################\n'
printf '%s' "$summary"
printf '\n  %d reproduced, %d fixed, %d skipped\n' "$reproduced" "$fixed" "$skipped"

[ "$reproduced" -eq 0 ]
