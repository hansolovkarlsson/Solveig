#!/bin/sh
#
# oracle.sh -- SolaBasic against a real QuickBASIC.
#
# Stage 7 of docs/SOLABASIC.md, and the only check here that can find something
# nobody thought of. Everything else this compiler is held to is a transcript
# recorded by its own author, which is exactly the failure basic.sol's header
# describes: eighty-three claims in that file caught none of the seven real
# defects the NBS suite found, because those check what the author thought to
# check.
#
# There are two kinds of program in oracle/ and the difference is the point:
#
#   agree/    must produce the same bytes under both. A difference here is
#             news, and is either a defect or a divergence nobody had written
#             down yet.
#   differ/   must NOT. Each one exercises a divergence the language definition
#             records, and each says at the top what each language should do.
#             A file here that suddenly agrees is also news -- it means the
#             divergence has gone, and the list should stop claiming it.
#
# So the divergence list stops being prose and becomes something that fails.
#
# Every program in agree/ says its types outright -- DEFINT, AS INTEGER, a
# suffix -- because QBasic's default numeric type is SINGLE and SolaBasic's is
# DOUBLE. A bare name is not the same variable in the two languages, and a file
# testing PRINT must not be testing that instead.
#
# ---------------------------------------------------------------------------
# Finding an oracle
#
# This repository has no dependencies beyond a C11 compiler and make, and this
# script does not change that: it is run when somebody wants to know, the way
# experiment/prove.sh is, and it says what it needs rather than installing it.
#
#   SOLA_ORACLE   a command taking a .bas path and printing what it prints.
#                 Anything that runs QuickBASIC will do.
#
# Failing that it looks for qb64, qb64pe or fbc. Those are reimplementations
# rather than the article, so a difference they report is worth less than one a
# real QuickBASIC 4.5 reports -- when they and SolaBasic disagree, either may be
# the one that is wrong.
#
# For the article: DOSBox with QuickBASIC 4.5, and **BC.EXE rather than QB.EXE**.
# The environment writes to the screen and cannot be redirected; the compiler
# makes a .EXE whose output can be. Roughly:
#
#     BC prog.bas;
#     LINK prog;
#     prog > out.txt
#
# Wrap that in a command, point SOLA_ORACLE at it, and this script does the rest.

set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
here="$root/programs/sola/oracle"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [ ! -f "$root/bin/solvm" ] || [ ! -f "$root/programs/sola.sob" ]; then
    echo "build first:  make && ./bin/solas programs/sola.sol"
    exit 1
fi

# ---------------------------------------------------------------------------
# Which oracle, if any

oracle_kind=""
if [ -n "${SOLA_ORACLE:-}" ]; then
    oracle_kind="SOLA_ORACLE"
elif command -v qb64pe >/dev/null 2>&1; then
    oracle_kind="qb64pe"
elif command -v qb64 >/dev/null 2>&1; then
    oracle_kind="qb64"
elif command -v fbc >/dev/null 2>&1; then
    oracle_kind="fbc"
fi

run_oracle() {
    case "$oracle_kind" in
      SOLA_ORACLE) sh -c "$SOLA_ORACLE \"\$1\"" _ "$1" 2>&1 ;;
      qb64pe|qb64)
          "$oracle_kind" -x "$1" -o "$work/oracle_exe" >/dev/null 2>&1 \
              && "$work/oracle_exe" 2>&1 ;;
      fbc)
          fbc -lang qb "$1" -x "$work/oracle_exe" >/dev/null 2>&1 \
              && "$work/oracle_exe" 2>&1 ;;
    esac
}

run_sola() {
    if "$root/bin/solvm" "$root/programs/sola.sob" "$1" "$work/prog.sob" \
            >/dev/null 2>&1; then
        "$root/bin/solvm" "$work/prog.sob" 2>&1
    else
        "$root/bin/solvm" "$root/programs/sola.sob" "$1" "$work/prog.sob" 2>&1
    fi
}

# ---------------------------------------------------------------------------
# With no oracle there is no verdict, so say so and check the corpus still runs

if [ -z "$oracle_kind" ]; then
    echo
    echo "No QuickBASIC to compare against, so there is no verdict."
    echo
    echo "  SOLA_ORACLE='<command taking a .bas and printing its output>'"
    echo "  or install qb64 or fbc, or read the header for the DOSBox route."
    echo
    echo "What the corpus does under SolaBasic alone:"
    echo
    failed=0
    for f in "$here"/agree/*.bas "$here"/differ/*.bas; do
        name=$(basename "$f" .bas)
        if "$root/bin/solvm" "$root/programs/sola.sob" "$f" "$work/prog.sob" \
                >/dev/null 2>&1; then
            printf '  %-14s compiles, %s lines out\n' "$name" \
                "$(run_sola "$f" | wc -l | tr -d ' ')"
        else
            printf '  %-14s WILL NOT COMPILE\n' "$name"
            failed=1
        fi
    done
    echo
    exit $((failed + 1))
fi

# ---------------------------------------------------------------------------
# The comparison

echo
echo "oracle: $oracle_kind"
echo

same=0
news=0

echo "agree/ -- these must match"
for f in "$here"/agree/*.bas; do
    name=$(basename "$f" .bas)
    run_sola "$f" > "$work/sola.out"
    run_oracle "$f" > "$work/oracle.out"
    if cmp -s "$work/sola.out" "$work/oracle.out"; then
        printf '  same      %s\n' "$name"
        same=$((same + 1))
    else
        printf '  DIFFERS   %s\n' "$name"
        diff -u "$work/oracle.out" "$work/sola.out" \
            | sed -e 's/^/            /' -e '1,2d'
        news=$((news + 1))
    fi
done

echo
echo "differ/ -- these must not, and each says why at the top of the file"
for f in "$here"/differ/*.bas; do
    name=$(basename "$f" .bas)
    run_sola "$f" > "$work/sola.out"
    run_oracle "$f" > "$work/oracle.out"
    if cmp -s "$work/sola.out" "$work/oracle.out"; then
        printf '  AGREES    %s -- the divergence has gone, and the list still claims it\n' "$name"
        news=$((news + 1))
    else
        printf '  differs   %s\n' "$name"
        sed -e 's/^/            oracle: /' "$work/oracle.out"
        sed -e 's/^/            sola:   /' "$work/sola.out"
    fi
done

echo
if [ "$news" -eq 0 ]; then
    echo "$same agree and every divergence is still there: nothing new."
    exit 0
fi
echo "$news to look at -- each is either a defect or a divergence nobody wrote down."
exit 1
