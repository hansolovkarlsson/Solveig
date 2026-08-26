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
# For the article: DOSBox with QuickBASIC 4.5.
#
#   SOLA_QB_DIR   a directory holding BC.EXE, LINK.EXE and BCOM45.LIB.
#
# DOSBox is found on the PATH or inside /Applications/dosbox.app, which is where
# Homebrew's cask puts it and is why it is not on the PATH at all.
#
# **BC.EXE and not QB.EXE.** The QuickBASIC environment writes to the screen,
# which a script cannot read; the compiler makes a .EXE, and a .EXE's output
# redirects into a file the host can pick up off the mounted drive. That is the
# whole reason this wants QuickBASIC 4.5 rather than the QBasic 1.1 that came
# with MS-DOS, which has no compiler in it.
#
# DOS ends its lines with CR LF and this strips the CR before comparing, so a
# difference reported here is a difference in what was printed.

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

dosbox=""
for candidate in dosbox /Applications/dosbox.app/Contents/MacOS/DOSBox \
                 /Applications/DOSBox.app/Contents/MacOS/DOSBox; do
    if command -v "$candidate" >/dev/null 2>&1; then dosbox="$candidate"; break; fi
    if [ -x "$candidate" ]; then dosbox="$candidate"; break; fi
done

oracle_kind=""
if [ -n "${SOLA_ORACLE:-}" ]; then
    oracle_kind="SOLA_ORACLE"
elif [ -n "${SOLA_QB_DIR:-}" ] && [ -n "$dosbox" ]; then
    oracle_kind="dosbox"
elif command -v qb64pe >/dev/null 2>&1; then
    oracle_kind="qb64pe"
elif command -v qb64 >/dev/null 2>&1; then
    oracle_kind="qb64"
elif command -v fbc >/dev/null 2>&1; then
    oracle_kind="fbc"
fi

# A program that reads gets its answers from a .in beside it, on both sides.
stdin_for() {
    base=${1%.bas}
    if [ -f "$base.in" ]; then echo "$base.in"; else echo "/dev/null"; fi
}

run_oracle() {
    case "$oracle_kind" in
      SOLA_ORACLE) sh -c "$SOLA_ORACLE \"\$1\"" _ "$1" <"$(stdin_for "$1")" 2>&1 ;;
      qb64pe|qb64)
          "$oracle_kind" -x "$1" -o "$work/oracle_exe" >/dev/null 2>&1 \
              && "$work/oracle_exe" <"$(stdin_for "$1")" 2>&1 ;;
      fbc)
          fbc -lang qb "$1" -x "$work/oracle_exe" >/dev/null 2>&1 \
              && "$work/oracle_exe" <"$(stdin_for "$1")" 2>&1 ;;
      dosbox) run_dosbox "$1" ;;
    esac
}

# QuickBASIC 4.5 under DOSBox: compile, link against the standalone runtime,
# run with the output redirected, and read it back off the mounted drive.
run_dosbox() {
    rm -rf "$work/dos"
    mkdir -p "$work/dos"
    # **BC.EXE wants CR LF and says nothing when it does not get it.** A file
    # with Unix line endings compiles, links, produces a .EXE, and that .EXE
    # prints nothing at all -- which looks exactly like a program whose output
    # cannot be redirected, and cost an hour of looking at the wrong thing.
    sed 's/$/\r/' "$1" > "$work/dos/P.BAS"
    sed 's/$/\r/' "$(stdin_for "$1")" > "$work/dos/IN.TXT"
    SDL_VIDEODRIVER=dummy "$dosbox" \
        -c "mount c $SOLA_QB_DIR" \
        -c "mount d $work/dos" \
        -c "set LIB=C:\\" \
        -c "d:" \
        -c "c:\\BC.EXE P.BAS /O;" \
        -c "c:\\LINK.EXE P.OBJ,,NUL,C:\\BCOM45.LIB;" \
        -c "P.EXE < IN.TXT > OUT.TXT" \
        -c "exit" >"$work/dos/dosbox.log" 2>&1
    # **The .EXE is what says the toolchain worked, not the .TXT.** DOS creates
    # the file a redirection names before it discovers there is nothing to run,
    # so OUT.TXT exists either way -- and a missing BC.EXE would otherwise be
    # reported as though the program had printed "Illegal command".
    if [ -f "$work/dos/P.EXE" ] || [ -f "$work/dos/p.exe" ]; then
        tr -d '\r' < "$work/dos/OUT.TXT" 2>/dev/null
    else
        echo "(QuickBASIC produced no program to run -- is BC.EXE in SOLA_QB_DIR?)"
        tr -d '\r' < "$work/dos/OUT.TXT" 2>/dev/null | head -5
    fi
}

run_sola() {
    if "$root/bin/solvm" "$root/programs/sola.sob" "$1" "$work/prog.sob" \
            >/dev/null 2>&1; then
        # In its own directory, because a program may write files and the
        # DOS side is already confined to the drive it was given.
        ( cd "$work" && "$root/bin/solvm" "$work/prog.sob" ) \
            <"$(stdin_for "$1")" 2>&1
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
    if [ -n "$dosbox" ]; then
        echo "  DOSBox is here: $dosbox"
        echo "  Point SOLA_QB_DIR at a directory holding QuickBASIC 4.5's"
        echo "  BC.EXE, LINK.EXE and BCOM45.LIB, and this will use it."
    else
        echo "  SOLA_ORACLE='<command taking a .bas and printing its output>'"
        echo "  or install qb64 or fbc, or read the header for the DOSBox route."
    fi
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
