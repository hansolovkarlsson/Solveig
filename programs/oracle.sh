#!/bin/sh
#
# oracle.sh -- a program here against the one already on the machine.
#
#     sh programs/oracle.sh sed
#     sh programs/oracle.sh tail
#     sh programs/oracle.sh sha256sum
#
# Takes the name of a program in programs/: runs programs/<name>.sob and the
# tool of the same name over the corpus in programs/<name>/, and compares the
# bytes.
#
# **It was written for sed and generalised by the second caller**, which is the
# usual way round here -- the alternative was a hundred and fifty lines of shell
# in two files, and ROADMAP 5.5 is what that costs. Nothing about the harness
# was sed's; what is sed's is the corpus. The third caller generalised it twice
# more, in the same way: `sha256sum` is not in `/usr/bin` on this machine, and
# its two ways in differ by the *name* they print rather than by the answer.
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
#   tworoutes:                 (optional -- see below)
#   pipenames:                 (optional -- see below)
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
# Each case is run twice: with the input named as a file and with it arriving on
# standard input. **Those are different code paths** -- a named file can be
# measured and seeked and a pipe can be neither -- and a program that answered
# two ways about the same bytes would be wrong in a way no single-route check
# could see. For `tail` the two routes are not even the same algorithm.
#
# **A program that prints the name of its input** cannot have its two routes
# compared directly: a file is named and a pipe is named `-`. `pipenames:` says
# so and bounds it -- the pipe's output must be the file's with the input path
# replaced by a dash, and anything else is news. That is a full check rather
# than a waiver, which is the difference between it and `tworoutes:`.
#
# It was proved to fail rather than assumed to: a sha256sum whose standard-input
# path drops its last partial chunk -- a defect invisible to every other check
# here, since the named-file route is untouched and the oracle is never asked
# about the pipe -- is reported by this escape on most of the corpus at once.
#
#   ORACLE        the command to compare against. `/usr/bin/<name>` when there
#                 is one, and otherwise whatever the name finds on the PATH --
#                 `sha256sum` lives in /sbin here.

set -u

if [ $# -lt 1 ]; then
    echo "usage: sh programs/oracle.sh <name>     (sed, tail, ...)"
    exit 2
fi

tool=$1
root=$(cd "$(dirname "$0")/.." && pwd)
here="$root/programs/$tool"
if [ -n "${ORACLE:-}" ]; then
    oracle=$ORACLE
elif [ -x "/usr/bin/$tool" ]; then
    oracle=/usr/bin/$tool
else
    oracle=$(command -v "$tool" 2>/dev/null || echo "/usr/bin/$tool")
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [ ! -d "$here" ]; then
    echo "no corpus at programs/$tool/"
    exit 2
fi

if [ ! -f "$root/bin/solvm" ] || [ ! -f "$root/programs/$tool.sob" ]; then
    echo "build first:  make && ./bin/solas programs/$tool.sol"
    exit 1
fi

if ! command -v "$oracle" >/dev/null 2>&1 && [ ! -x "$oracle" ]; then
    echo "no oracle: $oracle is not there. Set ORACLE to one."
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

    eval "\"\$root/bin/solvm\" \"\$root/programs/$tool.sob\" $args \"\$work/in.txt\"" \
        > "$work/file.out" 2>&1

    eval "\"\$root/bin/solvm\" \"\$root/programs/$tool.sob\" $args" \
        < "$work/in.txt" > "$work/pipe.out" 2>&1
}

report_diff() {
    diff -u "$work/oracle.out" "$1" | sed -e '1,2d' -e 's/^/            /'
}

# ---------------------------------------------------------------------------

echo
echo "$tool against $oracle"
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
    # `tworoutes:` is the wider escape and is meant to stay rare: the two routes
    # are not comparable at all for this case, and the case file says why. It
    # buys silence rather than a weaker check, so a case wanting it has to earn
    # it in prose.
    if has tworoutes "$f"; then
        :
    elif has pipenames "$f"; then
        # The output names its input, and standard input is named `-`. awk
        # rather than sed, and by index rather than by pattern, so that a path
        # full of dots is replaced literally.
        awk -v p="$work/in.txt" '{
            while ((i = index($0, p)) > 0)
                $0 = substr($0, 1, i - 1) "-" substr($0, i + length(p))
            print }' "$work/file.out" > "$work/expected.out"
        if ! cmp -s "$work/expected.out" "$work/pipe.out"; then
            printf '  TWO WAYS  %s -- the pipe differs by more than the name\n' "$name"
            diff -u "$work/expected.out" "$work/pipe.out" \
                | sed -e '1,2d' -e 's/^/            /'
            news=$((news + 1))
            continue
        fi
    elif has pipediffers "$f"; then
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
