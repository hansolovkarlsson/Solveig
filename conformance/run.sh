#!/bin/sh
# The conformance harness -- runs the corpus against whatever tools it is pointed
# at, and scores each case on its bytes.
#
#   ./conformance/run.sh                     every case
#   ./conformance/run.sh accepted/03-blocks  one directory, or one case
#   ./conformance/run.sh -v                  name every case, not only the failures
#
# Two environment variables say what to run. Each is a template with `%s` where
# a path goes -- the compile one takes the source and then the object, the run
# one takes the object:
#
#   SOL_COMPILE='./bin/solas %s -o %s'       the default
#   SOL_RUN='./bin/solvm %s'                 the default
#
# A second front end sets SOL_COMPILE. A second machine sets SOL_RUN. A producer
# that emits bytecode from another language sets both and translates each case,
# which is what the `.out` file is for: it is the answer, and the source is only
# the notation it was written in.
#
# The defaults name this repository's binaries and are the only mention of them
# here. Nothing else in this directory knows what implementation it is scoring.
#
# A case is two files. `name.sol` is the program and `name.out` is its output,
# byte for byte -- not a subsequence, not a pattern. Everything else is a header
# inside the program, so there is no manifest beside the tree to go stale:
#
#   ; conformance: what this case pins       required, one line
#   ; varies: front | machine | both         required -- who can fail it
#   ; status: 0 | <n> | nonzero              optional, the exit status; 0 if absent
#   ; refused: group/rule                    present when the compiler must reject it
#   ; stderr: expected                       optional -- something is said there
#
# The header says which of the three kinds a case is, so the three live in one
# tree read one way rather than three trees read three ways:
#
#   accepted   no `refused`, status 0 -- it compiles, runs, and prints the .out
#   trapped    no `refused`, status nonzero -- it compiles, runs, prints what is
#              in the .out, and then stops. What it stopped *saying* is not
#              compared: an error's wording is the implementation's to choose.
#   refused    `refused: group/rule` -- the compiler must reject it, and no .out
#              is wanted because nothing runs.
#
# Standard error is never compared -- the wording of a failure or a warning is
# the implementation's to choose. Whether anything is said there at all is not:
# a case must be silent unless its status is `nonzero` or it says
# `stderr: expected`, and one that says either must not be silent. What the
# compiler said on the way past counts with what the machine said, a warning
# being at one end and a failure at the other.
#
# A refusal case must have a `<name>-legal.sol` beside it: the same program with
# the one offending thing put right, which must compile and run. Without that a
# front end that refuses everything scores full marks on the whole of refused/.
# It is the arrangement programs/oracle.sh already uses, where `agree/` must
# match and `differ/` must not, and the second corpus is the point.
#
# `varies` is not read by this script. It is there so that a front end can be
# scored on the cases a front end can fail, once there is a second one; today it
# is a claim about the case that a reader can check.
#
# Exit status: 0 when every case passed, 1 when one did not, 2 when the harness
# itself could not proceed.
set -e

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
cd "$root"

: "${SOL_COMPILE:=./bin/solas %s -o %s}"
: "${SOL_RUN:=./bin/solvm %s}"

verbose=no
targets=""
for arg in "$@"; do
    case $arg in
        -v|--verbose) verbose=yes ;;
        -*) echo "run.sh: unknown option $arg" >&2; exit 2 ;;
        *)  targets="$targets $arg" ;;
    esac
done
[ -n "$targets" ] || targets=" $here/accepted $here/refused $here/trapped"

work=$(mktemp -d "${TMPDIR:-/tmp}/solveig-conformance.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

# Enumerated by extension rather than from a list. A case that is added is run;
# a case that is renamed is still run; and there is no second place to forget.
cases=$work/cases
: > "$cases"
for t in $targets; do
    # A target is read relative to this directory first, so that
    # `accepted/03-blocks` works from anywhere, and then relative to the caller.
    [ -e "$t" ] || [ ! -e "$here/$t" ] || t=$here/$t
    if [ -d "$t" ]; then
        find "$t" -name '*.sol' >> "$cases"
    elif [ -f "$t" ]; then
        echo "$t" >> "$cases"
    else
        echo "run.sh: no such case or directory: $t" >&2
        exit 2
    fi
done
LC_ALL=C sort -o "$cases" "$cases"

if [ ! -s "$cases" ]; then
    echo "run.sh: no cases found" >&2
    exit 2
fi

passed=0
failed=0
fails=$work/fails
: > "$fails"

# The header is read from the case rather than from a manifest, and a case
# missing one is a failure rather than a skip -- a corpus that quietly declines
# to run a case is the thing this suite exists to avoid.
field() {
    sed -n "s/^;[[:space:]]*$2:[[:space:]]*//p" "$1" | head -1
}

fail() {
    failed=$((failed + 1))
    printf 'FAIL  %s\n      %s\n' "$1" "$2" >> "$fails"
}

while IFS= read -r src; do
    name=${src#"$here"/}
    name=${name#./}
    out=${src%.sol}.out
    sob=$work/case.sob
    got=$work/got
    err=$work/err
    cerr=$work/cerr
    rerr=$work/rerr

    what=$(field "$src" conformance)
    varies=$(field "$src" varies)
    status=$(field "$src" status)
    rule=$(field "$src" refused)
    [ -n "$status" ] || status=0

    if [ -z "$what" ]; then
        fail "$name" "no '; conformance:' line -- every case says what it pins"
        continue
    fi
    case $varies in
        front|machine|both) ;;
        "") fail "$name" "no '; varies:' line -- front, machine or both"; continue ;;
        *)  fail "$name" "'; varies: $varies' is not front, machine or both"; continue ;;
    esac

    # A refusal case. The compiler must reject it, and the neighbour beside it --
    # the same program with the one offending thing put right -- is what stops a
    # compiler that refuses everything from scoring full marks here.
    if [ -n "$rule" ]; then
        case $rule in
            */*) ;;
            *) fail "$name" "'; refused: $rule' is not a group/rule name"; continue ;;
        esac
        legal=${src%.sol}-legal.sol
        if [ ! -f "$legal" ]; then
            fail "$name" "no $(basename "$legal") beside it -- a refusal needs the legal neighbour it differs from"
            continue
        fi
        rm -f "$sob"
        set +e
        eval "$(printf "$SOL_COMPILE" "$src" "$sob")" > "$err" 2>&1
        built=$?
        set -e
        if [ "$built" = 0 ]; then
            fail "$name" "compiled, and '$rule' says it must be refused"
            continue
        fi
        passed=$((passed + 1))
        [ "$verbose" = no ] || printf 'ok    %s -- %s\n' "$name" "$what"
        continue
    fi

    if [ ! -f "$out" ]; then
        fail "$name" "no $(basename "$out") beside it -- a case is two files"
        continue
    fi

    rm -f "$sob"
    if ! eval "$(printf "$SOL_COMPILE" "$src" "$sob")" > "$cerr" 2>&1; then
        fail "$name" "refused by the compiler: $(head -1 "$cerr")"
        continue
    fi

    set +e
    eval "$(printf "$SOL_RUN" "$sob")" > "$got" 2> "$rerr" < /dev/null
    ran=$?
    set -e

    # What the compiler said on the way past counts as much as what the machine
    # said: a warning is at one end and a failure at the other, and a case that
    # claims silence is claiming it of both.
    cat "$cerr" "$rerr" > "$err"

    if [ "$status" = nonzero ]; then
        if [ "$ran" = 0 ]; then
            fail "$name" "ran to the end, and the case says it must stop"
            continue
        fi
    elif [ "$ran" != "$status" ]; then
        fail "$name" "left with status $ran, expected $status: $(head -1 "$err")"
        continue
    fi

    # Standard error carries the wording of a failure or a warning, which is the
    # implementation's to choose -- so it is never compared. Whether anything is
    # said there at all is not the implementation's business: a case that says
    # nothing is coming must be silent, and one that says something is coming
    # must not be. Otherwise the field would be a waiver rather than a claim.
    if [ "$status" = nonzero ] || [ "$(field "$src" stderr)" = expected ]; then
        if [ ! -s "$err" ]; then
            fail "$name" "said nothing on standard error, and the case says it must"
            continue
        fi
    elif [ -s "$err" ]; then
        fail "$name" "wrote to standard error: $(head -1 "$err")"
        continue
    fi
    if ! cmp -s "$got" "$out"; then
        fail "$name" "output differs from $(basename "$out"):"
        diff -u "$out" "$got" | sed -n '3,12p' | sed 's/^/      /' >> "$fails"
        continue
    fi

    passed=$((passed + 1))
    [ "$verbose" = no ] || printf 'ok    %s -- %s\n' "$name" "$what"
done < "$cases"

[ ! -s "$fails" ] || { echo; cat "$fails"; }

total=$((passed + failed))
printf '%s cases, %s passed, %s failed\n' "$total" "$passed" "$failed"
[ "$failed" = 0 ] || exit 1
echo "every case holds"
