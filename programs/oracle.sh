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
#   first:                     (optional -- a second input, see below)
#   ...the first operand, up to the `input:` line...
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
# Two inputs
#
# **`diff` generalised this the way `sha256sum` generalised it before**: the
# harness ran one input because every tool it had been asked about read one.
# `diff` holds two and computes a relationship between them, so a case may
# carry a `first:` section, and the tool is then run over both -- `first.txt`
# and the input, in that order.
#
# The two routes stay what they were: the *second* operand is the one that
# arrives on standard input, named `-`, which is what a pipe into a diff means.
# `firstnonewline:` says the first operand's last line has no newline, the way
# `nonewline:` already does for the input.
#
# ---------------------------------------------------------------------------
# The exit status is part of the answer
#
# Compared alongside the bytes, and `diff` is why: its status is documented
# behaviour -- `0` the same, `1` different, `2` trouble -- rather than the
# `0` or `1` every tool here happened to agree on without anybody checking.
# A program can print the right bytes and answer the wrong status, and until
# this was added nothing here would have noticed.
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
first() { awk '/^input:$/ { exit } seen { print } /^first:$/ { seen = 1 }' "$1"; }

# awk's print puts a newline back on the last line. Where the case says there
# was none, take it off again.
strip_newline() {
    printf '%s' "$(cat "$1")" > "$1.trimmed"
    mv "$1.trimmed" "$1"
}

run_case() {
    file=$1
    args=$(field args "$file" | awk '{ gsub(/%NEWLINE%/, "\n"); print }')

    body "$file" > "$work/in.txt"
    if has nonewline "$file"; then
        strip_newline "$work/in.txt"
    fi

    # One operand or two. The second is the one a pipe stands in for, because
    # that is what `cat new | diff old -` means.
    if has first "$file"; then
        first "$file" > "$work/first.txt"
        if has firstnonewline "$file"; then
            strip_newline "$work/first.txt"
        fi
        operands="\"\$work/first.txt\" \"\$work/in.txt\""
        piped="\"\$work/first.txt\" -"
    else
        operands="\"\$work/in.txt\""
        piped=""
    fi

    eval "\"\$oracle\" $args $operands" > "$work/oracle.out" 2>&1
    oracle_status=$?

    eval "\"\$root/bin/solvm\" \"\$root/programs/$tool.sob\" $args $operands" \
        > "$work/file.out" 2>&1
    file_status=$?

    eval "\"\$root/bin/solvm\" \"\$root/programs/$tool.sob\" $args $piped" \
        < "$work/in.txt" > "$work/pipe.out" 2>&1
    pipe_status=$?
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

    if ! cmp -s "$work/oracle.out" "$work/file.out"; then
        printf '  DIFFERS   %s\n' "$name"
        printf '            args: %s\n' "$(field args "$f")"
        report_diff "$work/file.out"
        news=$((news + 1))
    elif [ "$file_status" -ne "$oracle_status" ]; then
        # The bytes agreed and the answer did not. Reported apart from a
        # difference in the output because it is a different kind of wrong:
        # a caller testing the status is told the opposite of the truth by a
        # program whose output is correct.
        printf '  STATUS    %s -- same bytes, exit %s against the oracle'\''s %s\n' \
            "$name" "$file_status" "$oracle_status"
        news=$((news + 1))
    elif [ "$pipe_status" -ne "$file_status" ]; then
        printf '  STATUS    %s -- named file exits %s and the pipe %s\n' \
            "$name" "$file_status" "$pipe_status"
        news=$((news + 1))
    else
        printf '  same      %s\n' "$name"
        same=$((same + 1))
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
