#!/bin/sh
#
# oracle.sh -- this sed against the one on the machine.
#
# Every other check a program here gets is a transcript its own author recorded,
# which can only catch what the author thought to check. The system `sed` was
# written by somebody else, has been in use for fifty years, and does not care
# what this program intended. It is the only check here that can find something
# nobody thought of -- which is the argument programs/sola/oracle.sh makes for
# QuickBASIC, and it applies here for less money, because the oracle is already
# installed.
#
# Two corpora, and the difference is the point:
#
#   agree/    must produce the same bytes under both. A difference is news, and
#             is either a defect or a divergence nobody had written down.
#   differ/   must NOT. Each file says at the top what each sed should do and
#             why this one is allowed to be different. A case here that starts
#             agreeing is also news: the divergence has gone and the file still
#             claims it.
#
# So the list of divergences stops being prose and becomes something that fails.
#
# ---------------------------------------------------------------------------
# A case file
#
#   # any number of comment lines, which are the argument for the case
#   args: -n /warn/p
#   nonewline:                 (optional -- the input's last line has no newline)
#   pipediffers:               (optional -- see below)
#   input:
#   ...everything after this line is the input...
#
# `args` is a shell word list, expanded by the shell, so quoting works as it
# does at a prompt. **`%NEWLINE%` in it becomes a real newline**, which is the
# only way to write the `a\`, `i\` and `c\` commands: their text begins on the
# line after the backslash, and the BSD sed this is held against does not take
# the `-e 'a\' -e 'text'` spelling that GNU does.
#
# ---------------------------------------------------------------------------
# Both ways in
#
# Each case is run twice against this sed: with the input named as a file and
# with it arriving on standard input. **Those are different code paths** --
# `system:readLine` reads a line at a time and a file is read whole and split --
# and a stream editor that answered two ways about the same bytes would be
# wrong in a way no single-route check could see.
#
#   SED_ORACLE    the sed to compare against; /usr/bin/sed by default.

set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
here="$root/programs/sed"
oracle=${SED_ORACLE:-/usr/bin/sed}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [ ! -f "$root/bin/solvm" ] || [ ! -f "$root/programs/sed.sob" ]; then
    echo "build first:  make && ./bin/solas programs/sed.sol"
    exit 1
fi

if ! command -v "$oracle" >/dev/null 2>&1 && [ ! -x "$oracle" ]; then
    echo "no oracle: $oracle is not there. Set SED_ORACLE to one."
    exit 2
fi

# ---------------------------------------------------------------------------
# Taking a case apart. awk rather than sed, so that nothing in the harness is
# the program under test.

field() { awk -v k="$1" '$0 ~ "^" k ":" { sub("^" k ": *", ""); print; exit }' "$2"; }
has()   { awk -v k="$1" '$0 ~ "^" k ":" { found = 1 } END { exit !found }' "$2"; }
body()  { awk 'seen { print } /^input:$/ { seen = 1 }' "$1"; }

run_case() {
    file=$1
    args=$(field args "$file" | awk '{ gsub(/%NEWLINE%/, "\n"); print }')

    body "$file" > "$work/in.txt"
    if has nonewline "$file"; then
        # awk's print added one; take it back off.
        printf '%s' "$(cat "$work/in.txt")" > "$work/in2.txt"
        mv "$work/in2.txt" "$work/in.txt"
    fi

    eval "\"\$oracle\" $args \"\$work/in.txt\"" > "$work/oracle.out" 2>&1
    oracle_status=$?

    eval "\"\$root/bin/solvm\" \"\$root/programs/sed.sob\" $args \"\$work/in.txt\"" \
        > "$work/file.out" 2>&1
    ours_status=$?

    eval "\"\$root/bin/solvm\" \"\$root/programs/sed.sob\" $args" \
        < "$work/in.txt" > "$work/pipe.out" 2>&1
}

report_diff() {
    diff -u "$work/oracle.out" "$1" | sed -e '1,2d' -e 's/^/            /'
}

# ---------------------------------------------------------------------------

echo
echo "oracle: $oracle"
echo

same=0
news=0

echo "agree/ -- these must match"
for f in "$here"/agree/*.case; do
    name=$(basename "$f" .case)
    run_case "$f"

    # The two routes must agree, except where a case says they cannot and says
    # what the difference is: standard input cannot report whether its last line
    # ended with a newline, so a pipe answers with one where a file does not.
    # That is checked rather than waved through -- the pipe's output must be the
    # file's plus exactly one newline, and anything else is news.
    if has pipediffers "$f"; then
        { cat "$work/file.out"; printf '\n'; } > "$work/expected.out"
        if ! cmp -s "$work/expected.out" "$work/pipe.out"; then
            printf '  TWO WAYS  %s -- the pipe differs by more than its last newline\n' "$name"
            diff -u "$work/file.out" "$work/pipe.out" | sed -e '1,2d' -e 's/^/            /'
            news=$((news + 1))
            continue
        fi
    elif ! cmp -s "$work/file.out" "$work/pipe.out"; then
        printf '  TWO WAYS  %s -- named file and pipe disagree\n' "$name"
        diff -u "$work/file.out" "$work/pipe.out" | sed -e '1,2d' -e 's/^/            /'
        news=$((news + 1))
        continue
    fi

    if cmp -s "$work/oracle.out" "$work/file.out"; then
        printf '  same      %s\n' "$name"
        same=$((same + 1))
    else
        printf '  DIFFERS   %s\n' "$name"
        printf '            args: %s\n' "$(field args "$f")"
        report_diff "$work/file.out"
        news=$((news + 1))
    fi
done

echo
echo "differ/ -- these must not, and each file says why"
for f in "$here"/differ/*.case; do
    [ -e "$f" ] || continue
    name=$(basename "$f" .case)
    run_case "$f"
    if cmp -s "$work/oracle.out" "$work/file.out"; then
        printf '  AGREES    %s -- the divergence has gone, and the file still claims it\n' "$name"
        news=$((news + 1))
    else
        printf '  differs   %s\n' "$name"
        awk '{ print "            oracle: " $0 }' "$work/oracle.out" | head -6
        awk '{ print "            ours:   " $0 }' "$work/file.out" | head -6
    fi
done

echo
if [ "$news" -eq 0 ]; then
    echo "$same agree, and every divergence is still there: nothing new."
    exit 0
fi
echo "$news to look at -- each is either a defect or a divergence nobody wrote down."
exit 1
